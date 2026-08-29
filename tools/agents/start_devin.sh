#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
source "$SCRIPT_DIR/sandbox_bootstrap.sh"
configureLocalWorkspace "$@"
SANDBOX_NAME="devin-$SANDBOX_WORKSPACE_NAME"

allow_devin_network() {
  allow_system_update_network
  local host

  for host in \
    devin.ai:443 \
    "*.devin.ai:443" \
    cognition.ai:443 \
    "*.cognition.ai:443" \
    server.codeium.com:443 \
    unleash.codeium.com:443
  do
    sbx policy allow network --sandbox "$SANDBOX_NAME" "$host"
  done
}

install_devin() {
  sbx exec "$SANDBOX_NAME" bash -lc '
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
if ! command -v devin >/dev/null 2>&1; then
  installer="$(mktemp)"
  curl -fsSL https://cli.devin.ai/install.sh -o "$installer"
  # The installer ends by starting an interactive login, which cannot run without a TTY.
  # Sign-in happens later, when the harness itself starts.
  bash "$installer" </dev/null || true
  rm -f "$installer"
fi
if ! command -v devin >/dev/null 2>&1; then
  echo "ERROR: The Devin CLI did not install." >&2
  exit 1
fi
'
}

runSandboxHarness allow_devin_network install_devin false devin
