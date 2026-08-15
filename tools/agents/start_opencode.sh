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

USE_LOCAL_MODEL=false
opencode_args=()
for arg in "$@"; do
  case "$arg" in
    --local-model) USE_LOCAL_MODEL=true ;;
    *) opencode_args+=("$arg") ;;
  esac
done
# bash 3.2, which macOS ships, treats an empty array as unset under `set -u`.
configureLocalWorkspace ${opencode_args[@]+"${opencode_args[@]}"}
copyMissingProjectInstructions "$PROMPT_INSTRUCTION_COPY"
REPO_ROOT="$WORKSPACE_ROOT_DIR"
REPO_NAME="$WORKSPACE_NAME"
REPO_REPLACE_UNDERSCORES="$SANDBOX_WORKSPACE_NAME"
PROJECT_DIR="$REPO_ROOT"
PROJECT_BASENAME="$REPO_NAME"
SANDBOX_NAME="opencode-$REPO_REPLACE_UNDERSCORES"
START_DOCKER="$WORKBENCH_ROOT/tools/scripts/start_docker.sh"

source "$SCRIPT_DIR/sandbox_bootstrap.sh"

LOCAL_OLLAMA_PORT=11434
LOCAL_PROXY_PORT=11435
LOCAL_PROXY_BIND="${WORKBENCH_LLM_PROXY_BIND:-127.0.0.1}"

port_is_open() {
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

start_local_ollama() {
  if port_is_open "$LOCAL_OLLAMA_PORT"; then
    return 0
  fi
  echo "Starting Ollama..."
  OLLAMA_HOST="127.0.0.1:$LOCAL_OLLAMA_PORT" \
    nohup ollama serve >/tmp/workbench-ollama.log 2>&1 &
  sleep 1
}

# The agent must not reach Ollama itself. That port also pulls, creates, and
# deletes models, and a pull fetches from any registry host the caller names.
start_local_inference_proxy() {
  if port_is_open "$LOCAL_PROXY_PORT"; then
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required for --local-model." >&2
    exit 1
  fi
  echo "Starting the inference-only proxy..."
  nohup python3 "$WORKBENCH_ROOT/tools/llm/ollama_inference_proxy.py" \
    "$LOCAL_PROXY_BIND:$LOCAL_PROXY_PORT" "127.0.0.1:$LOCAL_OLLAMA_PORT" \
    >/tmp/workbench-llm-proxy.log 2>&1 &
  sleep 1
}

if [ "$USE_LOCAL_MODEL" = true ]; then
  if [ -f /etc/agent-workbench/workbench.env ]; then
    set -a
    # shellcheck disable=SC1091
    . /etc/agent-workbench/workbench.env
    set +a
  fi
  LOCAL_LLM_BASE_URL="${LOCAL_LLM_BASE_URL:-http://host.docker.internal:$LOCAL_PROXY_PORT/v1}"
  LOCAL_LLM_MODEL="${LOCAL_LLM_MODEL:-qwen3.8:27b-mlx}"
  if [[ "$LOCAL_LLM_BASE_URL" == *host.docker.internal* ]]; then
    start_local_ollama
    start_local_inference_proxy
  fi
fi

bash "$START_DOCKER"

# One-time setup per sandbox name - enter your API key for BYOK usage:
#   Ex: sbx secret set <sandbox_name> openai
#
# Usage:
#   ./tools/agents/start_opencode.sh [--local-model] [WORKSPACE_PATH]

allow_opencode_network() {
  allow_gemini_access
  allow_system_update_network
  allow_vendor_docs_network
  allow_exa_mcp_network
  allow_skills_marketplace_network
  sbx policy allow network --sandbox "$SANDBOX_NAME" nodejs.org:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" registry.npmjs.org:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" models.dev:443
  # exa searches
  sbx policy allow network --sandbox "$SANDBOX_NAME" cdn.jsdelivr.net:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" raw.githubusercontent.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" opencode.ai:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" openrouter.ai:443
  if [ "$USE_LOCAL_MODEL" = true ]; then
    allow_local_llm_network
  fi
}

allow_local_llm_network() {
  local without_scheme="${LOCAL_LLM_BASE_URL#*://}"
  local hostport="${without_scheme%%/*}"
  if [ -z "$hostport" ]; then
    return 0
  fi
  if [[ "$hostport" != *:* ]]; then
    if [[ "$LOCAL_LLM_BASE_URL" == https://* ]]; then
      hostport="${hostport}:443"
    else
      hostport="${hostport}:80"
    fi
  fi
  sbx policy allow network --sandbox "$SANDBOX_NAME" "$hostport"
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

npm install -g opencode-ai@1.18.11 --ignore-scripts

(cd "$(npm root -g)/opencode-ai" && node postinstall.mjs)

opencode --version
'
}

install_skills() {
  install_matt_pocock_skills "$REPO_ROOT" opencode
  install_skill_creator "$REPO_ROOT" opencode
  install_no_mistakes "$REPO_ROOT" opencode
}

copy_config() {
  local opencode_config="$SCRIPT_DIR/opencode.json"
  local generated_config=""

  if [ ! -f "$opencode_config" ]; then
    echo "WARN: No workbench OpenCode config at $opencode_config" >&2
    return
  fi

  if [ "$USE_LOCAL_MODEL" = true ]; then
    if ! command -v jq >/dev/null 2>&1; then
      echo "ERROR: jq is required for --local-model." >&2
      exit 1
    fi
    generated_config="$(mktemp)"
    jq --arg url "$LOCAL_LLM_BASE_URL" --arg model "$LOCAL_LLM_MODEL" \
      '.model = ("local-llm/" + $model)
       | .provider += {
           "local-llm": {
             "npm": "@ai-sdk/openai-compatible",
             "name": "Local LLM",
             "options": { "baseURL": $url, "apiKey": "ollama" },
             "models": { ($model): { "name": $model } }
           }
         }' "$opencode_config" > "$generated_config"
    opencode_config="$generated_config"
  fi

  install_file_into_sandbox "$opencode_config" /etc/opencode/opencode.json 644 755 root:root
  if [ -n "$generated_config" ]; then
    rm -f "$generated_config"
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

# sbx secret set-custom "$SANDBOX_NAME" --host openrouter.ai --env OPENROUTER_API_KEY
