#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"

USE_LOCAL_MODEL=false
pi_args=()
for arg in "$@"; do
  case "$arg" in
    --local-model) USE_LOCAL_MODEL=true ;;
    *) pi_args+=("$arg") ;;
  esac
done
# bash 3.2, which macOS ships, treats an empty array as unset under `set -u`.
configureLocalWorkspace ${pi_args[@]+"${pi_args[@]}"}
copyMissingProjectInstructions "$PROMPT_INSTRUCTION_COPY"
REPO_ROOT="$WORKSPACE_ROOT_DIR"
REPO_REPLACE_UNDERSCORES="$SANDBOX_WORKSPACE_NAME"
SANDBOX_NAME="pi-$REPO_REPLACE_UNDERSCORES"
START_DOCKER="$WORKBENCH_ROOT/tools/scripts/start_docker.sh"

source "$SCRIPT_DIR/sandbox_bootstrap.sh"
source "$SCRIPT_DIR/local_llm.sh"

if [ "$USE_LOCAL_MODEL" = true ]; then
  resolve_local_llm
fi

echo "Using sandbox name: $SANDBOX_NAME"

bash "$START_DOCKER"

openLocalWorkspace

allow_pi_network() {
    allow_system_update_network
    allow_vendor_docs_network
    allow_exa_mcp_network
    allow_skills_marketplace_network
    allow_serena_mcp_network
    sbx policy allow network --sandbox "$SANDBOX_NAME" nodejs.org:443
    sbx policy allow network --sandbox "$SANDBOX_NAME" registry.npmjs.org:443
    sbx policy allow network --sandbox "$SANDBOX_NAME" pi.dev:443
    sbx policy allow network --sandbox "$SANDBOX_NAME" release-assets.githubusercontent.com:443
    sbx policy allow network --sandbox "$SANDBOX_NAME" raw.githubusercontent.com:443
    if [ "$USE_LOCAL_MODEL" = true ]; then
        allow_local_llm_network
    fi
}

install_pi_cli() {
    sbx exec "$SANDBOX_NAME" bash -c "
set -euo pipefail

  sudo npm install -g --ignore-scripts @earendil-works/pi-coding-agent@0.84.2

pi install npm:pi-web-access@0.14.0
"
}

# pi reads custom providers from ~/.pi/agent/models.json and picks up changes
# each time /model opens. There is no config field for a default model.
install_pi_local_model_config() {
    if [ "$USE_LOCAL_MODEL" != true ]; then
        return
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo "ERROR: jq is required for --local-model." >&2
        exit 1
    fi
    local models_config
    models_config="$(mktemp)"
    jq -n --arg url "$LOCAL_LLM_BASE_URL" --arg model "$LOCAL_LLM_MODEL" \
        '{
          providers: {
            "local-llm": {
              baseUrl: $url,
              api: "openai-completions",
              apiKey: "ollama",
              models: [ {
                id: $model,
                reasoning: true,
                thinkingLevelMap: { off: "none", minimal: null, low: "low", medium: "medium", high: "high", xhigh: null, max: null },
                compat: { supportsReasoningEffort: true }
              } ]
            }
          }
        }' > "$models_config"
    install_file_into_sandbox "$models_config" /home/agent/.pi/agent/models.json
    rm -f "$models_config"
}

usage_instructions() {
    local local_model_lines=""
    if [ "$USE_LOCAL_MODEL" = true ]; then
        local_model_lines="
Switch to the local model:

    Ctrl+L or /model -> local-llm
    Shift+Tab -> medium (thinking level)
"
    fi
    sbx exec "$SANDBOX_NAME" bash -c '
cat > "$HOME/.pi-welcome.sh" <<EOF
cat <<MSG

✅ sandbox is ready: '"$SANDBOX_NAME"'

Run pi:

  pi

First time: run /login to set a key or subscription plan.
Switch models any time with Ctrl+L or /model.
'"$local_model_lines"'
MSG
EOF

if ! grep ".pi-welcome.sh" "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<EOF

if [ -t 1 ] && [ -f "\$HOME/.pi-welcome.sh" ]; then
  bash "\$HOME/.pi-welcome.sh"
fi
EOF
fi
'
}

if sandboxExists "$SANDBOX_NAME"; then
    echo "✅ Existing sandbox found: $SANDBOX_NAME"
    echo "Reconnecting..."

    allow_pi_network
    configure_sandbox_env
    install_pi_cli
    install_pi_local_model_config
    install_matt_pocock_skills "$REPO_ROOT" pi
    install_skill_creator "$REPO_ROOT" pi
    install_no_mistakes "$REPO_ROOT" pi

    usage_instructions
    sbx run "$SANDBOX_NAME"
else
    echo "🆕 Creating new sandbox: $SANDBOX_NAME"

    createWorkbenchSandbox "$REPO_ROOT" "$SANDBOX_NAME"

    allow_pi_network
    upgrade_system_packages

    # echo "Installing serena..."
    # sbx exec "$SANDBOX_NAME" bash -c "uv tool install -p 3.13 serena-agent@latest --prerelease=allow"
    # echo "SUCCESS: Serena installed. Settings copied to mcp_config.json"

    install_node_lts
    install_pi_cli
    install_pi_local_model_config
    install_matt_pocock_skills "$REPO_ROOT" pi
    install_skill_creator "$REPO_ROOT" pi
    install_no_mistakes "$REPO_ROOT" pi

    configure_sandbox_env

    echo "✅ Setup complete! Dropping you into the sandbox."
    usage_instructions
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
# web search and fetch via Exa, no API key: https://pi.dev/packages/pi-web-access                                                                                                                                                                                                                                                                                                   
