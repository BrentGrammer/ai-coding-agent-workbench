#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
source "$SCRIPT_DIR/sandbox_bootstrap.sh"
configureLocalWorkspace "$@"
SANDBOX_NAME="junie-$SANDBOX_WORKSPACE_NAME"

allow_junie_network() {
  allow_system_update_network
  local host
  for host in \
    junie.jetbrains.com:443 \
    account.jetbrains.com:443 \
    oauth.account.jetbrains.com:443 \
    data.services.jetbrains.com:443 \
    api.jetbrains.ai:443 \
    ingrazzio-cloud-prod.labs.jb.gg:443 \
    openrouter.ai:443
  do
    sbx policy allow network --sandbox "$SANDBOX_NAME" "$host"
  done
}

install_junie() {
  sbx exec "$SANDBOX_NAME" bash -lc '
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
if ! command -v junie >/dev/null 2>&1; then
  curl -fsSL https://junie.jetbrains.com/install.sh | bash
fi
grep -q "HOME/.local/bin" "$HOME/.bashrc" 2>/dev/null ||
  echo '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> "$HOME/.bashrc"
'
}

runSandboxHarness allow_junie_network install_junie false junie
