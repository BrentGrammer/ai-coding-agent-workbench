#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
configureLocalWorkspace "$@"
REPO_ROOT="$WORKSPACE_ROOT_DIR"
REPO_REPLACE_UNDERSCORES="$SANDBOX_WORKSPACE_NAME"
SANDBOX_NAME="cursor-$REPO_REPLACE_UNDERSCORES"
START_DOCKER="$WORKBENCH_ROOT/tools/scripts/start_docker.sh"

source "$SCRIPT_DIR/sandbox_bootstrap.sh"

echo "Using sandbox name: $SANDBOX_NAME"

bash "$START_DOCKER"

openLocalWorkspace

allow_cursor_network() {
  allow_system_update_network
  allow_vendor_docs_network
  allow_exa_mcp_network
  allow_serena_mcp_network

  # Cursor CLI installer + runtime/auth endpoints.
  sbx policy allow network --sandbox "$SANDBOX_NAME" cursor.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" api.cursor.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" "*.cursor.sh:443"
  sbx policy allow network --sandbox "$SANDBOX_NAME" "*.cursor.com:443"
  sbx policy allow network --sandbox "$SANDBOX_NAME" "agentn.global.*.cursor.sh"
  sbx policy allow network --sandbox "$SANDBOX_NAME" downloads.cursor.com:443

  # Often needed by install/update flows and Node-based project work.
  sbx policy allow network --sandbox "$SANDBOX_NAME" registry.npmjs.org:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" nodejs.org:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" github.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" objects.githubusercontent.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" release-assets.githubusercontent.com:443
}

install_or_update_cursor_cli() {
  echo "Installing/updating Cursor CLI..."

  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

curl https://cursor.com/install -fsS | bash

if ! grep "HOME/.local/bin" "$HOME/.bashrc" 2>/dev/null; then
  echo '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> "$HOME/.bashrc"
fi

echo "Cursor CLI version:"
agent --version || cursor-agent --version || true
'
}

configure_cursor_env() {
  echo "Configuring Cursor CLI environment..."

  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail

mkdir -p "$HOME/.cursor"

if ! grep "HOME/.local/bin" "$HOME/.bashrc" 2>/dev/null; then
  echo '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> "$HOME/.bashrc"
fi
'
}

copy_cursor_mcp_config() {
  local cursor_mcp_config="$SCRIPT_DIR/cursor-mcp.json"

  if [ -f "$cursor_mcp_config" ]; then
    sbx exec "$SANDBOX_NAME" bash -c 'mkdir -p "$HOME/.cursor"'
    sbx cp "$cursor_mcp_config" "$SANDBOX_NAME":/home/agent/.cursor/mcp.json
  fi
}

usage_instructions() {
  echo "Installing Cursor shell reminder..."

  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail

cat > "$HOME/.cursor-sandbox-reminder" <<'"'"'EOF'"'"'

------ Usage Instructions: ------

Run command:

  agent

Update command:

  agent update
  
Notes:
  - Cursor CLI installs to ~/.local/bin via the official installer.

EOF

if ! grep -q ".cursor-sandbox-reminder" "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<'"'"'EOF'"'"'

# Show Cursor sandbox reminder when entering an interactive shell.
if [[ $- == *i* ]] && [ -f "$HOME/.cursor-sandbox-reminder" ]; then
  cat "$HOME/.cursor-sandbox-reminder"
fi
EOF
fi
'
}

if sandboxExists "$SANDBOX_NAME"; then
  echo "✅ Existing sandbox found: $SANDBOX_NAME"
  echo "Reconnecting..."

  allow_cursor_network
  configure_sandbox_env
  configure_cursor_env
  install_or_update_cursor_cli
  copy_cursor_mcp_config
  usage_instructions

  sbx run "$SANDBOX_NAME"
else
  echo "🆕 Creating new sandbox: $SANDBOX_NAME"

  sbx create shell "$REPO_ROOT" --name "$SANDBOX_NAME"

  allow_cursor_network
  upgrade_system_packages

  # Cursor's official installer uses curl and installs into ~/.local/bin.
  # Node is still useful for most agent coding workflows and npm-based repos.
  install_node_lts
  install_or_update_cursor_cli

  configure_sandbox_env
  configure_cursor_env
  copy_cursor_mcp_config
  usage_instructions

  sbx run "$SANDBOX_NAME"
fi
