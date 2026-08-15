#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
configureLocalWorkspace "$@"
copyMissingProjectInstructions "$PROMPT_INSTRUCTION_COPY"
REPO_ROOT="$WORKSPACE_ROOT_DIR"
REPO_REPLACE_UNDERSCORES="$SANDBOX_WORKSPACE_NAME"
SANDBOX_NAME="junie-$REPO_REPLACE_UNDERSCORES"
START_DOCKER="$WORKBENCH_ROOT/tools/scripts/start_docker.sh"

source "$SCRIPT_DIR/sandbox_bootstrap.sh"

echo "Using sandbox name: $SANDBOX_NAME"

bash "$START_DOCKER"

openLocalWorkspace

allow_junie_network() {
	allow_system_update_network
	allow_vendor_docs_network
	allow_exa_mcp_network
	allow_skills_marketplace_network

	# Junie installer, update info, and API key page
	sbx policy allow network --sandbox "$SANDBOX_NAME" junie.jetbrains.com:443
	sbx policy allow network --sandbox "$SANDBOX_NAME" raw.githubusercontent.com:443

	# JetBrains Account login and licensing
	sbx policy allow network --sandbox "$SANDBOX_NAME" account.jetbrains.com:443
	sbx policy allow network --sandbox "$SANDBOX_NAME" oauth.account.jetbrains.com:443
	sbx policy allow network --sandbox "$SANDBOX_NAME" www.jetbrains.com:443
	sbx policy allow network --sandbox "$SANDBOX_NAME" data.services.jetbrains.com:443

	# JetBrains AI service and Junie LLM endpoint
	sbx policy allow network --sandbox "$SANDBOX_NAME" api.jetbrains.ai:443
	sbx policy allow network --sandbox "$SANDBOX_NAME" ingrazzio-cloud-prod.labs.jb.gg:443

	# BYOK via OpenRouter
	sbx policy allow network --sandbox "$SANDBOX_NAME" openrouter.ai:443

	# for installing node and npm packages
	sbx policy allow network --sandbox "$SANDBOX_NAME" nodejs.org:443
	sbx policy allow network --sandbox "$SANDBOX_NAME" registry.npmjs.org:443
}

install_or_update_junie() {
	echo "Installing or updating Junie CLI..."

	sbx exec "$SANDBOX_NAME" bash -lc '
		set -euo pipefail

		export PATH="$HOME/.local/bin:$PATH"

		if command -v junie >/dev/null 2>&1; then
			echo "junie already installed: $(command -v junie)"
			junie --version </dev/null || true
			exit 0
		fi

		curl -fsSL https://junie.jetbrains.com/install.sh | bash

		if ! grep -Fq ".local/bin" "$HOME/.bashrc" 2>/dev/null; then
			echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$HOME/.bashrc"
		fi

		command -v junie
		junie --version </dev/null || true
	'

	echo "SUCCESS: Junie CLI installed or updated."
}

# Junie draws unicode icons and box characters. Without a UTF-8 locale they
# render as question marks. COLORTERM stays junie-local because it promises
# truecolor support the outer terminal may not have.
ensure_junie_terminal_env() {
	sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail
if ! grep -q "LC_ALL=C.UTF-8" "$HOME/.bashrc" 2>/dev/null; then
	{
		echo "export LANG=C.UTF-8"
		echo "export LC_ALL=C.UTF-8"
	} >> "$HOME/.bashrc"
fi
if ! grep -q "COLORTERM=truecolor" "$HOME/.bashrc" 2>/dev/null; then
	echo "export COLORTERM=truecolor" >> "$HOME/.bashrc"
fi
'
}

configure_junie_theme() {
	sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail

python3 - <<'PY'
import json
from pathlib import Path

settings_path = Path.home() / ".junie" / "settings.json"
settings_path.parent.mkdir(parents=True, exist_ok=True)

try:
    settings = json.loads(settings_path.read_text()) if settings_path.exists() else {}
except (OSError, json.JSONDecodeError):
    settings = {}

settings["selectedTheme"] = "Dark"
settings_path.write_text(json.dumps(settings, indent=2) + "\n")
PY
'
}

install_exa_mcp_server() {
	echo "Registering the Exa MCP server with Junie..."

	install_file_into_sandbox "$SCRIPT_DIR/junie-mcp.json" /home/agent/.junie/mcp/mcp.json
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
cat > "$HOME/.junie-welcome.sh" <<EOF
cat <<MSG

✅ sandbox is ready: '"$SANDBOX_NAME"'

Start Junie:

  junie

First-time auth. This sandbox has no browser, so use a Junie API key.
Get one at https://junie.jetbrains.com/cli then either:

  junie --auth="\\\$JUNIE_API_KEY"

or start junie and paste the key with the /account command.
BYOK also works, no env vars needed. Start junie, pick
"Use external LLM providers" on the welcome screen (or run /account),
select a provider such as OpenRouter, and paste your key.
Then pick a model with /model.

MSG
EOF

if ! grep ".junie-welcome.sh" "$HOME/.bashrc" 2>/dev/null; then
	cat >> "$HOME/.bashrc" <<EOF

if [ -t 1 ] && [ -f "\$HOME/.junie-welcome.sh" ]; then
	bash "\$HOME/.junie-welcome.sh"
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
	allow_junie_network
	configure_sandbox_env
	install_or_update_junie
	ensure_junie_terminal_env
	configure_junie_theme
	sync_files_to_sandbox
	install_exa_mcp_server
	install_matt_pocock_skills "$REPO_ROOT" junie
	install_skill_creator "$REPO_ROOT" junie
	install_no_mistakes "$REPO_ROOT" junie
	usage_instructions
else
	echo "🆕 Creating new sandbox: $SANDBOX_NAME"

	createWorkbenchSandbox "$REPO_ROOT" "$SANDBOX_NAME"

	allow_junie_network
	configure_sandbox_env
	upgrade_system_packages

	echo "Installing Node..."
	install_node_lts
	echo "SUCCESS: Node installed!"

	install_or_update_junie
	ensure_junie_terminal_env
	configure_junie_theme
	sync_files_to_sandbox
	install_exa_mcp_server
	install_matt_pocock_skills "$REPO_ROOT" junie
	install_skill_creator "$REPO_ROOT" junie
	install_no_mistakes "$REPO_ROOT" junie
	usage_instructions
fi

sbx run "$SANDBOX_NAME"