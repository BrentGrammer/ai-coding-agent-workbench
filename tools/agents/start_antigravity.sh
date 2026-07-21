#!/bin/bash

###############################################################################
# Antigravity CLI OAuth Setup inside Docker SBX Locked-Down Sandbox
# see https://antigravity.google/docs/cli-getting-started
# see https://antigravity.google/docs/mcp
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
configureLocalWorkspace "$@"
REPO_ROOT="$WORKSPACE_ROOT_DIR"
REPO_REPLACE_UNDERSCORES="$SANDBOX_WORKSPACE_NAME"
SANDBOX_NAME="antigravity-$REPO_REPLACE_UNDERSCORES"
START_DOCKER="$WORKBENCH_ROOT/tools/scripts/start_docker.sh"

source "$SCRIPT_DIR/sandbox_bootstrap.sh"

echo "Using sandbox name: $SANDBOX_NAME"

bash "$START_DOCKER"

openLocalWorkspace

allow_antigravity_network() {
	allow_system_update_network
	allow_vendor_docs_network

	# Antigravity CLI updater / runtime fetches
	sbx policy allow network --sandbox "$SANDBOX_NAME" "antigravity-cli-auto-updater-974169037036.us-central1.run.app:443"
	sbx policy allow network --sandbox "$SANDBOX_NAME" "storage.googleapis.com:443"

	# Google OAuth / account login
	sbx policy allow network --sandbox "$SANDBOX_NAME" "oauth2.googleapis.com:443"
	sbx policy allow network --sandbox "$SANDBOX_NAME" "accounts.google.com:443"
	sbx policy allow network --sandbox "$SANDBOX_NAME" "play.googleapis.com:443"
	sbx policy allow network --sandbox "$SANDBOX_NAME" "www.googleapis.com:443"


	# Gemini / Code Assist / Antigravity model endpoints
	sbx policy allow network --sandbox "$SANDBOX_NAME" "generativelanguage.googleapis.com:443"
	sbx policy allow network --sandbox "$SANDBOX_NAME" "cloudcode-pa.googleapis.com:443"
	sbx policy allow network --sandbox "$SANDBOX_NAME" "daily-cloudcode-pa.googleapis.com:443"

	# Antigravity app / CLI endpoints
	sbx policy allow network --sandbox "$SANDBOX_NAME" "antigravity.google:443"
	sbx policy allow network --sandbox "$SANDBOX_NAME" "www.antigravity.google:443"
	sbx policy allow network --sandbox "$SANDBOX_NAME" "*.antigravity.google:443"
	sbx policy allow network --sandbox "$SANDBOX_NAME" "antigravity-unleash.goog:443"

	# Google-hosted profile/assets
	sbx policy allow network --sandbox "$SANDBOX_NAME" "lh3.googleusercontent.com:443"

	# Playwright downloads used by Antigravity/browser tooling
	sbx policy allow network --sandbox "$SANDBOX_NAME" "playwright.azureedge.net:443"
	sbx policy allow network --sandbox "$SANDBOX_NAME" "playwright-akamai.azureedge.net:443"
	sbx policy allow network --sandbox "$SANDBOX_NAME" "playwright-verizon.azureedge.net:443"

	allow_exa_mcp_network

	# for installing node and npm packages
	sbx policy allow network --sandbox "$SANDBOX_NAME" nodejs.org:443
	sbx policy allow network --sandbox "$SANDBOX_NAME" registry.npmjs.org:443
}

sync_files_to_sandbox() {
	echo "Syncing host-managed files into sandbox..."

	sbx exec "$SANDBOX_NAME" bash -c "mkdir -p /home/agent/.gemini/antigravity-cli"

	if [ -f "$WORKBENCH_ROOT/.gemini/antigravity-cli/mcp_config.json" ]; then
		sbx cp "$WORKBENCH_ROOT/.gemini/antigravity-cli/mcp_config.json" "$SANDBOX_NAME":/home/agent/.gemini/antigravity-cli/mcp_config.json
	fi

	if [ -f "$WORKBENCH_ROOT/.npmrc" ]; then
		sbx cp "$WORKBENCH_ROOT/.npmrc" "$SANDBOX_NAME":/home/agent/.npmrc
	fi

	echo "SUCCESS: Synced host-managed files into sandbox."
}

usage_instructions() {
	echo "Configuring usage instructions..."
	sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail

if [ -f "$HOME/.bashrc" ]; then
	python3 -c "
import pathlib
rc = pathlib.Path.home() / \".bashrc\"
if rc.exists():
    content = rc.read_text()
    bad_blocks = [
        \"\n# Automate agy startup\nif command -v agy >/dev/null; then\n  agy\nfi\",
        \"# Automate agy startup\nif command -v agy >/dev/null; then\n  agy\nfi\",
        \"\nif command -v agy >/dev/null; then\n  agy\nfi\",
        \"if command -v agy >/dev/null; then\n  agy\nfi\"
    ]
    modified = False
    for bad in bad_blocks:
        if bad in content:
            content = content.replace(bad, \"\")
            modified = True
    if modified:
        rc.write_text(content)
"
fi

cat > "$HOME/.antigravity-sandbox-reminder" <<'"'"'EOF'"'"'

------ Usage Instructions: ------

Start Google Antigravity:

  agy

Exit:
  Ctrl+D Ctrl+D (or /exit or /quit)

EOF

if ! grep -q ".antigravity-sandbox-reminder" "$HOME/.bashrc" 2>/dev/null; then
	cat >> "$HOME/.bashrc" <<'"'"'EOF'"'"'

if [[ $- == *i* ]] && [ -f "$HOME/.antigravity-sandbox-reminder" ]; then
	cat "$HOME/.antigravity-sandbox-reminder"
fi
EOF
fi
'
}

###############################################################################
# Create or reuse sandbox
###############################################################################

if sandboxExists "$SANDBOX_NAME"; then
	echo "✅ Existing sandbox found: $SANDBOX_NAME"
	allow_antigravity_network
	configure_sandbox_env

	# Copy updated MCP config to the existing sandbox
	sync_files_to_sandbox
	usage_instructions
else
	echo "🆕 Creating new sandbox: $SANDBOX_NAME"

	sbx create shell "$REPO_ROOT" --name "$SANDBOX_NAME"

	echo "Allowing sandbox-specific SBX network policies for $SANDBOX_NAME..."
	allow_antigravity_network
	configure_sandbox_env
	upgrade_system_packages

	# Node and usage tool: see https://github.com/skainguyen1412/antigravity-usage
	echo "Installing Node..."
	install_node_lts
	# This did not work - requires callback to localhost to signin: && sudo npm install -g antigravity-usage --ignore-scripts --allow-git=none"
	echo "SUCCESS: Node installed!"

	echo "Installing antigravity-cli..."
	sbx exec "$SANDBOX_NAME" bash -c "curl -fsSL https://antigravity.google/cli/install.sh | bash"
	echo "SUCCESS: Installed Antigravity CLI"

	sync_files_to_sandbox
	usage_instructions
fi

###############################################################################
# Run sandbox
###############################################################################

cat <<'EOF'

Start Antigravity:

  agy

EOF

sbx run "$SANDBOX_NAME"
