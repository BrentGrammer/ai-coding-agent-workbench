#!/bin/bash
set -euo pipefail

###############################################################################
# Gemini CLI OAuth Setup inside Docker SBX Locked-Down Sandbox
#
# Purpose:
# Use Gemini CLI with Google OAuth (subscription/account login)
# instead of an API key.
#
# Notes:
# - Do NOT use: sbx run gemini
# - Use: sbx run shell .
# - Gemini CLI may say "no sandbox"
#   because that refers to Gemini's internal sandbox,
#   not Docker SBX.
#
# Manual Setup:
#
# 1. If Gemini keeps using an API key instead of OAuth, remove the global secret:
#    sbx secret rm -g google
#
# 2. Start Gemini in the sandbox:
#    gemini
#
# 3. Choose "Sign in with Google".
#
################################################ 
#
# REUSING EXISTING SANDBOX (after setting it up initially using above instructions)
#
# 1. List existing sandboxes:
#    sbx ls
#
# 2. Reconnect to the existing sandbox:
#    sbx run <sandbox-name>
#
# Notes:
# - Gemini CLI install persists inside the sandbox.
# - OAuth login/session should persist inside the sandbox.
#
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
configureLocalWorkspace "$@"
REPO_ROOT="$WORKSPACE_ROOT_DIR"
REPO_REPLACE_UNDERSCORES="$SANDBOX_WORKSPACE_NAME"
SANDBOX_NAME="gemini-$REPO_REPLACE_UNDERSCORES"
START_DOCKER="$WORKBENCH_ROOT/tools/scripts/start_docker.sh"

source "$SCRIPT_DIR/sandbox_bootstrap.sh"

echo "Using sandbox name: $SANDBOX_NAME"

chmod +x "$START_DOCKER"
"$START_DOCKER"

openLocalWorkspace

allow_gemini_network() {
  allow_system_update_network
  allow_exa_mcp_network
  allow_serena_mcp_network
  sbx policy allow network --sandbox "$SANDBOX_NAME" nodejs.org:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" generativelanguage.googleapis.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" oauth2.googleapis.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" accounts.google.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" play.googleapis.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" cloudcode-pa.googleapis.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" www.googleapis.com:443
}

install_gemini_cli() {
  echo "Ensuring Node and Gemini CLI are installed..."

  sbx exec "$SANDBOX_NAME" bash -c "
set -euo pipefail

if ! command -v gemini >/dev/null 2>&1; then
  sudo npm install -g @google/gemini-cli --ignore-scripts --allow-git=none
fi
"
}

# Reuse existing sandbox if it already exists
if sbx ls | grep "$SANDBOX_NAME"; then
  echo "✅ Existing sandbox found: $SANDBOX_NAME"
  echo "Reconnecting..."

  allow_gemini_network
  configure_sandbox_env

  echo "REMINDER: Once inside the sandbox, run the command 'gemini' to start the cli."
  sbx run "$SANDBOX_NAME"
else
  echo "🆕 Creating new sandbox: $SANDBOX_NAME"
  
  sbx create shell "$REPO_ROOT" --name "$SANDBOX_NAME"
  allow_gemini_network
  configure_sandbox_env
  upgrade_system_packages
  install_node_lts
  install_gemini_cli

  echo "Gemini CLI is installed. Run 'gemini' inside the sandbox and choose 'Sign in with Google'."

  sbx run "$SANDBOX_NAME"
fi
