#!/usr/bin/env bash
set -euo pipefail

PREFIX_NAME="claude"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
configureLocalWorkspace "$@"
copyMissingProjectInstructions "$PROMPT_INSTRUCTION_COPY"
REPO_ROOT="$WORKSPACE_ROOT_DIR"
REPO_REPLACE_UNDERSCORES="$SANDBOX_WORKSPACE_NAME"
SANDBOX_NAME="$PREFIX_NAME-$REPO_REPLACE_UNDERSCORES"
START_DOCKER="$WORKBENCH_ROOT/tools/scripts/start_docker.sh"

source "$SCRIPT_DIR/sandbox_bootstrap.sh"

echo "Using sandbox name: $SANDBOX_NAME"

bash "$START_DOCKER"

openLocalWorkspace

allow_network() {
  allow_system_update_network
  
  sbx policy allow network --sandbox "$SANDBOX_NAME" claude.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" downloads.claude.ai:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" api.anthropic.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" console.anthropic.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" claude.ai:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" platform.claude.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" downloads.claude.ai:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" storage.googleapis.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" challenges.cloudflare.com:443
  
  sbx policy allow network --sandbox "$SANDBOX_NAME" raw.githubusercontent.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" github.com:443

  sbx policy allow network --sandbox "$SANDBOX_NAME" registry.npmjs.org:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" nodejs.org:443

  sbx policy allow network --sandbox "$SANDBOX_NAME" api.github.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" codeload.github.com:443

  allow_vendor_docs_network
  allow_exa_mcp_network
  allow_skills_marketplace_network
}

get_anthropic_api_key() {
  if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    printf '%s' "$ANTHROPIC_API_KEY"
    return 0
  fi

  if command -v sbx >/dev/null 2>&1; then
    sbx secret get ANTHROPIC_API_KEY 2>/dev/null || true
  fi
}

configure_claude_env() {
  echo "Configuring Claude Code-specific env..."

  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail

PERSISTENT_ENV="/etc/sandbox-persistent.sh"

sudo touch "$PERSISTENT_ENV"
sudo sed -i "/^export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1$/d" "$PERSISTENT_ENV"
'
}

install_or_update() {
  echo "Installing/updating Claude Code..."

  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail

source /etc/sandbox-persistent.sh 2>/dev/null || true
export PATH="$HOME/.local/bin:$PATH"

if command -v claude >/dev/null 2>&1; then
  claude update || true
else
  curl -fsSL https://claude.ai/install.sh | bash
fi

if ! grep "HOME/.local/bin" "$HOME/.bashrc" 2>/dev/null; then
  echo '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> "$HOME/.bashrc"
fi

claude --version
'
}

copy_config() {
  local claude_settings_file="$SCRIPT_DIR/claude-settings.json"

  if [ ! -f "$claude_settings_file" ]; then
    echo "WARN: No bundled Claude settings at $claude_settings_file" >&2
    return
  fi

  echo "Installing Claude Code managed settings into sandbox..."
  sbx cp "$claude_settings_file" "$SANDBOX_NAME":/tmp/claude-settings.json
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

install_exa_tools() {
  echo "Installing Exa web search for Claude Code..."

  sbx exec "$SANDBOX_NAME" bash -lc '
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"

if claude plugin list 2>/dev/null | grep -q exa; then
  echo "Exa plugin already installed."
else
  claude plugin marketplace add anthropics/claude-plugins-official </dev/null >/dev/null 2>&1 || true
  if claude plugin install exa@claude-plugins-official </dev/null >/dev/null 2>&1; then
    echo "Installed the Exa plugin."
  elif claude mcp get exa >/dev/null 2>&1; then
    echo "Exa MCP server already registered."
  else
    echo "Plugin install did not work, falling back to the MCP server."
    claude mcp add --transport http --scope user exa https://mcp.exa.ai/mcp
  fi
fi

if ! claude plugin list 2>/dev/null | grep -q exa &&
  ! claude mcp list 2>/dev/null | grep -q exa; then
  echo "WARN: Claude Code has neither the Exa plugin nor the Exa MCP server." >&2
fi
'
}

usage_instructions() {
  sbx exec "$SANDBOX_NAME" bash -c '
cat > "$HOME/.claude-code-welcome.sh" <<EOF
cat <<MSG

✅ sandbox is ready: '"$SANDBOX_NAME"'

Prerequisite: gh (GitHub CLI) must be installed and authenticated here.

Run Claude Code:

  claude

with model:

  claude --model claude-opus-4-8
  `/model claude-opus-4-8`

Bypass all permissions:

  claude --permission-mode bypassPermissions

Allow switching to bypass mode with Shift+Tab:

  claude --allow-dangerously-skip-permissions

Note: Make sure ANTHROPIC_API_KEY is unset, or it overrides subscription auth.

Run /setup-matt-pocock-skills once per repo, if you have not already.

MSG
EOF

if ! grep ".claude-code-welcome.sh" "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<EOF

if [ -t 1 ] && [ -f "\$HOME/.claude-code-welcome.sh" ]; then
  bash "\$HOME/.claude-code-welcome.sh"
fi
EOF
fi
'
}

if sandboxExists "$SANDBOX_NAME"; then
  echo "✅ Existing sandbox found: $SANDBOX_NAME"
  echo "Reconnecting..."

  allow_network
  install_bash_sandbox_runtime
  configure_sandbox_env
  configure_claude_env
  install_or_update
  copy_config
  install_exa_tools
  install_matt_pocock_skills_plugin
  install_skill_creator "$REPO_ROOT" claude-code
  install_no_mistakes "$REPO_ROOT" claude-code
  usage_instructions

  sbx run "$SANDBOX_NAME"
else
  echo "🆕 Creating new sandbox: $SANDBOX_NAME"

  createWorkbenchSandbox "$REPO_ROOT" "$SANDBOX_NAME"

  allow_network
  upgrade_system_packages
  install_bash_sandbox_runtime
  install_node_lts
  configure_sandbox_env
  configure_claude_env
  install_or_update
  copy_config
  install_exa_tools
  install_matt_pocock_skills_plugin
  install_skill_creator "$REPO_ROOT" claude-code
  install_no_mistakes "$REPO_ROOT" claude-code
  usage_instructions

  sbx run "$SANDBOX_NAME"
fi
