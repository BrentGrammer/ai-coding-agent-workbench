#!/usr/bin/env bash
set -euo pipefail

# try these models:
# qwen.qwen3-coder-next
# minimax.minimax-m3 - THIS ONE IS PRETTY GOOD! wrote good tests understood documents, pretty good open model option.
# mistral.devstral-2-123b
# deepseek.v3.2
# zai.glm-4.7

# Could not get Deepseek R1 to work with OPENCODE

# Good complex coding models to try from Bedrock:
# 1. Claude Opus 4.5 or Claude Opus 4.6 (US) works from Bedrock
# 2. Claude Sonnet 4.5
# 3. Claude Opus 4.1
# 4. Qwen3 Coder Next  # This one seemed really good for planning refactors!
# 5. Devstral 2 123B
# 6. DeepSeek V3.2
# 7. MiniMax M2.5
# 8. GLM5
# 9. Kimi K2.5 # The thinking version is capable, but was really slow and a little glitchy

# MODEL="amazon-bedrock/zai.glm-5"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"

selectModelHost "$@"
configureLocalWorkspace ${LAUNCHER_ARGS[@]+"${LAUNCHER_ARGS[@]}"}
copyMissingProjectInstructions "$PROMPT_INSTRUCTION_COPY"
REPO_ROOT="$WORKSPACE_ROOT_DIR"
REPO_NAME="$WORKSPACE_NAME"
REPO_REPLACE_UNDERSCORES="$SANDBOX_WORKSPACE_NAME"
PROJECT_DIR="$REPO_ROOT"
PROJECT_BASENAME="$REPO_NAME"
SANDBOX_NAME="opencode-$REPO_REPLACE_UNDERSCORES"
START_DOCKER="$WORKBENCH_ROOT/tools/scripts/start_docker.sh"

source "$SCRIPT_DIR/sandbox_bootstrap.sh"
source "$SCRIPT_DIR/local_llm.sh"

if [ "$USE_LOCAL_MODEL" = true ]; then
  resolve_local_llm
fi

bash "$START_DOCKER"

# One-time setup per sandbox name - enter your API key for BYOK usage:
#   Ex: sbx secret set <sandbox_name> openai
#
# Usage:
#   ./tools/agents/start_opencode.sh [--local-model|--gpu-box] [WORKSPACE_PATH]
#     --local-model  this Mac's own Ollama
#     --gpu-box      the GPU box on the tailnet

allow_opencode_network() {
  allow_gemini_access
  allow_system_update_network
  allow_vendor_docs_network
  allow_exa_mcp_network
  allow_skills_marketplace_network
  sbx policy allow network --sandbox "$SANDBOX_NAME" nodejs.org:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" registry.npmjs.org:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" models.dev:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" models.opencode.ai:443
  # exa searches
  sbx policy allow network --sandbox "$SANDBOX_NAME" cdn.jsdelivr.net:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" raw.githubusercontent.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" opencode.ai:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" openrouter.ai:443
  if [ "$USE_LOCAL_MODEL" = true ]; then
    allow_local_llm_network
  fi
}

allow_codex_oauth_network() {
  sbx policy allow network --sandbox "$SANDBOX_NAME" auth.openai.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" accounts.google.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" oauthaccountmanager.googleapis.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" oauth2.googleapis.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" chatgpt.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" api.openai.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" platform.openai.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" openaiapi-site.azureedge.net:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" challenges.cloudflare.com:443
}

install_pinned_opencode() {
  echo "Installing pinned OpenCode inside sandbox..."

  sbx exec -d "$SANDBOX_NAME" bash -c '
set -euo pipefail

npm install -g opencode-ai@1.18.18 --ignore-scripts

(cd "$(npm root -g)/opencode-ai" && node postinstall.mjs)

opencode --version
'
}

install_skills() {
  install_matt_pocock_skills "$REPO_ROOT" opencode
  install_skill_creator "$REPO_ROOT" opencode
  install_no_mistakes "$REPO_ROOT" opencode
  install_github_tools "$REPO_ROOT" opencode
}

