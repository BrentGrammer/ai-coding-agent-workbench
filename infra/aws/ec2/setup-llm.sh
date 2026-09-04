#!/usr/bin/env bash
# Installs Ollama and the cached Qwen model on the GPU box. Idempotent.
# The AMI ships the NVIDIA driver and CUDA, so there is no driver install
# and no reboot.
set -euo pipefail

# Pinned artifact versions and verification hashes.
AWS_CLI_GPG_KEY_ID="A6310ACC4672475C"
AWS_CLI_GPG_FINGERPRINT="FB5D B77F D5C1 18B8 0511  ADA8 A631 0ACC 4672 475C"

OLLAMA_VERSION="0.33.3"
OLLAMA_SHA256="c13cea8f3389db4145f8a6cb88d1747242a48639d7c13e3bda7c1ebdc6eebb2f"

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
  gnupg \
  iproute2 \
  jq \
  python3 \
  unzip \
  zstd

echo "== AWS CLI"
if ! command -v aws >/dev/null 2>&1; then
  aws_tmp="$(mktemp -d)"
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$aws_tmp/awscli.zip"
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip.sig" -o "$aws_tmp/awscli.zip.sig"

  gpg --import <<'GPGKEY'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBF2Cr7UBEADJZHcgusOJl7ENSyumXh85z0TRV0xJorM2B/JL0kHOyigQluUG
ZMLhENaG0bYatdrKP+3H91lvK050pXwnO/R7fB/FSTouki4ciIx5OuLlnJZIxSzx
PqGl0mkxImLNbGWoi6Lto0LYxqHN2iQtzlwTVmq9733zd3XfcXrZ3+LblHAgEt5G
TfNxEKJ8soPLyWmwDH6HWCnjZ/aIQRBTIQ05uVeEoYxSh6wOai7ss/KveoSNBbYz
gbdzoqI2Y8cgH2nbfgp3DSasaLZEdCSsIsK1u05CinE7k2qZ7KgKAUIcT/cR/grk
C6VwsnDU0OUCideXcQ8WeHutqvgZH1JgKDbznoIzeQHJD238GEu+eKhRHcz8/jeG
94zkcgJOz3KbZGYMiTh277Fvj9zzvZsbMBCedV1BTg3TqgvdX4bdkhf5cH+7NtWO
lrFj6UwAsGukBTAOxC0l/dnSmZhJ7Z1KmEWilro/gOrjtOxqRQutlIqG22TaqoPG
fYVN+en3Zwbt97kcgZDwqbuykNt64oZWc4XKCa3mprEGC3IbJTBFqglXmZ7l9ywG
EEUJYOlb2XrSuPWml39beWdKM8kzr1OjnlOm6+lpTRCBfo0wa9F8YZRhHPAkwKkX
XDeOGpWRj4ohOx0d2GWkyV5xyN14p2tQOCdOODmz80yUTgRpPVQUtOEhXQARAQAB
tCFBV1MgQ0xJIFRlYW0gPGF3cy1jbGlAYW1hem9uLmNvbT6JAlQEEwEIAD4CGwMF
CwkIBwIGFQoJCAsCBBYCAwECHgECF4AWIQT7Xbd/1cEYuAURraimMQrMRnJHXAUC
akV0ygUJDqP4lQAKCRCmMQrMRnJHXFHjD/9eyZLYcKuQOlLvtqSDtUBiEZf6ZZjM
i3ygYH8rJNtuToUH+HvSpe819urJCquXhDrlK6N+aqW0hCLtNABJG/vsafIgvIYJ
hSGgpgtNnQyMV1jViRWqPjbouw8OkYKBThUfT1i2Y+wn58ifs6ODBCmTexWtXspA
Si+Gt49xDOW0APmbOPnI+a4HJW6tVEo6MWS0WjzpiBayR3d1A4pt4YrPfSdDgpLo
h2SLQqlRqvvVZJaWBjhkErNFpfsBA06sDcPEOb0G8LBUbR4WOcdvhe5LubJbZuxC
AG9kNPCVeQP1ixwjgjXKysaxeQ6rv0VzIQgRp6tLVLWhy6AKDNvLjFSsmXZ1Wl08
Y/RlOHXlzLuQMRE6sR1wOdRxc9TsrNWTGiBK65cvSWOy03JeBkQQ8pesqltiyxI9
U21kkgiXtTSKNGfKK8pO27D81YANhRqPK7iTp6kuFiY2WtOg90KTMNlIT+Ff85Y2
b1rHj6Z0SrCkJujhWk3IBPic/wJgz01LEc/OAdUPlby90RJZcIBhSlWhT7mXnXIO
c0HWlNQrns2s3CTyYwZSiSlYe9ApeLwhjDo8NhbFuCAy61l6O5UsR4AfZxx/rGKv
2wFb1/RN/P4gNe6vmxZAPjR0AQcwD3tc2McimOLr/22kmPz8IH3I0X7WoSFr0Biz
E91G7bb0hOb/cA==
=knv7
-----END PGP PUBLIC KEY BLOCK-----
GPGKEY

  gpg --verify "$aws_tmp/awscli.zip.sig" "$aws_tmp/awscli.zip"
  unzip -q "$aws_tmp/awscli.zip" -d "$aws_tmp"
  "$aws_tmp/aws/install" --update
  rm -rf "$aws_tmp"
fi
aws --version

echo "== NVIDIA driver"
if ! nvidia-smi >/dev/null 2>&1; then
  echo "ERROR: nvidia-smi failed. This script expects a Deep Learning AMI," >&2
  echo "which ships the driver. Check the AMI in workbench-llm-stack.ts." >&2
  exit 1
fi

echo "== Ollama $OLLAMA_VERSION"
if ! command -v ollama >/dev/null 2>&1; then
  ollama_tmp="$(mktemp -d)"
  curl -fsSL "https://ollama.com/download/ollama-linux-amd64.tar.zst?version=${OLLAMA_VERSION}" -o "$ollama_tmp/ollama.tar.zst"
  echo "$OLLAMA_SHA256  $ollama_tmp/ollama.tar.zst" | sha256sum -c -
  tar -xf "$ollama_tmp/ollama.tar.zst" -C /usr
  rm -rf "$ollama_tmp"

  if ! id ollama >/dev/null 2>&1; then
    useradd -r -s /bin/false -U -m -d /usr/share/ollama ollama
  fi
  if getent group render >/dev/null 2>&1; then
    usermod -a -G render ollama
  fi
  if getent group video >/dev/null 2>&1; then
    usermod -a -G video ollama
  fi

  cat > /etc/systemd/system/ollama.service <<'EOF'
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
EOF
fi
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
