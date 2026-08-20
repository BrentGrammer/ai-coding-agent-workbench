#!/usr/bin/env bash
set -euo pipefail

PREFIX_NAME="codex"

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
  allow_vendor_docs_network
  allow_exa_mcp_network
  allow_skills_marketplace_network

  sbx policy allow network --sandbox "$SANDBOX_NAME" nodejs.org:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" registry.npmjs.org:443
  # needed for lean ctx
  sbx policy allow network --sandbox "$SANDBOX_NAME" api.github.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" github.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" raw.githubusercontent.com:443

  sbx policy allow network --sandbox "$SANDBOX_NAME" files.openai.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" developers.openai.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" chatgpt.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" api.openai.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" ab.chatgpt.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" auth.openai.com:443
}

install_pinned_codex() {
  echo "Installing pinned Codex CLI..."

  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail

source /etc/sandbox-persistent.sh 2>/dev/null || true

if ! command -v npm >/dev/null 2>&1; then
  echo "ERROR: npm is not installed."
  exit 1
fi

sudo npm install -g @openai/codex@0.148.0 --ignore-scripts

codex --version
'
}

copy_config() {
  local codex_config="$SCRIPT_DIR/codex-config.toml"

  if [ -f "$codex_config" ]; then
    echo "Syncing workbench Codex config into sandbox..."
    install_file_into_sandbox "$codex_config" /home/agent/.codex/config.toml
  else
    echo "WARN: No workbench Codex config at $codex_config" >&2
  fi

  if [ -f "$WORKBENCH_ROOT/.npmrc" ]; then
    install_file_into_sandbox "$WORKBENCH_ROOT/.npmrc" /home/agent/.npmrc
  fi
}

install_exa_mcp_server() {
  [ "$INSTALL_EXA" = "true" ] || return 0

  echo "Registering the Exa MCP server with Codex..."

  # The add writes the config entry first, then offers an OAuth flow that would
  # block setup waiting for a browser callback. Exa's free tier needs no login,
  # so the timeout stops at the entry.
  sbx exec "$SANDBOX_NAME" bash -lc '
set -euo pipefail

if codex mcp get exa >/dev/null 2>&1; then
  echo "Exa MCP server already registered."
else
  timeout 20 codex mcp add exa --url https://mcp.exa.ai/mcp </dev/null >/dev/null 2>&1 || true
fi

if codex mcp get exa >/dev/null 2>&1; then
  echo "Exa MCP server ready."
else
  echo "WARN: Codex does not list the Exa MCP server. Run codex mcp add exa --url https://mcp.exa.ai/mcp inside the sandbox." >&2
fi
'
}

install_skills() {
  install_matt_pocock_skills "$REPO_ROOT" codex
  install_skill_creator "$REPO_ROOT" codex
  install_github_tools "$REPO_ROOT" codex
}

usage_instructions() {
  local skills_block=""
  if [ "$INSTALL_MATT_POCOCK_SKILLS" = "true" ]; then
    skills_block=$'\nUse Skills in Codex:\n\n  Inside Codex type: /skills\n  Select setup-matt-pocock-skills and run it.\n'
  fi
  sbx exec "$SANDBOX_NAME" bash -c '
cat > "$HOME/.codex-welcome.sh" <<EOF
cat <<MSG

✅ sandbox is ready: '"$SANDBOX_NAME"'

Run Codex:

  codex
'"$skills_block"'
MSG
EOF

if ! grep ".codex-welcome.sh" "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<EOF

if [ -t 1 ] && [ -f "\$HOME/.codex-welcome.sh" ]; then
  bash "\$HOME/.codex-welcome.sh"
fi
EOF
fi
'
}

if sandboxExists "$SANDBOX_NAME"; then
  echo "✅ Existing sandbox found: $SANDBOX_NAME"
  echo "Reconnecting..."

  allow_network
  configure_sandbox_env
  install_pinned_codex
  copy_config
  install_exa_mcp_server
  install_skills
  link_codex_skills_for_discovery
  usage_instructions

  sbx run "$SANDBOX_NAME"
else
  echo "🆕 Creating new sandbox: $SANDBOX_NAME"

  createWorkbenchSandbox "$REPO_ROOT" "$SANDBOX_NAME"

  allow_network
  upgrade_system_packages
  install_node_lts
  configure_sandbox_env
  install_pinned_codex
  copy_config
  install_exa_mcp_server
  install_skills
  link_codex_skills_for_discovery
  usage_instructions

  sbx run "$SANDBOX_NAME"
fi
