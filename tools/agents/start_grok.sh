#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
source "$SCRIPT_DIR/sandbox_bootstrap.sh"
configureLocalWorkspace "$@"
SANDBOX_NAME="grok-$SANDBOX_WORKSPACE_NAME"

allow_grok_network() {
  allow_system_update_network
  local host
  for host in x.ai:443 api.x.ai:443 auth.x.ai:443 accounts.x.ai:443 cli-chat-proxy.grok.com:443 storage.googleapis.com:443; do
    sbx policy allow network --sandbox "$SANDBOX_NAME" "$host"
  done
}

install_grok() {
  sbx exec "$SANDBOX_NAME" bash -lc '
set -euo pipefail
export PATH="$HOME/.grok/bin:$HOME/.local/bin:$PATH"
if command -v grok >/dev/null 2>&1; then
  grok update || true
else
  curl -fsSL https://x.ai/cli/install.sh | bash
fi
'
}

runSandboxHarness allow_grok_network install_grok false grok
