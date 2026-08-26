#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
source "$SCRIPT_DIR/sandbox_bootstrap.sh"
configureLocalWorkspace "$@"
SANDBOX_NAME="cursor-$SANDBOX_WORKSPACE_NAME"

allow_cursor_network() {
  allow_system_update_network
  local host

  for host in \
    cursor.com:443 \
    "*.cursor.com:443" \
    "**.cursor.sh:443"
  do
    sbx policy allow network --sandbox "$SANDBOX_NAME" "$host"
  done
}

install_cursor() {
  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
curl -fsS https://cursor.com/install | bash
grep -q "HOME/.local/bin" "$HOME/.bashrc" 2>/dev/null ||
  echo '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> "$HOME/.bashrc"
'
  install_file_into_sandbox "$SCRIPT_DIR/cursor-cli-config.json" /home/agent/.cursor/cli-config.json
}

runSandboxHarness allow_cursor_network install_cursor false agent
