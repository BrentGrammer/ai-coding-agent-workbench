#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
source "$SCRIPT_DIR/local_llm.sh"
configureLocalLlmWorkspace "$@"

SANDBOX_NAME="opencode-$SANDBOX_WORKSPACE_NAME"
source "$SCRIPT_DIR/sandbox_bootstrap.sh"

if [ "$USE_LOCAL_MODEL" = true ]; then
  resolve_local_llm
fi

allow_opencode_network() {
  allow_system_update_network
  allow_standard_model_network
  local host
  for host in \
    api.openai.com:443 \
    auth.openai.com:443 \
    chatgpt.com:443 \
    generativelanguage.googleapis.com:443 \
    models.dev:443 \
    models.opencode.ai:443 \
    opencode.ai:443 \
    openrouter.ai:443
  do
    sbx policy allow network --sandbox "$SANDBOX_NAME" "$host"
  done
  if [ "$USE_LOCAL_MODEL" = true ]; then
    allow_local_llm_network
  fi
}

install_opencode() {
  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail
npm install -g opencode-ai@1.18.21 --ignore-scripts
(cd "$(npm root -g)/opencode-ai" && node postinstall.mjs)
opencode --version
'
  local source_config="$SCRIPT_DIR/opencode.json"
  local generated_config=""
  if [ "$USE_LOCAL_MODEL" = true ]; then
    generated_config="$(mktemp)"
    jq -s '.[0] * .[1]' "$source_config" <(opencode_local_model_config) > "$generated_config"
    source_config="$generated_config"
  fi
  install_file_into_sandbox "$source_config" /etc/opencode/opencode.json 644 755 root:root
  [ -z "$generated_config" ] || rm -f "$generated_config"
}

runSandboxHarness allow_opencode_network install_opencode true opencode
