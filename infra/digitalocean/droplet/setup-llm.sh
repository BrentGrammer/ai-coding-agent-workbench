#!/usr/bin/env bash
# Installs Ollama and the cached Qwen model on a DigitalOcean GPU droplet.
# Idempotent.
set -euo pipefail

LLM_MODEL_DIR=/usr/share/ollama/.ollama/models
# Cloud-init sets no HOME, and the Ollama CLI panics reading $HOME/.ollama.
export OLLAMA_MODELS="$LLM_MODEL_DIR"
LLM_PROXY_PORT=11435
DIGITALOCEAN_DIR=/opt/agent-workbench/infra/digitalocean/droplet
INFERENCE_PROXY_SCRIPT=/opt/agent-workbench/tools/llm/ollama_inference_proxy.py
SETUP_STATE_DIR=/var/lib/agent-workbench

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run this script as root: sudo $0" >&2
  exit 1
fi

if [ ! -f /etc/agent-workbench/workbench.env ]; then
  echo "ERROR: /etc/agent-workbench/workbench.env is missing." >&2
  exit 1
fi
# shellcheck disable=SC1091
. /etc/agent-workbench/workbench.env

if [ ! -f /etc/agent-workbench/digitalocean-secrets.env ]; then
  echo "ERROR: /etc/agent-workbench/digitalocean-secrets.env is missing." >&2
  exit 1
fi
chmod 600 /etc/agent-workbench/digitalocean-secrets.env
# shellcheck disable=SC1091
. /etc/agent-workbench/digitalocean-secrets.env

: "${SPACES_REGION:?SPACES_REGION is not set in workbench.env}"
: "${LLM_CACHE_BUCKET:?LLM_CACHE_BUCKET is not set in workbench.env}"
: "${LLM_MODEL:?LLM_MODEL is not set in workbench.env}"
: "${DIGITALOCEAN_LLM_DESTROY_TOKEN:?DIGITALOCEAN_LLM_DESTROY_TOKEN is not set in digitalocean-secrets.env}"
: "${TAILSCALE_AUTH_KEY:?TAILSCALE_AUTH_KEY is not set in digitalocean-secrets.env}"
: "${SPACES_ACCESS_KEY_ID:?SPACES_ACCESS_KEY_ID is not set in digitalocean-secrets.env}"
: "${SPACES_SECRET_ACCESS_KEY:?SPACES_SECRET_ACCESS_KEY is not set in digitalocean-secrets.env}"
OLLAMA_CONTEXT_LENGTH="${OLLAMA_CONTEXT_LENGTH:-131072}"
SPACES_ENDPOINT="https://${SPACES_REGION}.digitaloceanspaces.com"

mkdir -p "$SETUP_STATE_DIR"
exec 9>"$SETUP_STATE_DIR/setup.lock"
flock -n 9 || exit 0
export DEBIAN_FRONTEND=noninteractive

# A powered-off GPU droplet bills at the full rate, so the fuse must destroy
# the droplet through the API. Plain `shutdown -h` would keep billing.
install -m 755 "$DIGITALOCEAN_DIR/llm-self-destroy" /usr/local/bin/llm-self-destroy
systemctl stop llm-fuse.timer 2>/dev/null || true
systemd-run --on-active=720min --unit=llm-fuse /usr/local/bin/llm-self-destroy
echo "== 12-hour fuse set"

echo "== Metadata lock"
# User data holds the secrets above and the metadata service serves it to any
# local process without auth. Only root may reach it.
iptables -C OUTPUT -d 169.254.169.254 -m owner ! --uid-owner 0 -j REJECT 2>/dev/null ||
  iptables -A OUTPUT -d 169.254.169.254 -m owner ! --uid-owner 0 -j REJECT

echo "== System packages"
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  iproute2 \
  jq \
  python3 \
  unzip

echo "== AWS CLI"
# Spaces speaks the S3 API, so the same CLI syncs the model cache.
if ! command -v aws >/dev/null 2>&1; then
  aws_tmp="$(mktemp -d)"
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$aws_tmp/awscli.zip"
  unzip -q "$aws_tmp/awscli.zip" -d "$aws_tmp"
  "$aws_tmp/aws/install"
  rm -rf "$aws_tmp"
fi

echo "== Tailscale"
command -v tailscale >/dev/null 2>&1 || curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable --now tailscaled
if ! tailscale status >/dev/null 2>&1; then
  tailscale up --ssh --hostname agent-llm --auth-key "$TAILSCALE_AUTH_KEY" ||
    echo "WARN: Tailscale did not accept the auth key. Join by hand: sudo tailscale up --ssh --hostname agent-llm" >&2
fi

echo "== NVIDIA driver"
if ! nvidia-smi >/dev/null 2>&1; then
  echo "ERROR: nvidia-smi failed. This script expects the AI/ML-ready image" >&2
  echo "(gpu-h100x1-base), which ships the driver. Check the image slug in bin/workbench." >&2
  exit 1
