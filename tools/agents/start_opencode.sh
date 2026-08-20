#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
configureLocalWorkspace "$@"

SANDBOX_NAME="opencode-$SANDBOX_WORKSPACE_NAME"
source "$SCRIPT_DIR/sandbox_bootstrap.sh"

allow_opencode_network() {
  allow_system_update_network
  allow_standard_model_network
  local host
  for host in \
    api.openai.com:443 \
    auth.openai.com:443 \
    chatgpt.com:443 \
    generativelanguage.googleapis.com:443 \
    models.dev:443 \
    models.opencode.ai:443 \
    opencode.ai:443 \
    openrouter.ai:443
  do
    sbx policy allow network --sandbox "$SANDBOX_NAME" "$host"
  done
}

install_opencode() {
  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail
npm install -g opencode-ai@1.18.18 --ignore-scripts
(cd "$(npm root -g)/opencode-ai" && node postinstall.mjs)
opencode --version
'
  install_file_into_sandbox "$SCRIPT_DIR/opencode.json" /etc/opencode/opencode.json 644 755 root:root
}

runSandboxHarness allow_opencode_network install_opencode true opencode
