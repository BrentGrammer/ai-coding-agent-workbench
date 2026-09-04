#!/usr/bin/env bash
# Installs Ollama and the cached Qwen model on the GPU box. Idempotent.
# The AMI ships the NVIDIA driver and CUDA, so there is no driver install
# and no reboot.
set -euo pipefail

LLM_MODEL_DIR=/usr/share/ollama/.ollama/models
# Cloud-init sets no HOME, and the Ollama CLI panics reading $HOME/.ollama.
export OLLAMA_MODELS="$LLM_MODEL_DIR"
LLM_PROXY_PORT=11435
EC2_DIR=/opt/agent-workbench/infra/aws/ec2
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

: "${AWS_REGION:?AWS_REGION is not set in workbench.env}"
: "${LLM_CACHE_BUCKET:?LLM_CACHE_BUCKET is not set in workbench.env}"
: "${LLM_MODEL:?LLM_MODEL is not set in workbench.env}"
OLLAMA_CONTEXT_LENGTH="${OLLAMA_CONTEXT_LENGTH:-131072}"
OLLAMA_KV_CACHE_TYPE="${OLLAMA_KV_CACHE_TYPE:-q8_0}"

mkdir -p "$SETUP_STATE_DIR"
exec 9>"$SETUP_STATE_DIR/setup.lock"
flock -n 9 || exit 0
export DEBIAN_FRONTEND=noninteractive

shutdown -c 2>/dev/null || true
shutdown -h +720
echo "== 12-hour fuse set"

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
if ! command -v aws >/dev/null 2>&1; then
  aws_tmp="$(mktemp -d)"
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$aws_tmp/awscli.zip"
  unzip -q "$aws_tmp/awscli.zip" -d "$aws_tmp"
  "$aws_tmp/aws/install"
  rm -rf "$aws_tmp"
fi

echo "== NVIDIA driver"
if ! nvidia-smi >/dev/null 2>&1; then
  echo "ERROR: nvidia-smi failed. This script expects a Deep Learning AMI," >&2
  echo "which ships the driver. Check the AMI in workbench-llm-stack.ts." >&2
  exit 1
fi

echo "== Ollama"
command -v ollama >/dev/null 2>&1 || curl -fsSL https://ollama.com/install.sh | sh
install -d -m 755 /etc/systemd/system/ollama.service.d
# q8_0 halves what the context costs in KV cache but can cost quality at long
# context. It is required on the 24 GB card; use f16 on a 48 GB one.
cat > /etc/systemd/system/ollama.service.d/override.conf <<EOF
[Service]
Environment=OLLAMA_HOST=127.0.0.1:11434
Environment=OLLAMA_CONTEXT_LENGTH=$OLLAMA_CONTEXT_LENGTH
Environment=OLLAMA_FLASH_ATTENTION=1
Environment=OLLAMA_KV_CACHE_TYPE=$OLLAMA_KV_CACHE_TYPE
Environment=OLLAMA_NUM_PARALLEL=1
# Loading 15 GB into VRAM costs about 3 minutes, so stay warm across a session.
# llm-idle-stop reads a loaded model as in use, so this also sets the idle floor.
Environment=OLLAMA_KEEP_ALIVE=59m
EOF
systemctl daemon-reload
systemctl enable --now ollama
systemctl restart ollama

echo "== Inference-only proxy"
# The workbench reaches this proxy, not Ollama. The Ollama port also pulls,
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
cache_prefix="s3://${LLM_CACHE_BUCKET}/${LLM_MODEL}"
cache_complete="${cache_prefix}/_COMPLETE"
if aws s3api head-object \
  --bucket "$LLM_CACHE_BUCKET" \
  --key "${LLM_MODEL}/_COMPLETE" \
  --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "== Restoring model from S3 cache"
  aws s3 sync "${cache_prefix}/" "$LLM_MODEL_DIR/" \
    --exclude "_COMPLETE" \
    --region "$AWS_REGION"
  chown -R ollama:ollama /usr/share/ollama/.ollama
  systemctl restart ollama
else
  echo "== Cache miss: pulling $LLM_MODEL"
  ollama pull "$LLM_MODEL"
  chown -R ollama:ollama /usr/share/ollama/.ollama
  echo "== Uploading model to S3 cache"
  aws s3 rm "$cache_complete" --region "$AWS_REGION" 2>/dev/null || true
  if aws s3 sync "$LLM_MODEL_DIR/" "${cache_prefix}/" \
    --exclude "_COMPLETE" \
    --region "$AWS_REGION"; then
    printf 'ok\n' | aws s3 cp - "$cache_complete" --region "$AWS_REGION"
  else
    echo "WARN: Could not upload the model cache to S3." >&2
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
install -m 755 "$EC2_DIR/llm-idle-stop" /usr/local/bin/llm-idle-stop
install -m 644 "$EC2_DIR/llm-idle-stop.service" /etc/systemd/system/
install -m 644 "$EC2_DIR/llm-idle-stop.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now llm-idle-stop.timer

echo "== Done. Serving $LLM_MODEL on port $LLM_PROXY_PORT inside the VPC"
