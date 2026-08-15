#!/usr/bin/env bash
# Installs NVIDIA drivers, Ollama, and the cached Qwen model on the GPU box.
# Idempotent. Reboots once after the driver install, then continues via systemd.
set -euo pipefail

LLM_MODEL_DIR=/usr/share/ollama/.ollama/models
TAILSCALE_AUTH_KEY_PARAMETER=/coding-agent-workbench/tailscale/llm-auth-key
SETUP_STATE_DIR=/var/lib/agent-workbench
CONTINUE_SERVICE=/etc/systemd/system/llm-setup.service

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
  jq \
  linux-headers-generic \
  ubuntu-drivers-common \
  unzip

echo "== AWS CLI"
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
  tailscale_auth_key="$(aws ssm get-parameter \
    --region "$AWS_REGION" \
    --name "$TAILSCALE_AUTH_KEY_PARAMETER" \
    --with-decryption \
    --query Parameter.Value \
    --output text 2>/dev/null || true)"
  if [ -n "$tailscale_auth_key" ]; then
    tailscale up --ssh --hostname agent-llm --auth-key "$tailscale_auth_key" ||
      echo "WARN: Tailscale did not accept the stored auth key. Join by hand: sudo tailscale up --ssh --hostname agent-llm" >&2
  else
    echo "WARN: No auth key at $TAILSCALE_AUTH_KEY_PARAMETER. Join by hand: sudo tailscale up --ssh --hostname agent-llm" >&2
  fi
  unset tailscale_auth_key
fi

echo "== NVIDIA driver"
if ! nvidia-smi >/dev/null 2>&1; then
  if [ -f "$SETUP_STATE_DIR/nvidia-installed" ]; then
    echo "ERROR: NVIDIA driver is installed but nvidia-smi failed." >&2
    exit 1
  fi
  ubuntu-drivers install --gpgpu || ubuntu-drivers autoinstall
  touch "$SETUP_STATE_DIR/nvidia-installed"
  cat > "$CONTINUE_SERVICE" <<EOF
[Unit]
Description=Continue workbench LLM setup after the NVIDIA driver reboot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/agent-workbench/infra/aws/ec2/setup-llm.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable llm-setup.service
  echo "== Rebooting to load the NVIDIA driver"
  reboot
  exit 0
fi

echo "== Ollama"
command -v ollama >/dev/null 2>&1 || curl -fsSL https://ollama.com/install.sh | sh
install -d -m 755 /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf <<'EOF'
[Service]
Environment=OLLAMA_HOST=0.0.0.0:11434
Environment=OLLAMA_CONTEXT_LENGTH=32768
EOF
systemctl daemon-reload
systemctl enable --now ollama
systemctl restart ollama

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

if [ -f "$CONTINUE_SERVICE" ]; then
  systemctl disable llm-setup.service || true
  rm -f "$CONTINUE_SERVICE"
  systemctl daemon-reload
fi

echo "== Done. Serving $LLM_MODEL on http://agent-llm:11434/v1"
