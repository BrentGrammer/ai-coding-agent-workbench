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
configureLocalWorkspace "$@"
REPO_ROOT="$WORKSPACE_ROOT_DIR"
REPO_NAME="$WORKSPACE_NAME"
REPO_REPLACE_UNDERSCORES="$SANDBOX_WORKSPACE_NAME"
PROJECT_DIR="$REPO_ROOT"
PROJECT_BASENAME="$REPO_NAME"
SANDBOX_NAME="opencode-$REPO_REPLACE_UNDERSCORES"
START_DOCKER="$WORKBENCH_ROOT/tools/scripts/start_docker.sh"

source "$SCRIPT_DIR/sandbox_bootstrap.sh"

bash "$START_DOCKER"

# One-time setup per sandbox name - enter your API key for BYOK usage:
#   Ex: sbx secret set <sandbox_name> openai
#
# Usage:
#   ./tools/agents/start_opencode.sh

allow_opencode_network() {
  allow_gemini_access
  allow_system_update_network
  allow_vendor_docs_network
  allow_exa_mcp_network
  sbx policy allow network --sandbox "$SANDBOX_NAME" nodejs.org:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" registry.npmjs.org:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" models.dev:443
  # exa searches
  sbx policy allow network --sandbox "$SANDBOX_NAME" cdn.jsdelivr.net:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" raw.githubusercontent.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" opencode.ai:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" openrouter.ai:443

  # Required by `npx skills add mattpocock/skills`
  sbx policy allow network --sandbox "$SANDBOX_NAME" github.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" api.github.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" codeload.github.com:443

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

update_opencode() {
  echo "Updating OpenCode inside sandbox..."

  sbx exec -d "$SANDBOX_NAME" bash -c '
set -euo pipefail

npm install -g opencode-ai@latest

opencode --version
'
}

install_skills() {
  echo "Installing Matt Pocock skills..."

  sbx exec "$SANDBOX_NAME" bash -lc "
    set -euo pipefail
    cd '$REPO_ROOT'

    npx --yes skills@latest add mattpocock/skills \
      --agent opencode \
      --skill '*' \
      --global \
      --yes \
      --copy
  "
}

update_skills() {
  echo "Updating Matt Pocock skills..."

  sbx exec "$SANDBOX_NAME" bash -lc "
    set -euo pipefail
    cd '$REPO_ROOT'

    npx --yes skills@latest update -g -y
  "
}

copy_config() {
  local opencode_config="$SCRIPT_DIR/opencode.json"

  if [ ! -f "$opencode_config" ]; then
    echo "WARN: No workbench OpenCode config at $opencode_config" >&2
    return
  fi

  sbx cp "$opencode_config" "$SANDBOX_NAME":/tmp/opencode.json
  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail
sudo install -d -m 755 -o root -g root /etc/opencode
sudo install -m 644 -o root -g root /tmp/opencode.json /etc/opencode/opencode.json
sudo rm -f /tmp/opencode.json
'
}

install_codex_auth_plugin() {
  echo "Installing OpenAI Codex Auth plugin..."

  sbx exec "$SANDBOX_NAME" bash -lc "
    set -euo pipefail
    npx --yes opencode-openai-codex-auth@latest
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
echo "Auth mode: OpenAI Codex (ChatGPT Plus/Pro OAuth)"

# Reuse existing sandbox if it already exists
if sandboxExists "$SANDBOX_NAME"; then
  echo "✅ Existing sandbox found: $SANDBOX_NAME"
  echo "Reconnecting..."

  allow_opencode_network
  configure_sandbox_env
  update_opencode
  update_skills

  allow_codex_oauth_network
  copy_config
  install_codex_auth_plugin
  usage_instructions
  sbx exec -it -w "$PROJECT_DIR" "$SANDBOX_NAME" bash
else
  echo "🆕 Creating new sandbox: $SANDBOX_NAME"

  sbx create opencode "$PROJECT_DIR" --name "$SANDBOX_NAME"

  allow_opencode_network
  upgrade_system_packages
  install_node_lts
  configure_sandbox_env
  install_skills

  allow_codex_oauth_network
  copy_config
  install_codex_auth_plugin
  usage_instructions
  sbx exec -it -w "$PROJECT_DIR" "$SANDBOX_NAME" bash
fi

##### SETTING OPENROUTER ##########

# sbx secret set-custom "$SANDBOX_NAME" --host openrouter.ai --env OPENROUTER_API_KEY
