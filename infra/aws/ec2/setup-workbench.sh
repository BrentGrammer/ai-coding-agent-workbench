#!/usr/bin/env bash
# Installs and updates everything on the EC2 workbench. Idempotent: cloud-init
# runs it on first boot, and `workbench ec2 update` re-runs it for updates.
set -euo pipefail

NODE_MAJOR=24
PI_VERSION=0.84.4

WORKBENCH_USER=ubuntu
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run this script as root: sudo $0" >&2
  exit 1
fi

install -d -m 755 /etc/agent-workbench
touch /etc/agent-workbench/workbench.env
chmod 644 /etc/agent-workbench/workbench.env
sed -i '/^GITHUB_APP_TOKEN_FUNCTION_NAME=/d' /etc/agent-workbench/workbench.env
grep -q '^LOCAL_LLM_MODEL=' /etc/agent-workbench/workbench.env ||
  echo 'LOCAL_LLM_MODEL=qwen3.8:27b' >> /etc/agent-workbench/workbench.env
grep -q '^WORKBENCH_INSTANCE=' /etc/agent-workbench/workbench.env ||
  echo 'WORKBENCH_INSTANCE=true' >> /etc/agent-workbench/workbench.env

export DEBIAN_FRONTEND=noninteractive

echo "== System packages"
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  git \
  jq \
  less \
  ncurses-term \
  unattended-upgrades \
  unzip

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

echo "== Node $NODE_MAJOR"
if ! command -v node >/dev/null 2>&1 ||
  [ "$(node --version | sed 's/^v//' | cut -d. -f1)" != "$NODE_MAJOR" ]; then
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
  apt-get install -y nodejs
fi

echo "== AWS CLI"
if ! command -v aws >/dev/null 2>&1; then
  aws_tmp="$(mktemp -d)"
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "$aws_tmp/awscli.zip"
  unzip -q "$aws_tmp/awscli.zip" -d "$aws_tmp"
  "$aws_tmp/aws/install"
  rm -rf "$aws_tmp"
fi

echo "== Workbench files"
install -d -m 755 /etc/agent-workbench

install -m 755 "$REPO_DIR/infra/aws/ec2/workbench-idle-stop" /usr/local/bin/workbench-idle-stop
ln -sfn /opt/agent-workbench/bin/start-pi /usr/local/bin/start-pi

install -m 644 "$REPO_DIR/infra/aws/ec2/agent-workbench-profile.sh" /etc/profile.d/agent-workbench.sh
install -m 644 "$REPO_DIR/infra/aws/ec2/login-welcome" /etc/agent-workbench/login-welcome

echo "== Remove leftover GitHub token chain"
systemctl disable --now github-token-relay.service 2>/dev/null || true
rm -f /etc/systemd/system/github-token-relay.service
rm -f /usr/local/bin/git-credential-github-app
rm -f /usr/local/lib/agent-workbench/github-token-relay.mjs \
  /usr/local/lib/agent-workbench/github-app-token-client.mjs \
  /usr/local/lib/agent-workbench/github-token-relay-service.mjs
helper="$(sudo -u "$WORKBENCH_USER" -H git config --global --get credential.helper 2>/dev/null || true)"
if [ "$helper" = "/usr/local/bin/git-credential-github-app" ]; then
  sudo -u "$WORKBENCH_USER" -H git config --global --unset-all credential.helper || true
  sudo -u "$WORKBENCH_USER" -H git config --global --unset-all credential.useHttpPath || true
fi

echo "== Swap"
if [ ! -f /swapfile ]; then
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
fi
grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
swapon -a

echo "== systemd units"
install -m 644 "$REPO_DIR/infra/aws/ec2/workbench-idle-stop.service" /etc/systemd/system/workbench-idle-stop.service
install -m 644 "$REPO_DIR/infra/aws/ec2/workbench-idle-stop.timer" /etc/systemd/system/workbench-idle-stop.timer
systemctl daemon-reload
systemctl enable workbench-idle-stop.timer
systemctl start workbench-idle-stop.timer

echo "== Agent CLIs for $WORKBENCH_USER"
sudo -u "$WORKBENCH_USER" -H \
  env PI_VERSION="$PI_VERSION" \
  bash -s <<'USER_SETUP'
set -euo pipefail

export NPM_CONFIG_PREFIX="$HOME/.local/npm"
export PATH="$HOME/.local/npm/bin:$HOME/.local/bin:$PATH"
mkdir -p "$HOME/.local/npm" "$HOME/.local/bin" "$HOME/workspace"

# The npm prefix is user-owned so Pi can update itself later.
npm install -g --ignore-scripts "@earendil-works/pi-coding-agent@${PI_VERSION}"
pi --version

if ! command -v agy >/dev/null 2>&1; then
  curl -fsSL https://antigravity.google/cli/install.sh | bash
fi
agy --version

mkdir -p "$HOME/.pi/agent"

if ! git config --global user.name >/dev/null 2>&1 ||
   ! git config --global user.email >/dev/null 2>&1; then
  echo "NOTE: Set your git identity on the box:"
  echo "  git config --global user.name 'Your Name'"
  echo "  git config --global user.email 'you@example.com'"
fi
USER_SETUP

echo "== Done"
echo "The workbench is ready. Connect with start-workbench, then run agy or pi."