fi

echo "== Ollama"
command -v ollama >/dev/null 2>&1 || curl -fsSL https://ollama.com/install.sh | sh
install -d -m 755 /etc/systemd/system/ollama.service.d
# A q8_0 KV cache halves what the context costs (~128 KB/token) but can cost
# quality at long context. 131K is the known-safe edge; check output past it.
cat > /etc/systemd/system/ollama.service.d/override.conf <<EOF
[Service]
Environment=OLLAMA_HOST=127.0.0.1:11434
Environment=OLLAMA_CONTEXT_LENGTH=$OLLAMA_CONTEXT_LENGTH
Environment=OLLAMA_FLASH_ATTENTION=1
Environment=OLLAMA_KV_CACHE_TYPE=q8_0
Environment=OLLAMA_NUM_PARALLEL=1
# Loading 15 GB into VRAM costs about 3 minutes, so stay warm across a session.
# llm-idle-stop reads a loaded model as in use, so this also sets the idle floor.
Environment=OLLAMA_KEEP_ALIVE=59m
EOF
systemctl daemon-reload
systemctl enable --now ollama
systemctl restart ollama

echo "== Inference-only proxy"
# The tailnet reaches this proxy, not Ollama. The Ollama port also pulls,
# creates, and deletes models, and a pull fetches from any registry host the
# caller names.
cat > /etc/systemd/system/llm-inference-proxy.service <<EOF
[Unit]
Description=Serves only the inference routes of Ollama
After=ollama.service
Wants=ollama.service

[Service]
ExecStart=/usr/bin/python3 $INFERENCE_PROXY_SCRIPT 0.0.0.0:$LLM_PROXY_PORT 127.0.0.1:11434
DynamicUser=yes
NoNewPrivileges=yes
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable llm-inference-proxy.service
systemctl restart llm-inference-proxy.service

echo "== Model $LLM_MODEL"
install -d -m 755 -o ollama -g ollama "$LLM_MODEL_DIR"
export AWS_ACCESS_KEY_ID="$SPACES_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$SPACES_SECRET_ACCESS_KEY"
# Spaces ignores the region but the CLI refuses to run without one.
export AWS_DEFAULT_REGION=us-east-1
cache_prefix="s3://${LLM_CACHE_BUCKET}/${LLM_MODEL}"
cache_complete="${cache_prefix}/_COMPLETE"
if aws s3api head-object \
  --bucket "$LLM_CACHE_BUCKET" \
  --key "${LLM_MODEL}/_COMPLETE" \
  --endpoint-url "$SPACES_ENDPOINT" >/dev/null 2>&1; then
  echo "== Restoring model from Spaces cache"
  aws s3 sync "${cache_prefix}/" "$LLM_MODEL_DIR/" \
    --exclude "_COMPLETE" \
    --endpoint-url "$SPACES_ENDPOINT"
  chown -R ollama:ollama /usr/share/ollama/.ollama
  systemctl restart ollama
else
  echo "== Cache miss: pulling $LLM_MODEL"
  ollama pull "$LLM_MODEL"
  chown -R ollama:ollama /usr/share/ollama/.ollama
  echo "== Uploading model to Spaces cache"
  aws s3 rm "$cache_complete" --endpoint-url "$SPACES_ENDPOINT" 2>/dev/null || true
  if aws s3 sync "$LLM_MODEL_DIR/" "${cache_prefix}/" \
    --exclude "_COMPLETE" \
    --endpoint-url "$SPACES_ENDPOINT"; then
    printf 'ok\n' | aws s3 cp - "$cache_complete" --endpoint-url "$SPACES_ENDPOINT"
  else
    echo "WARN: Could not upload the model cache to Spaces." >&2
  fi
fi

echo "== Warming the model"
# Pay the load now, while the user is already waiting on llm up.
# num_predict 1 because loading the model is the point, not the answer.
curl -fsS http://127.0.0.1:11434/api/generate \
  -d "{\"model\":\"$LLM_MODEL\",\"prompt\":\"hi\",\"stream\":false,\"options\":{\"num_predict\":1}}" \
  >/dev/null || echo "WARN: Could not warm the model." >&2

# Last, so the timer never runs while the model is still restoring.
echo "== Idle stop"
install -m 755 "$DIGITALOCEAN_DIR/llm-idle-stop" /usr/local/bin/llm-idle-stop
install -m 644 "$DIGITALOCEAN_DIR/llm-idle-stop.service" /etc/systemd/system/
install -m 644 "$DIGITALOCEAN_DIR/llm-idle-stop.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now llm-idle-stop.timer

echo "== Done. Serving $LLM_MODEL on http://agent-llm:$LLM_PROXY_PORT/v1"
