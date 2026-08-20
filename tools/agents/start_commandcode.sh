#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
source "$SCRIPT_DIR/sandbox_bootstrap.sh"
configureLocalWorkspace "$@"
SANDBOX_NAME="commandcode-$SANDBOX_WORKSPACE_NAME"

allow_commandcode_network() {
  allow_system_update_network
  sbx policy allow network --sandbox "$SANDBOX_NAME" api.commandcode.ai:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" commandcode.ai:443
}

install_commandcode() {
  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail
sudo npm install -g command-code@1.4.4 --ignore-scripts
'
}

runSandboxHarness allow_commandcode_network install_commandcode true commandcode
