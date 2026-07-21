#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
configureLocalWorkspace "$@"
REPO_ROOT="$WORKSPACE_ROOT_DIR"
REPO_REPLACE_UNDERSCORES="$SANDBOX_WORKSPACE_NAME"
SANDBOX_NAME="pi-$REPO_REPLACE_UNDERSCORES"
START_DOCKER="$WORKBENCH_ROOT/tools/scripts/start_docker.sh"

source "$SCRIPT_DIR/sandbox_bootstrap.sh"

echo "Using sandbox name: $SANDBOX_NAME"

bash "$START_DOCKER"

openLocalWorkspace

allow_pi_network() {
    allow_system_update_network
    allow_exa_mcp_network
    allow_serena_mcp_network
    sbx policy allow network --sandbox "$SANDBOX_NAME" nodejs.org:443
    sbx policy allow network --sandbox "$SANDBOX_NAME" registry.npmjs.org:443
    sbx policy allow network --sandbox "$SANDBOX_NAME" pi.dev:443
    sbx policy allow network --sandbox "$SANDBOX_NAME" release-assets.githubusercontent.com:443
    sbx policy allow network --sandbox "$SANDBOX_NAME" raw.githubusercontent.com:443
}

install_pi_cli() {
    sbx exec "$SANDBOX_NAME" bash -c "
set -euo pipefail

  sudo npm install -g --ignore-scripts @earendil-works/pi-coding-agent

pi install npm:pi-mcp-adapter
"
}

if sandboxExists "$SANDBOX_NAME"; then
    echo "✅ Existing sandbox found: $SANDBOX_NAME"
    echo "Reconnecting..."
    echo "REMINDER: Once inside the sandbox, run 'pi' to start the CLI."

    allow_pi_network
    configure_sandbox_env
    install_pi_cli

    sbx run "$SANDBOX_NAME"
else
    echo "🆕 Creating new sandbox: $SANDBOX_NAME"

    sbx create shell "$REPO_ROOT" --name "$SANDBOX_NAME"

    allow_pi_network
    upgrade_system_packages

    # echo "Installing serena..."
    # sbx exec "$SANDBOX_NAME" bash -c "uv tool install -p 3.13 serena-agent@latest --prerelease=allow"
    # echo "SUCCESS: Serena installed. Settings copied to mcp_config.json"

    install_node_lts
    install_pi_cli

    configure_sandbox_env

    echo "✅ Setup complete! Dropping you into the sandbox."
    echo "!!! REMINDER: Run 'pi' to start the CLI, then run '/login' command after starting pi to set a key or subscription plan."
    sbx run "$SANDBOX_NAME"
fi

# Useful shortcuts in pi

# Turn off telemetry: /settings > select Install telemtry = false

# Ctrl+L - choose model
# Ctrl+P cycle model
# Shift+Tab thinking level
# Esc Abort
# /tree go back and edit a previous prompt to resubmit
# pi -c # continue session
# pi -r # resume picker select
# /settings
# !!<enter command> run a command in shell

# Skills stored in .agents/skills/<filename>

# packages at pi.dev/packages
# enable mcp compatibility and usage: https://pi.dev/packages/pi-mcp-adapter                                                                                                                                                                                                                                                                                                   
