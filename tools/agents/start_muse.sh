#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
source "$SCRIPT_DIR/sandbox_bootstrap.sh"
configureLocalWorkspace "$@"
SANDBOX_NAME="muse-$SANDBOX_WORKSPACE_NAME"

allow_muse_network() {
  allow_system_update_network
  local host
  for host in \
    dev.meta.ai:443 \
    api.meta.ai:443 \
    meta.ai:443 \
    "*.meta.ai:443" \
    meta.com:443 \
    "*.meta.com:443" \
    facebook.com:443 \
    "*.facebook.com:443"
  do
    sbx policy allow network --sandbox "$SANDBOX_NAME" "$host"
  done
}

install_muse() {
  sbx exec "$SANDBOX_NAME" bash -lc '
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
if ! command -v muse >/dev/null 2>&1; then
  curl -fsSL https://dev.meta.ai/install.sh | bash
fi
grep -q "HOME/.local/bin" "$HOME/.bashrc" 2>/dev/null ||
  echo '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> "$HOME/.bashrc"
muse --version
'
}

runSandboxHarness allow_muse_network install_muse false muse
