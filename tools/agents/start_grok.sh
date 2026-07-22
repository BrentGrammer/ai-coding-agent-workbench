#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
configureLocalWorkspace "$@"
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

	# Grok Build installer / updates
	sbx policy allow network --sandbox "$SANDBOX_NAME" x.ai:443
	sbx policy allow network --sandbox "$SANDBOX_NAME" docs.x.ai:443
	sbx policy allow network --sandbox "$SANDBOX_NAME" storage.googleapis.com:443

	# Grok API
	sbx policy allow network --sandbox "$SANDBOX_NAME" api.x.ai:443

	# for installing node and npm packages
	sbx policy allow network --sandbox "$SANDBOX_NAME" nodejs.org:443
	sbx policy allow network --sandbox "$SANDBOX_NAME" registry.npmjs.org:443
}

install_grok_build() {
	echo "Installing Grok Build if missing..."

	sbx exec "$SANDBOX_NAME" bash -lc '
		if command -v grok >/dev/null 2>&1; then
			echo "grok already installed: $(command -v grok)"
			grok --version || true
			exit 0
		fi

		curl -fsSL https://x.ai/cli/install.sh | bash

		# Common installer locations; make available for this shell and future shells.
		for d in "$HOME/.local/bin" "$HOME/.grok/bin" "$HOME/.cargo/bin"; do
			if [ -d "$d" ] && ! echo "$PATH" | tr ":" "\n" | grep -Fxq "$d"; then
				export PATH="$d:$PATH"
				if ! grep -Fq "$d" "$HOME/.bashrc" 2>/dev/null; then
					echo "export PATH=\"$d:\$PATH\"" >> "$HOME/.bashrc"
				fi
			fi
		done

		command -v grok
		grok --version || true
	'

	echo "SUCCESS: Grok Build installed."
}

sync_files_to_sandbox() {
	echo "Syncing host-managed files into sandbox..."

	if [ -f "$WORKBENCH_ROOT/.npmrc" ]; then
		sbx cp "$WORKBENCH_ROOT/.npmrc" "$SANDBOX_NAME":/tmp/.npmrc
		sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail
sudo install -m 600 -o agent -g agent /tmp/.npmrc /home/agent/.npmrc
sudo rm -f /tmp/.npmrc
'
	fi

	echo "SUCCESS: Synced host-managed files into sandbox."
}

###############################################################################
# Create or reuse sandbox
###############################################################################

if sandboxExists "$SANDBOX_NAME"; then
	echo "✅ Existing sandbox found: $SANDBOX_NAME"
	allow_grok_network
	configure_sandbox_env
	sync_files_to_sandbox

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
else
	echo "🆕 Creating new sandbox: $SANDBOX_NAME"

	sbx create shell "$REPO_ROOT" --name "$SANDBOX_NAME"

	allow_grok_network
	configure_sandbox_env
	upgrade_system_packages

	echo "Installing Node..."
	install_node_lts
	echo "SUCCESS: Node installed!"

	echo "Installing grok build..."
	install_grok_build
	echo "SUCCESS: Installed Grok Build"

	sync_files_to_sandbox
fi

###############################################################################
# Run sandbox
###############################################################################

cat <<'EOF'

Start Grok Build:

  grok

EOF

sbx run "$SANDBOX_NAME"
