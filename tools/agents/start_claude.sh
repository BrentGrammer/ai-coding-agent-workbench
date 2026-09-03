#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
source "$SCRIPT_DIR/sandbox_bootstrap.sh"
configureLocalWorkspace "$@"
SANDBOX_NAME="claude-$SANDBOX_WORKSPACE_NAME"

allow_claude_network() {
  allow_system_update_network
  local host
  for host in \
    claude.com:443 \
    downloads.claude.ai:443 \
    api.anthropic.com:443 \
    console.anthropic.com:443 \
    claude.ai:443 \
    claude.com:443 \
    storage.googleapis.com:443 \
    challenges.cloudflare.com:443 \
    platform.claude.com:443
  do
    sbx policy allow network --sandbox "$SANDBOX_NAME" "$host"
  done
}

install_claude() {
  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
if command -v claude >/dev/null 2>&1; then
  claude update || true
else
  curl -fsSL https://claude.ai/install.sh | bash
fi
grep -q "HOME/.local/bin" "$HOME/.bashrc" 2>/dev/null ||
  echo '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> "$HOME/.bashrc"
claude --version
'

  install_bash_sandbox_runtime
  sbx cp "$SCRIPT_DIR/config/claude/settings.json" "$SANDBOX_NAME":/tmp/claude-settings.json
  sbx cp "$WORKBENCH_ROOT/runtime/deny-protected-file-reads" \
    "$SANDBOX_NAME":/tmp/deny-protected-file-reads
  sbx cp "$WORKBENCH_ROOT/runtime/install-claude-settings" \
    "$SANDBOX_NAME":/tmp/install-claude-settings
  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail
bash /tmp/install-claude-settings \
  /tmp/claude-settings.json \
  /tmp/deny-protected-file-reads
sudo rm -f /tmp/install-claude-settings /tmp/claude-settings.json \
  /tmp/deny-protected-file-reads
'
}

runSandboxHarness allow_claude_network install_claude false claude
