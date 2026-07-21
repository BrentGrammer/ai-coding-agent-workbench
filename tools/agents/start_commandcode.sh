#!/usr/bin/env bash
set -euo pipefail

PREFIX_NAME="commandcode"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
configureLocalWorkspace "$@"
REPO_ROOT="$WORKSPACE_ROOT_DIR"
REPO_REPLACE_UNDERSCORES="$SANDBOX_WORKSPACE_NAME"
SANDBOX_NAME="$PREFIX_NAME-$REPO_REPLACE_UNDERSCORES"
START_DOCKER="$WORKBENCH_ROOT/tools/scripts/start_docker.sh"

source "$SCRIPT_DIR/sandbox_bootstrap.sh"

echo "Using sandbox name: $SANDBOX_NAME"

chmod +x "$START_DOCKER"
"$START_DOCKER"

openLocalWorkspace

allow_network() {
  allow_system_update_network
  allow_exa_mcp_network
#   allow_serena_mcp_network
  sbx policy allow network --sandbox "$SANDBOX_NAME" api.commandcode.ai:443

  # Often needed by install/update flows and Node-based project work.
  sbx policy allow network --sandbox "$SANDBOX_NAME" registry.npmjs.org:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" nodejs.org:443
#   sbx policy allow network --sandbox "$SANDBOX_NAME" github.com:443
#   sbx policy allow network --sandbox "$SANDBOX_NAME" objects.githubusercontent.com:443
#   sbx policy allow network --sandbox "$SANDBOX_NAME" release-assets.githubusercontent.com:443
}

install_or_update() {
  echo "Installing..."

  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

npm i -g command-code@latest --ignore-scripts

# Make sure future interactive shells can find the CLI.
PROFILE="$HOME/.bashrc"
if ! grep "HOME/.local/bin" "$PROFILE" 2>/dev/null; then
  echo '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> "$PROFILE"
fi

export PATH="$HOME/.local/bin:$PATH"
'
}

copy_config() {
  local commandcode_config_dir="$WORKBENCH_ROOT/.commandcode"

  if [ -d "$commandcode_config_dir" ]; then
    echo "Copying workbench Command Code config into sandbox home..."
    sbx exec "$SANDBOX_NAME" bash -c "mkdir -p /home/agent/.commandcode"
    sbx cp "$commandcode_config_dir/." "$SANDBOX_NAME":/home/agent/.commandcode/
  fi
}

usage_instructions() {
  cat <<EOF

✅ sandbox is ready: $SANDBOX_NAME

Run the following command to start the agent:

  commandcode

EOF
}

if sbx ls | grep "$SANDBOX_NAME"; then
  echo "✅ Existing sandbox found: $SANDBOX_NAME"
  echo "Reconnecting..."

  allow_network
  configure_sandbox_env
  install_or_update
  copy_config

  usage_instructions
  sbx run "$SANDBOX_NAME"
else
  echo "🆕 Creating new sandbox: $SANDBOX_NAME"

  sbx create shell "$REPO_ROOT" --name "$SANDBOX_NAME"

  allow_network
  upgrade_system_packages

  configure_sandbox_env
  install_node_lts
  install_or_update
  copy_config

  usage_instructions
  sbx run "$SANDBOX_NAME"
fi
