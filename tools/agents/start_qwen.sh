#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
configureLocalWorkspace "$@"

SANDBOX_NAME="qwen-$SANDBOX_WORKSPACE_NAME"
source "$SCRIPT_DIR/sandbox_bootstrap.sh"

allow_qwen_network() {
  allow_system_update_network
  local host
  for host in chat.qwen.ai:443 portal.qwen.ai:443 dashscope.aliyuncs.com:443; do
    sbx policy allow network --sandbox "$SANDBOX_NAME" "$host"
  done
}

install_qwen() {
  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail
sudo npm install -g --ignore-scripts @qwen-code/qwen-code@0.21.14
qwen --version
'
}

runSandboxHarness allow_qwen_network install_qwen true qwen
