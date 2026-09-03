#!/usr/bin/env bash
# Installs and updates everything on the EC2 workbench. Idempotent: cloud-init
# runs it on first boot, and `workbench ec2 update` re-runs it for updates.
set -euo pipefail

NODE_MAJOR=24
HERDR_VERSION=0.8.0
CLAUDE_CODE_VERSION=2.1.233
CODEX_VERSION=0.148.0
OPENCODE_VERSION=1.18.21
GH_AXI_VERSION=0.1.30
NPM_AXI_VERSION=0.1.1
SKILLS_CLI_VERSION=1.5.23
PI_VERSION=0.84.4

WORKBENCH_USER=ubuntu
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run this script as root: sudo $0" >&2
  exit 1
fi

if [ ! -f /etc/agent-workbench/workbench.env ]; then
  echo "WARN: /etc/agent-workbench/workbench.env is missing." >&2
  echo "WARN: Write AWS_REGION and GITHUB_APP_TOKEN_FUNCTION_NAME to it, or the token chain cannot work." >&2
fi
install -d -m 755 /etc/agent-workbench
touch /etc/agent-workbench/workbench.env
chmod 644 /etc/agent-workbench/workbench.env
grep -q '^LOCAL_LLM_BASE_URL=' /etc/agent-workbench/workbench.env ||
  echo 'LOCAL_LLM_BASE_URL=http://agent-llm:11435/v1' >> /etc/agent-workbench/workbench.env
grep -q '^LOCAL_LLM_MODEL=' /etc/agent-workbench/workbench.env ||
  echo 'LOCAL_LLM_MODEL=qwen3.8:27b' >> /etc/agent-workbench/workbench.env

export DEBIAN_FRONTEND=noninteractive

echo "== System packages"
apt-get update
apt-get install -y --no-install-recommends \
  bubblewrap \
  ca-certificates \
  curl \
  git \
  jq \
  less \
  mosh \
  ncurses-term \
  socat \
  unattended-upgrades \
  unzip

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

echo "== Docker"
apt-get install -y --no-install-recommends docker.io docker-compose-v2
usermod -aG docker "$WORKBENCH_USER"
systemctl enable --now docker

echo "== AppArmor profile for bwrap"
install -m 644 "$REPO_DIR/infra/aws/ec2/apparmor-bwrap" /etc/apparmor.d/bwrap
apparmor_parser --replace /etc/apparmor.d/bwrap

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

echo "== Tailscale"
command -v tailscale >/dev/null 2>&1 || curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable --now tailscaled
if ! tailscale status >/dev/null 2>&1; then
  [ -f /etc/agent-workbench/workbench.env ] && . /etc/agent-workbench/workbench.env
  tailscale_auth_key="$(aws ssm get-parameter \
    --region "${AWS_REGION:-}" \
    --name /coding-agent-workbench/tailscale/auth-key \
    --with-decryption \
    --query Parameter.Value \
    --output text 2>/dev/null || true)"
  if [ -n "$tailscale_auth_key" ]; then
    tailscale up --ssh --hostname agent-workbench --auth-key "$tailscale_auth_key" ||
      echo "WARN: Tailscale did not accept the stored auth key. Join by hand: sudo tailscale up --ssh" >&2
  else
    echo "WARN: No auth key at /coding-agent-workbench/tailscale/auth-key. Join by hand: sudo tailscale up --ssh" >&2
  fi
  unset tailscale_auth_key
fi

echo "== Herdr $HERDR_VERSION"
if ! /usr/local/bin/herdr --version 2>/dev/null | grep -q "$HERDR_VERSION"; then
  herdr_tmp="$(mktemp /usr/local/bin/herdr.XXXXXX)"
  trap 'rm -f "$herdr_tmp"' EXIT
  curl -fsSL "https://github.com/herdrdev/herdr/releases/download/v${HERDR_VERSION}/herdr-linux-aarch64" -o "$herdr_tmp"
  chmod 755 "$herdr_tmp"
  "$herdr_tmp" --version | grep -q "$HERDR_VERSION"
  mv -f "$herdr_tmp" /usr/local/bin/herdr
  trap - EXIT
  /usr/local/bin/herdr --version
