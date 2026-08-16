#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
configureLocalWorkspace "$@"
copyMissingProjectInstructions "$PROMPT_INSTRUCTION_COPY"
REPO_ROOT="$WORKSPACE_ROOT_DIR"
REPO_REPLACE_UNDERSCORES="$SANDBOX_WORKSPACE_NAME"
SANDBOX_NAME="grok-$REPO_REPLACE_UNDERSCORES"
START_DOCKER="$WORKBENCH_ROOT/tools/scripts/start_docker.sh"

source "$SCRIPT_DIR/sandbox_bootstrap.sh"

echo "Using sandbox name: $SANDBOX_NAME"

bash "$START_DOCKER"

openLocalWorkspace

allow_grok_network() {
	allow_system_update_network
	allow_vendor_docs_network
	allow_exa_mcp_network
	allow_skills_marketplace_network

	# Grok Build installer / updates
	sbx policy allow network --sandbox "$SANDBOX_NAME" x.ai:443
	sbx policy allow network --sandbox "$SANDBOX_NAME" docs.x.ai:443
	sbx policy allow network --sandbox "$SANDBOX_NAME" storage.googleapis.com:443

	# Grok API
	sbx policy allow network --sandbox "$SANDBOX_NAME" api.x.ai:443

	# Login (browser OAuth, legacy accounts, device-auth proxy)
	sbx policy allow network --sandbox "$SANDBOX_NAME" auth.x.ai:443
	sbx policy allow network --sandbox "$SANDBOX_NAME" accounts.x.ai:443
	sbx policy allow network --sandbox "$SANDBOX_NAME" cli-chat-proxy.grok.com:443

	# for installing node and npm packages
	sbx policy allow network --sandbox "$SANDBOX_NAME" nodejs.org:443
	sbx policy allow network --sandbox "$SANDBOX_NAME" registry.npmjs.org:443
}

install_or_update_grok_build() {
	echo "Installing or updating Grok Build..."

	sbx exec "$SANDBOX_NAME" bash -lc '
		set -euo pipefail

		export PATH="$HOME/.grok/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

		if command -v grok >/dev/null 2>&1; then
			echo "grok already installed: $(command -v grok)"
			grok update || true
			grok --version || grok version || true
			exit 0
		fi

		curl -fsSL https://x.ai/cli/install.sh | bash

		for d in "$HOME/.grok/bin" "$HOME/.local/bin" "$HOME/.cargo/bin"; do
			if [ -d "$d" ] && ! echo "$PATH" | tr ":" "\n" | grep -Fxq "$d"; then
				export PATH="$d:$PATH"
				if ! grep -Fq "$d" "$HOME/.bashrc" 2>/dev/null; then
					echo "export PATH=\"$d:\$PATH\"" >> "$HOME/.bashrc"
				fi
			fi
		done

		command -v grok
		grok --version || grok version || true
	'

	echo "SUCCESS: Grok Build installed or updated."
}

install_exa_mcp_server() {
	echo "Registering the Exa MCP server with Grok Build..."

	sbx exec "$SANDBOX_NAME" bash -lc '
set -euo pipefail

export PATH="$HOME/.grok/bin:$HOME/.local/bin:$PATH"

if grok mcp list 2>/dev/null | grep -q exa; then
	echo "Exa MCP server already registered."
else
	timeout 20 grok mcp add --transport http exa https://mcp.exa.ai/mcp </dev/null >/dev/null 2>&1 || true
fi

if grok mcp list 2>/dev/null | grep -q exa; then
	echo "Exa MCP server ready."
else
	echo "WARN: Grok Build does not list the Exa MCP server. Run grok mcp add --transport http exa https://mcp.exa.ai/mcp inside the sandbox." >&2
fi
'
}

sync_files_to_sandbox() {
	echo "Syncing host-managed files into sandbox..."

	if [ -f "$WORKBENCH_ROOT/.npmrc" ]; then
		install_file_into_sandbox "$WORKBENCH_ROOT/.npmrc" /home/agent/.npmrc
	fi

	echo "SUCCESS: Synced host-managed files into sandbox."
}

usage_instructions() {
	sbx exec "$SANDBOX_NAME" bash -c '
cat > "$HOME/.grok-welcome.sh" <<EOF
cat <<MSG

✅ sandbox is ready: '"$SANDBOX_NAME"'

Start Grok Build:

  grok

First-time auth. This sandbox has no browser, so use device login:

  grok login --device-auth

Or set an API key:

  export XAI_API_KEY="xai-..."
  grok

MSG
EOF

if ! grep ".grok-welcome.sh" "$HOME/.bashrc" 2>/dev/null; then
	cat >> "$HOME/.bashrc" <<EOF

if [ -t 1 ] && [ -f "\$HOME/.grok-welcome.sh" ]; then
	bash "\$HOME/.grok-welcome.sh"
fi
EOF
fi
'
}

strip_legacy_grok_autostart() {
	sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail
if [ -f "$HOME/.bashrc" ]; then
	python3 -c "
import pathlib
rc = pathlib.Path.home() / \".bashrc\"
if rc.exists():
    content = rc.read_text()
    bad_blocks = [
        \"\n# Automate grok startup\nif command -v grok >/dev/null; then\n  grok\nfi\",
        \"# Automate grok startup\nif command -v grok >/dev/null; then\n  grok\nfi\",
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
'
}

###############################################################################
# Create or reuse sandbox
###############################################################################

if sandboxExists "$SANDBOX_NAME"; then
	echo "✅ Existing sandbox found: $SANDBOX_NAME"
	allow_grok_network
	configure_sandbox_env
	install_or_update_grok_build
	sync_files_to_sandbox
	install_exa_mcp_server
	install_matt_pocock_skills "$REPO_ROOT" grok
	install_skill_creator "$REPO_ROOT" grok
	install_no_mistakes "$REPO_ROOT" grok
	install_github_tools "$REPO_ROOT" grok
	strip_legacy_grok_autostart
	usage_instructions
else
	echo "🆕 Creating new sandbox: $SANDBOX_NAME"

	createWorkbenchSandbox "$REPO_ROOT" "$SANDBOX_NAME"

	allow_grok_network
	configure_sandbox_env
	upgrade_system_packages

	echo "Installing Node..."
	install_node_lts
	echo "SUCCESS: Node installed!"

	install_or_update_grok_build
	sync_files_to_sandbox
	install_exa_mcp_server
	install_matt_pocock_skills "$REPO_ROOT" grok
	install_skill_creator "$REPO_ROOT" grok
	install_no_mistakes "$REPO_ROOT" grok
	install_github_tools "$REPO_ROOT" grok
	usage_instructions
fi

sbx run "$SANDBOX_NAME"
