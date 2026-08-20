#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
source "$SCRIPT_DIR/sandbox_bootstrap.sh"
configureLocalWorkspace "$@"
SANDBOX_NAME="antigravity-$SANDBOX_WORKSPACE_NAME"

allow_antigravity_network() {
  allow_system_update_network
  local host
  for host in \
    antigravity.google:443 \
    "*.antigravity.google:443" \
    antigravity-cli-auto-updater-974169037036.us-central1.run.app:443 \
    accounts.google.com:443 \
    oauth2.googleapis.com:443 \
    generativelanguage.googleapis.com:443 \
    cloudcode-pa.googleapis.com:443 \
    storage.googleapis.com:443
  do
    sbx policy allow network --sandbox "$SANDBOX_NAME" "$host"
  done
}

install_antigravity() {
  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail
if ! command -v agy >/dev/null 2>&1; then
  curl -fsSL https://antigravity.google/cli/install.sh | bash
fi
'
}

runSandboxHarness allow_antigravity_network install_antigravity false agy