fi

echo "== Workbench files"
install -d -m 755 /etc/agent-workbench /etc/claude-code /usr/local/libexec /usr/local/lib/agent-workbench
rm -f /usr/local/bin/herdr-pane

install -m 755 "$REPO_DIR/runtime/herdr-session" /usr/local/bin/herdr-session
install -m 755 "$REPO_DIR/runtime/workbench-pane-shell" /usr/local/bin/workbench-pane-shell
install -m 755 "$REPO_DIR/runtime/deny-protected-file-reads" /usr/local/bin/deny-protected-file-reads
install -m 644 "$REPO_DIR/runtime/herdr-config.toml" /etc/agent-workbench/herdr-config.toml

install -m 755 "$REPO_DIR/infra/aws/runtime/git-credential-github-app.mjs" /usr/local/bin/git-credential-github-app
install -m 755 "$REPO_DIR/infra/aws/runtime/socat-ipv4" /usr/local/libexec/socat-ipv4
install -m 644 "$REPO_DIR/infra/aws/runtime/github-token-relay.mjs" /usr/local/lib/agent-workbench/github-token-relay.mjs
install -m 644 "$REPO_DIR/infra/aws/runtime/github-app-token-client.mjs" /usr/local/lib/agent-workbench/github-app-token-client.mjs
install -m 644 "$REPO_DIR/infra/aws/ec2/github-token-relay-service.mjs" /usr/local/lib/agent-workbench/github-token-relay-service.mjs

install -m 644 "$REPO_DIR/tools/agents/local_llm.sh" /usr/local/lib/agent-workbench/local_llm.sh
install -m 755 "$REPO_DIR/infra/aws/ec2/start-herdr" /usr/local/bin/start-herdr
rm -f /usr/local/bin/workbench-open
install -m 755 "$REPO_DIR/infra/aws/ec2/workbench-idle-stop" /usr/local/bin/workbench-idle-stop

install -m 644 "$REPO_DIR/tools/agents/config/claude/settings.json" /etc/claude-code/managed-settings.json
install -m 644 "$REPO_DIR/tools/agents/config/codex/config.toml" /etc/agent-workbench/codex-config.toml
install -m 644 "$REPO_DIR/tools/agents/config/cursor/cli-config.json" /etc/agent-workbench/cursor-cli-config.json

install -m 644 "$REPO_DIR/infra/aws/ec2/agent-workbench-profile.sh" /etc/profile.d/agent-workbench.sh
install -m 644 "$REPO_DIR/infra/aws/ec2/login-welcome" /etc/agent-workbench/login-welcome

echo "== Swap"
if [ ! -f /swapfile ]; then
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
fi
grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
swapon -a

echo "== systemd units"
install -m 644 "$REPO_DIR/infra/aws/ec2/github-token-relay.service" /etc/systemd/system/github-token-relay.service
install -m 644 "$REPO_DIR/infra/aws/ec2/workbench-idle-stop.service" /etc/systemd/system/workbench-idle-stop.service
install -m 644 "$REPO_DIR/infra/aws/ec2/workbench-idle-stop.timer" /etc/systemd/system/workbench-idle-stop.timer
systemctl daemon-reload
systemctl enable github-token-relay.service workbench-idle-stop.timer
systemctl restart github-token-relay.service
systemctl start workbench-idle-stop.timer

echo "== Agent CLIs and skills for $WORKBENCH_USER"
sudo -u "$WORKBENCH_USER" -H \
  env REPO_DIR="$REPO_DIR" \
  CLAUDE_CODE_VERSION="$CLAUDE_CODE_VERSION" \
  CODEX_VERSION="$CODEX_VERSION" \
  OPENCODE_VERSION="$OPENCODE_VERSION" \
  GH_AXI_VERSION="$GH_AXI_VERSION" \
  NPM_AXI_VERSION="$NPM_AXI_VERSION" \
  SKILLS_CLI_VERSION="$SKILLS_CLI_VERSION" \
  PI_VERSION="$PI_VERSION" \
  bash -s <<'USER_SETUP'
set -euo pipefail

