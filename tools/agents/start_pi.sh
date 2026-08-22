#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
source "$SCRIPT_DIR/local_llm.sh"
configureLocalLlmWorkspace "$@"

SANDBOX_NAME="pi-$SANDBOX_WORKSPACE_NAME"
source "$SCRIPT_DIR/sandbox_bootstrap.sh"

if [ "$USE_LOCAL_MODEL" = true ]; then
  resolve_local_llm
fi

allow_pi_network() {
  allow_system_update_network
  allow_standard_model_network
  sbx policy allow network --sandbox "$SANDBOX_NAME" pi.dev:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" release-assets.githubusercontent.com:443
  if [ "$USE_LOCAL_MODEL" = true ]; then
    allow_local_llm_network
  fi
}

install_pi() {
  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail
sudo npm install -g --ignore-scripts @earendil-works/pi-coding-agent@0.84.2
'

  merge_json_into_sandbox_file "$SCRIPT_DIR/config/pi/settings.json" /home/agent/.pi/agent/settings.json

  if [ "$USE_LOCAL_MODEL" = true ]; then
    local models_config settings_config
    models_config="$(mktemp)"
    settings_config="$(mktemp)"
    jq -n --arg url "$LOCAL_LLM_BASE_URL" --arg model "$LOCAL_LLM_MODEL" \
      '{providers:{"local-llm":{baseUrl:$url,api:"openai-completions",apiKey:"ollama",models:[{id:$model,reasoning:true,thinkingLevelMap:{off:"none",minimal:null,low:"low",medium:"medium",high:"high",xhigh:null,max:null},compat:{supportsReasoningEffort:true}}]}}}' \
      > "$models_config"
    pi_default_model_settings > "$settings_config"
    merge_json_into_sandbox_file "$models_config" /home/agent/.pi/agent/models.json
    merge_json_into_sandbox_file "$settings_config" /home/agent/.pi/agent/settings.json
    rm -f "$models_config" "$settings_config"
  fi

  install_file_into_sandbox \
    "$SCRIPT_DIR/config/pi/terminal-status-title.js" \
    /home/agent/.pi/agent/extensions/terminal-status-title.js

  install_file_into_sandbox \
    "$SCRIPT_DIR/config/pi/welcome.sh" \
    /home/agent/.pi-welcome.sh
}

after_sandbox_install() {
  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail
if [ -f "$HOME/.bashrc" ]; then
  awk "
    /pi-welcome.sh/ { skip=1; next }
    skip && /^fi\$/ { skip=0; next }
    skip { next }
    { print }
  " "$HOME/.bashrc" > "$HOME/.bashrc.tmp" && mv "$HOME/.bashrc.tmp" "$HOME/.bashrc"
fi
cat >> "$HOME/.bashrc" <<'"'"'EOF'"'"'

if [[ $- == *i* ]] && [ -t 1 ] && [ -f "$HOME/.pi-welcome.sh" ]; then
  bash "$HOME/.pi-welcome.sh"
fi
EOF
'
}

runSandboxHarness allow_pi_network install_pi true bash
