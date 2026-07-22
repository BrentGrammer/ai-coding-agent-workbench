#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -gt 2 ]; then
  echo "Usage: $0 [WORKSPACE_PATH] [claude|codex|opencode]" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"

WORKBENCH_AGENT="${2:-${WORKBENCH_AGENT:-claude}}"
export WORKBENCH_AGENT
case "$WORKBENCH_AGENT" in
  claude|codex|opencode)
    ;;
  *)
    echo "ERROR: Agent must be claude, codex, or opencode." >&2
    exit 1
    ;;
esac

configureLocalWorkspace "${1:-$PWD}"

SANDBOX_NAME="herdr-$SANDBOX_WORKSPACE_NAME"
START_DOCKER="$WORKBENCH_ROOT/tools/scripts/start_docker.sh"

source "$SCRIPT_DIR/sandbox_bootstrap.sh"

allow_network() {
  allow_system_update_network
  allow_vendor_docs_network

  local host
  for host in \
    ab.chatgpt.com:443 \
    api.anthropic.com:443 \
    api.github.com:443 \
    api.openai.com:443 \
    auth.openai.com:443 \
    challenges.cloudflare.com:443 \
    chatgpt.com:443 \
    claude.ai:443 \
    claude.com:443 \
    cdn.jsdelivr.net:443 \
    codeload.github.com:443 \
    downloads.claude.ai:443 \
    files.openai.com:443 \
    github.com:443 \
    herdr.dev:443 \
    models.dev:443 \
    nodejs.org:443 \
    objects.githubusercontent.com:443 \
    openrouter.ai:443 \
    platform.claude.com:443 \
    raw.githubusercontent.com:443 \
    registry.npmjs.org:443 \
    release-assets.githubusercontent.com:443 \
    storage.googleapis.com:443
  do
    sbx policy allow network --sandbox "$SANDBOX_NAME" "$host"
  done
}

install_runtime_files() {
  install_file_into_sandbox "$WORKBENCH_ROOT/runtime/start-herdr" /usr/local/bin/start-herdr 755 755 root:root
  install_file_into_sandbox "$WORKBENCH_ROOT/runtime/workbench-pane-shell" /usr/local/bin/workbench-pane-shell 755 755 root:root
  install_file_into_sandbox "$WORKBENCH_ROOT/runtime/herdr-config.toml" /etc/agent-workbench/herdr-config.toml 644 755 root:root
}

install_system_packages() {
  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail

sudo apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  git \
  less \
  ncurses-bin \
  ncurses-term
'
}

install_or_update_tools() {
  sbx exec "$SANDBOX_NAME" bash -lc '
set -euo pipefail

mkdir -p "$HOME/.local/bin" "$HOME/.local/npm"
npm config set prefix "$HOME/.local/npm"

case "$(uname -m)" in
  aarch64|arm64)
    herdr_arch="aarch64"
    ;;
  x86_64|amd64)
    herdr_arch="x86_64"
    ;;
  *)
    echo "ERROR: Unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

curl -fsSL "https://github.com/ogulcancelik/herdr/releases/download/v0.7.4/herdr-linux-${herdr_arch}" \
  -o "$HOME/.local/bin/herdr"
chmod 755 "$HOME/.local/bin/herdr"

npm install -g \
  "hunkdiff@0.17.3" \
  @openai/codex@latest \
  opencode-ai@latest

cd "$(npm root -g)/opencode-ai"
node postinstall.mjs
cd "$HOME"

if command -v claude >/dev/null 2>&1; then
  claude update || true
else
  curl -fsSL https://claude.ai/install.sh | bash
fi

herdr --version
hunk --version
claude --version
codex --version
opencode --version
'
}

copy_agent_settings() {
  local claude_settings_file="$SCRIPT_DIR/claude-settings.json"
  local codex_config_file="$SCRIPT_DIR/codex-config.toml"
  local opencode_config_file="$SCRIPT_DIR/opencode.json"

  if [ -f "$claude_settings_file" ]; then
    sbx cp "$claude_settings_file" "$SANDBOX_NAME":/tmp/claude-settings.json
    sbx cp "$WORKBENCH_ROOT/runtime/deny-protected-file-reads" \
      "$SANDBOX_NAME":/tmp/deny-protected-file-reads
    sbx cp "$WORKBENCH_ROOT/runtime/install-claude-settings" \
      "$SANDBOX_NAME":/tmp/install-claude-settings
    sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail
bash /tmp/install-claude-settings \
  /tmp/claude-settings.json \
  /tmp/deny-protected-file-reads
sudo rm -f /tmp/install-claude-settings /tmp/claude-settings.json \
  /tmp/deny-protected-file-reads
'
  else
    echo "WARN: No bundled Claude settings at $claude_settings_file" >&2
  fi

  if [ -f "$codex_config_file" ]; then
    install_file_into_sandbox "$codex_config_file" /home/agent/.codex/config.toml
  else
    echo "WARN: No workbench Codex config at $codex_config_file" >&2
  fi

  if [ -f "$opencode_config_file" ]; then
    install_file_into_sandbox "$opencode_config_file" /etc/opencode/opencode.json 644 755 root:root
  else
    echo "WARN: No workbench OpenCode config at $opencode_config_file" >&2
  fi
}

install_integrations() {
  sbx exec "$SANDBOX_NAME" bash -lc '
set -euo pipefail

mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.config/opencode"
chmod 700 "$HOME/.claude" "$HOME/.codex" "$HOME/.config/opencode"

for agent_name in claude codex opencode; do
  herdr integration install "$agent_name"
done
'
}

bash "$START_DOCKER"
openLocalWorkspace

if sandboxExists "$SANDBOX_NAME"; then
  echo "Reusing sandbox: $SANDBOX_NAME"
else
  echo "Creating sandbox: $SANDBOX_NAME"
  sbx create shell "$WORKSPACE_ROOT_DIR" --name "$SANDBOX_NAME"
  allow_network
  upgrade_system_packages
  install_system_packages
  install_node_lts
fi

allow_network
configure_sandbox_env
if ! sbx exec "$SANDBOX_NAME" bash -c 'command -v node >/dev/null 2>&1'; then
  install_node_lts
fi
install_runtime_files
install_or_update_tools
install_bash_sandbox_runtime
copy_agent_settings
install_integrations

echo "Starting Herdr with $WORKBENCH_AGENT in $WORKSPACE_ROOT_DIR"

sbx exec -it -w "$WORKSPACE_ROOT_DIR" "$SANDBOX_NAME" \
  env \
    WORKSPACE_DIR="$WORKSPACE_ROOT_DIR" \
    WORKBENCH_SESSION="$SANDBOX_NAME" \
    WORKBENCH_AGENT="$WORKBENCH_AGENT" \
    HERDR_CONFIG_PATH=/etc/agent-workbench/herdr-config.toml \
  bash -lc start-herdr