export NPM_CONFIG_PREFIX="$HOME/.local/npm"
export PATH="$HOME/.local/npm/bin:$HOME/.local/bin:$PATH"
mkdir -p "$HOME/.local/npm" "$HOME/.local/bin" "$HOME/workspace"

# The npm prefix is user-owned so the agents can update themselves later.
npm install -g --ignore-scripts \
  "@openai/codex@${CODEX_VERSION}" \
  "opencode-ai@${OPENCODE_VERSION}" \
  "gh-axi@${GH_AXI_VERSION}" \
  "npm-axi@${NPM_AXI_VERSION}" \
  "@earendil-works/pi-coding-agent@${PI_VERSION}"

# Claude Code needs its install scripts to run so that `claude update` works.
# Override the .npmrc ignore-scripts policy for this package only.
npm install -g --ignore-scripts=false "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}"
(cd "$(npm root -g)/opencode-ai" && node postinstall.mjs)
claude --version
codex --version
opencode --version
gh-axi --version
npm-axi --version
pi --version

command -v cursor-agent >/dev/null 2>&1 || curl -fsS https://cursor.com/install | bash

# The Devin installer ends with an interactive login, which needs a TTY. Skip it
# here; sign-in happens the first time the harness runs.
if ! command -v devin >/dev/null 2>&1; then
  devin_installer="$(mktemp)"
  curl -fsSL https://cli.devin.ai/install.sh -o "$devin_installer"
  bash "$devin_installer" </dev/null || true
  rm -f "$devin_installer"
fi
command -v devin >/dev/null 2>&1 || { echo "ERROR: The Devin CLI did not install." >&2; exit 1; }

git config --global credential.helper /usr/local/bin/git-credential-github-app
git config --global credential.useHttpPath true

mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.config/opencode" "$HOME/.cursor" "$HOME/.agents/skills"

install -m 600 /etc/agent-workbench/codex-config.toml "$HOME/.codex/config.toml"
install -m 600 /etc/agent-workbench/cursor-cli-config.json "$HOME/.cursor/cli-config.json"

if [ ! -f "$HOME/.cursor/mcp.json" ]; then
  cat > "$HOME/.cursor/mcp.json" <<'EOF'
{
  "mcpServers": {
    "exa": {
      "type": "http",
      "url": "https://mcp.exa.ai/mcp"
    }
  }
}
EOF
  chmod 600 "$HOME/.cursor/mcp.json"
fi

# Global scope on purpose, not managed scope, so the user can change the
# model (audit finding #5). Seed once and never overwrite.
if [ ! -f "$HOME/.config/opencode/opencode.json" ]; then
  install -m 600 "$REPO_DIR/tools/agents/config/opencode/opencode.json" "$HOME/.config/opencode/opencode.json"
fi
if [ -f "$HOME/.config/opencode/opencode.json" ]; then
  if ! jq -e '.mcp.exa' "$HOME/.config/opencode/opencode.json" >/dev/null 2>&1; then
    tmp_json="$(mktemp)"
    jq '.mcp.exa = {"type": "remote", "url": "https://mcp.exa.ai/mcp", "enabled": true}' \
      "$HOME/.config/opencode/opencode.json" > "$tmp_json" && mv "$tmp_json" "$HOME/.config/opencode/opencode.json"
    chmod 600 "$HOME/.config/opencode/opencode.json"
  fi
fi

for agent_name in claude codex opencode cursor devin pi; do
  herdr integration install "$agent_name"
done

echo "Installing the Matt Pocock skills plugin for Claude Code..."
if claude plugin list 2>/dev/null | grep -q mattpocock-skills; then
  claude plugin update mattpocock-skills </dev/null >/dev/null 2>&1 || true
else
  claude plugin marketplace add mattpocock/skills </dev/null >/dev/null 2>&1 || true
  claude plugin install mattpocock-skills@mattpocock </dev/null >/dev/null 2>&1 || true
fi
if ! claude plugin list 2>/dev/null | grep -q mattpocock-skills; then
  echo "WARN: The Matt Pocock skills plugin did not install for Claude Code." >&2
fi

