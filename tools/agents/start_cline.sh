#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
configureLocalWorkspace "$@"
REPO_ROOT="$WORKSPACE_ROOT_DIR"
REPO_REPLACE_UNDERSCORES="$SANDBOX_WORKSPACE_NAME"
SANDBOX_NAME="cline-$REPO_REPLACE_UNDERSCORES"
START_DOCKER="$WORKBENCH_ROOT/tools/scripts/start_docker.sh"

source "$SCRIPT_DIR/sandbox_bootstrap.sh"

echo "Using sandbox name: $SANDBOX_NAME"

bash "$START_DOCKER"

openLocalWorkspace

allow_cline_network() {
  allow_system_update_network
  allow_vendor_docs_network
  allow_exa_mcp_network
  allow_serena_mcp_network
  sbx policy allow network --sandbox "$SANDBOX_NAME" nodejs.org:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" registry.npmjs.org:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" api.workos.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" api.cline.bot:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" docs.cline.bot:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" models.dev:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" release-assets.githubusercontent.com:443
}

install_cline_cli() {
  echo "Ensuring Cline CLI is installed..."

  sbx exec "$SANDBOX_NAME" bash -c "
set -euo pipefail

if ! command -v cline >/dev/null 2>&1; then
  sudo npm install -g cline --ignore-scripts --allow-git=none
fi
"
}

sync_cline_settings() {
  local global_settings="$SCRIPT_DIR/cline-global-settings.json"
  local mcp_settings="$SCRIPT_DIR/cline-mcp-settings.json"

  if [ -f "$global_settings" ]; then
    install_file_into_sandbox "$global_settings" /home/agent/.cline/data/settings/global-settings.json
  fi

  if [ -f "$mcp_settings" ]; then
    install_file_into_sandbox "$mcp_settings" /home/agent/.cline/data/settings/cline_mcp_settings.json
  fi
}

if sandboxExists "$SANDBOX_NAME"; then
  echo "✅ Existing sandbox found: $SANDBOX_NAME"
  echo "Reconnecting..."
  echo "REMINDER: Once inside the sandbox, run 'cline' to start the CLI."

  allow_cline_network
  configure_sandbox_env
  install_cline_cli
  sync_cline_settings
  
  sbx run "$SANDBOX_NAME"
else
  echo "🆕 Creating new sandbox: $SANDBOX_NAME"
  
  sbx create shell "$REPO_ROOT" --name "$SANDBOX_NAME"
  
  allow_cline_network
  upgrade_system_packages
  
  install_node_lts
  install_cline_cli

  configure_sandbox_env
  sync_cline_settings
  
  echo "✅ Setup complete! Dropping you into the sandbox."
  echo "!!! REMINDER: Run 'cline auth' (requires registering a cline account on their site), then 'cline' to start the CLI."
  sbx run "$SANDBOX_NAME"
fi
