#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
source "$SCRIPT_DIR/sandbox_bootstrap.sh"
configureLocalWorkspace "$@"
SANDBOX_NAME="codex-$SANDBOX_WORKSPACE_NAME"

allow_codex_network() {
  allow_system_update_network
  local host
  for host in files.openai.com:443 chatgpt.com:443 api.openai.com:443 ab.chatgpt.com:443 auth.openai.com:443; do
    sbx policy allow network --sandbox "$SANDBOX_NAME" "$host"
  done
}

install_codex() {
  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail
sudo npm install -g @openai/codex@0.148.0 --ignore-scripts
codex --version
'
  install_file_into_sandbox "$SCRIPT_DIR/codex-config.toml" /home/agent/.codex/config.toml
}

runSandboxHarness allow_codex_network install_codex true codex
