#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
source "$SCRIPT_DIR/sandbox_bootstrap.sh"
configureLocalWorkspace "$@"
SANDBOX_NAME="cline-$SANDBOX_WORKSPACE_NAME"

allow_cline_network() {
  allow_system_update_network
  local host
  for host in api.workos.com:443 api.cline.bot:443 models.dev:443; do
    sbx policy allow network --sandbox "$SANDBOX_NAME" "$host"
  done
}

install_cline() {
  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail
sudo npm install -g cline@3.0.55 --ignore-scripts --allow-git=none
'
}

runSandboxHarness allow_cline_network install_cline true cline