echo "Installing Matt Pocock skills for Codex, OpenCode, and Cursor..."
if ! (
  cd "$HOME"
  npx --yes "skills@${SKILLS_CLI_VERSION}" add mattpocock/skills \
    --agent codex \
    --agent opencode \
    --agent cursor \
    --skill '*' \
    --global \
    --yes \
    --copy
) </dev/null; then
  echo "WARN: Could not install Matt Pocock skills for Codex, OpenCode, or Cursor." >&2
fi

echo "Installing gh-axi, npm-axi, skill-creator, and PStack skills..."
if ! (
  cd "$HOME"
  npx --yes "skills@${SKILLS_CLI_VERSION}" add kunchenguid/gh-axi \
    --skill gh-axi \
    --agent claude-code \
    --agent codex \
    --agent opencode \
    --agent cursor \
    --global \
    --yes \
    --copy
  npx --yes "skills@${SKILLS_CLI_VERSION}" add SSBrouhard/npm-axi \
    --skill npm-axi \
    --agent claude-code \
    --agent codex \
    --agent opencode \
    --agent cursor \
    --global \
    --yes \
    --copy
  npx --yes "skills@${SKILLS_CLI_VERSION}" add anthropics/skills \
    --skill skill-creator \
    --agent claude-code \
    --agent codex \
    --agent opencode \
    --agent cursor \
    --global \
    --yes \
    --copy
  npx --yes "skills@${SKILLS_CLI_VERSION}" add cursor/plugins/pstack \
    --skill unslop \
    --agent claude-code \
    --agent codex \
    --agent opencode \
    --agent cursor \
    --global \
    --yes \
    --copy
) </dev/null; then
  echo "WARN: Could not install gh-axi, npm-axi, skill-creator, or PStack skills." >&2
fi

echo "Setting up gh-axi and npm-axi session hooks..."
gh-axi setup hooks </dev/null || echo "WARN: Could not set up gh-axi session hooks." >&2
npm-axi setup hooks </dev/null || echo "WARN: Could not set up npm-axi session hooks." >&2

# Link Codex skills into ~/.agents/skills for cross-agent discovery.
for skill_dir in "$HOME/.codex/skills"/*; do
  [ -d "$skill_dir" ] || continue
  skill_name="$(basename "$skill_dir")"
  case "$skill_name" in
    .system) continue ;;
  esac
  ln -sfn "$skill_dir" "$HOME/.agents/skills/$skill_name"
done

echo "Installing Exa for Claude Code..."
if ! claude plugin list 2>/dev/null | grep -q exa; then
  claude plugin marketplace add anthropics/claude-plugins-official </dev/null >/dev/null 2>&1 || true
  if ! claude plugin install exa@claude-plugins-official </dev/null >/dev/null 2>&1 &&
    ! claude mcp get exa >/dev/null 2>&1; then
    claude mcp add --transport http --scope user exa https://mcp.exa.ai/mcp </dev/null >/dev/null 2>&1 || true
  fi
fi
if ! claude plugin list 2>/dev/null | grep -q exa &&
  ! claude mcp list 2>/dev/null | grep -q exa; then
  echo "WARN: Claude Code has neither the Exa plugin nor the Exa MCP server." >&2
fi

echo "Registering the Exa MCP server with Codex..."
if ! codex mcp get exa >/dev/null 2>&1; then
  timeout 20 codex mcp add exa --url https://mcp.exa.ai/mcp </dev/null >/dev/null 2>&1 || true
fi
if ! codex mcp get exa >/dev/null 2>&1; then
  echo "WARN: Codex does not list the Exa MCP server." >&2
fi

if ! git config --global user.name >/dev/null 2>&1 ||
   ! git config --global user.email >/dev/null 2>&1; then
  echo "NOTE: Set your git identity on the box:"
  echo "  git config --global user.name 'Your Name'"
  echo "  git config --global user.email 'you@example.com'"
fi
USER_SETUP

echo "== Done"
if ! tailscale status >/dev/null 2>&1; then
  echo "NOTE: Tailscale is not connected yet. Run once: sudo tailscale up --ssh"
fi
echo "The workbench is ready. Run start-workbench which connects, cd into a repo under ~/workspace, then run: start-herdr [agent]"