copy_config() {
  local opencode_config="$SCRIPT_DIR/opencode.json"
  local source_config="$opencode_config"
  local generated_configs=()

  if [ ! -f "$source_config" ]; then
    echo "WARN: No workbench OpenCode config at $source_config" >&2
    return
  fi

  if [ "$INSTALL_EXA" = "true" ] || [ "$USE_LOCAL_MODEL" = "true" ]; then
    require_jq
  fi

  if [ "$INSTALL_EXA" = "true" ]; then
    local exa_fragment exa_merged
    exa_fragment="$(mktemp)"
    jq -n '{mcp:{exa:{type:"remote",url:"https://mcp.exa.ai/mcp",enabled:true}}}' > "$exa_fragment"
    exa_merged="$(mktemp)"
    # `*` merges deeply, so only the mcp block is added.
    jq -s '.[0] * .[1]' "$source_config" "$exa_fragment" > "$exa_merged"
    rm -f "$exa_fragment"
    generated_configs+=("$exa_merged")
    source_config="$exa_merged"
  fi

  if [ "$USE_LOCAL_MODEL" = "true" ]; then
    local model_merged
    # `*` merges deeply, so the provider is added and .model is replaced.
    model_merged="$(mktemp)"
    jq -s '.[0] * .[1]' "$source_config" <(opencode_local_model_config) > "$model_merged"
    generated_configs+=("$model_merged")
    source_config="$model_merged"
  fi

  install_file_into_sandbox "$source_config" /etc/opencode/opencode.json 644 755 root:root
  if [ "${#generated_configs[@]}" -gt 0 ]; then
    rm -f "${generated_configs[@]}"
  fi
}

install_codex_auth_plugin() {
  echo "Installing OpenAI Codex Auth plugin..."

  sbx exec "$SANDBOX_NAME" bash -lc "
    set -euo pipefail
    npx --yes opencode-openai-codex-auth@4.4.0
  "

  echo "Codex auth plugin installed. Run 'opencode auth login' inside the sandbox to authenticate."
  echo "Select: OpenAI -> ChatGPT Plus/Pro (Codex Subscription)"
}

usage_instructions() {
  sbx exec "$SANDBOX_NAME" bash -c '
cat <<MSG

------ Usage Instructions ------

Start with OpenRouter (default - DeepSeek model):

    opencode

    # Then inside opencode:
    # -> Run: /connect
    # -> Select: OpenRouter
    # -> Enter your OpenRouter API key (one time per sandbox)

    # DeepSeek is the default model (openrouter/deepseek/deepseek-v4-pro).
    # Switch models any time with /model.

Start:

    opencode

Start with OpenAI Plus/Pro subscription:

    opencode auth login

    # -> Select: OpenAI
    # -> Select: ChatGPT Plus/Pro (Manual URL Paste)
    #    (Paste the URL into your host browser, then copy the redirect URL back)
    
    opencode

Switch models at any time inside opencode with:

    /model

MSG
'
}

# OPENCODE_DISABLE_MODELS_FETCH # this can slow things down, so revisit whether really need this

echo "Starting opencode agent for project $PROJECT_BASENAME"
echo "Sandbox name: $SANDBOX_NAME"
echo "Project dir: $PROJECT_DIR"
if [ "$USE_LOCAL_MODEL" = true ]; then
  echo "Model: $LOCAL_LLM_MODEL at $LOCAL_LLM_BASE_URL"
else
  echo "Auth mode: OpenAI Codex (ChatGPT Plus/Pro OAuth)"
fi

# Reuse existing sandbox if it already exists
if sandboxExists "$SANDBOX_NAME"; then
  echo "✅ Existing sandbox found: $SANDBOX_NAME"
  echo "Reconnecting..."

  allow_opencode_network
  configure_sandbox_env
  install_pinned_opencode
  install_skills

  allow_codex_oauth_network
  copy_config
  install_codex_auth_plugin
  usage_instructions
  sbx exec -it -w "$PROJECT_DIR" "$SANDBOX_NAME" bash
else
  echo "🆕 Creating new sandbox: $SANDBOX_NAME"

  createWorkbenchSandbox "$PROJECT_DIR" "$SANDBOX_NAME"

  allow_opencode_network
  upgrade_system_packages
  install_node_lts
  configure_sandbox_env
  install_pinned_opencode
  install_skills

  allow_codex_oauth_network
  copy_config
  install_codex_auth_plugin
  usage_instructions
  sbx exec -it -w "$PROJECT_DIR" "$SANDBOX_NAME" bash
fi

##### SETTING OPENROUTER ##########

# sbx secr