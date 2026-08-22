#!/usr/bin/env bash
set -euo pipefail

POSITIONAL=()
LAUNCHER_FLAGS=()
for argument in "$@"; do
  case "$argument" in
    --*) LAUNCHER_FLAGS+=("$argument") ;;
    *) POSITIONAL+=("$argument") ;;
  esac
done
if [ "${#POSITIONAL[@]}" -gt 2 ]; then
  echo "Usage: $0 [WORKSPACE_PATH] [claude|codex|opencode|cursor] [--clone]" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
source "$SCRIPT_DIR/sandbox_bootstrap.sh"

WORKBENCH_AGENT="${POSITIONAL[1]:-${WORKBENCH_AGENT:-cursor}}"
case "$WORKBENCH_AGENT" in
  claude|codex|opencode|cursor) ;;
  *) echo "ERROR: Unknown harness: $WORKBENCH_AGENT" >&2; exit 1 ;;
esac

configureLocalWorkspace ${LAUNCHER_FLAGS[@]+"${LAUNCHER_FLAGS[@]}"} "${POSITIONAL[0]:-$PWD}"
SANDBOX_NAME="herdr-$SANDBOX_WORKSPACE_NAME"

allow_herdr_network() {
  allow_system_update_network
  local host
  for host in \
    github.com:443 \
    objects.githubusercontent.com:443 \
    release-assets.githubusercontent.com:443 \
    herdr.dev:443 \
    claude.com:443 \
    claude.ai:443 \
    downloads.claude.ai:443 \
    api.anthropic.com:443 \
    chatgpt.com:443 \
    auth.openai.com:443 \
    api.openai.com:443 \
    cursor.com:443 \
    api.cursor.com:443 \
    downloads.cursor.com:443 \
    "*.cursor.com:443" \
    "*.cursor.sh:443" \
    models.dev:443 \
    models.opencode.ai:443 \
    opencode.ai:443 \
    openrouter.ai:443
  do
    sbx policy allow network --sandbox "$SANDBOX_NAME" "$host"
  done
}

install_runtime_files() {
  install_file_into_sandbox "$WORKBENCH_ROOT/runtime/herdr-session" /usr/local/bin/herdr-session 755 755 root:root
  install_file_into_sandbox "$WORKBENCH_ROOT/runtime/workbench-pane-shell" /usr/local/bin/workbench-pane-shell 755 755 root:root
  install_file_into_sandbox "$WORKBENCH_ROOT/runtime/herdr-config.toml" /etc/agent-workbench/herdr-config.toml 644 755 root:root
}

install_herdr_dependencies() {
  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends jq
'
}

install_herdr_and_harness() {
  sbx exec "$SANDBOX_NAME" bash -lc '
set -euo pipefail
mkdir -p "$HOME/.local/bin" "$HOME/.local/npm"
npm config set prefix "$HOME/.local/npm"
export PATH="$HOME/.local/bin:$HOME/.local/npm/bin:$PATH"

case "$(uname -m)" in
  aarch64|arm64) herdr_arch="aarch64" ;;
  x86_64|amd64) herdr_arch="x86_64" ;;
  *) echo "ERROR: Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

curl -fsSL "https://github.com/herdrdev/herdr/releases/download/v0.8.0/herdr-linux-${herdr_arch}" \
  -o "$HOME/.local/bin/herdr"
chmod 755 "$HOME/.local/bin/herdr"

case '"$WORKBENCH_AGENT"' in
  claude)
    command -v claude >/dev/null 2>&1 || curl -fsSL https://claude.ai/install.sh | bash
    ;;
  codex)
    npm install -g @openai/codex@0.148.0 --ignore-scripts
    ;;
  opencode)
    npm install -g opencode-ai@1.18.21 --ignore-scripts
    (cd "$(npm root -g)/opencode-ai" && node postinstall.mjs)
    ;;
  cursor)
    curl -fsSL https://cursor.com/install | bash
    ;;
esac

herdr integration install '"$WORKBENCH_AGENT"'
'
}

install_harness_security() {
  case "$WORKBENCH_AGENT" in
    claude)
      install_bash_sandbox_runtime
      sbx cp "$SCRIPT_DIR/claude-settings.json" "$SANDBOX_NAME":/tmp/claude-settings.json
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
      ;;
    codex)
      install_file_into_sandbox "$SCRIPT_DIR/codex-config.toml" /home/agent/.codex/config.toml
      ;;
    opencode)
      install_file_into_sandbox "$SCRIPT_DIR/opencode.json" /etc/opencode/opencode.json 644 755 root:root
      ;;
    cursor)
      install_file_into_sandbox "$SCRIPT_DIR/cursor-cli-config.json" /home/agent/.cursor/cli-config.json
      ;;
  esac
}

bash "$WORKBENCH_ROOT/tools/scripts/start_docker.sh"
if ! sandboxExists "$SANDBOX_NAME"; then
  createWorkbenchSandbox "$WORKSPACE_ROOT_DIR" "$SANDBOX_NAME"
  allow_herdr_network
  install_herdr_dependencies
  install_node_lts
fi

allow_herdr_network
install_runtime_files
install_herdr_and_harness
install_harness_security
# Shared with the optional-skills-tools branch so this launcher stays one file to change.
if type install_selected_skills_and_tools >/dev/null 2>&1; then
  install_selected_skills_and_tools
fi

sbx exec -it -w "$WORKSPACE_ROOT_DIR" "$SANDBOX_NAME" \
  env \
    WORKSPACE_DIR="$WORKSPACE_ROOT_DIR" \
    WORKBENCH_SESSION="$SANDBOX_NAME" \
    WORKBENCH_AGENT="$WORKBENCH_AGENT" \
    HERDR_CONFIG_PATH=/etc/agent-workbench/herdr-config.toml \
  bash -lc herdr-session
