#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
source "$SCRIPT_DIR/local_llm.sh"
configureLocalLlmWorkspace "$@"

SANDBOX_NAME="kilo-$SANDBOX_WORKSPACE_NAME"
source "$SCRIPT_DIR/sandbox_bootstrap.sh"

if [ "$USE_LOCAL_MODEL" = true ]; then
  resolve_local_llm
fi

allow_kilo_network() {
  allow_system_update_network
  local host
  for host in \
    api.kilo.ai:443 \
    kilo.ai:443 \
    models.dev:443 \
    api.openai.com:443 \
    api.anthropic.com:443 \
    openrouter.ai:443 \
    api.openrouter.ai:443
  do
    sbx policy allow network --sandbox "$SANDBOX_NAME" "$host"
  done
  if [ "$USE_LOCAL_MODEL" = true ]; then
    allow_local_llm_network
  fi
}

install_kilo() {
  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail
export NPM_CONFIG_PREFIX="$HOME/.local"
export PATH="$HOME/.local/bin:$PATH"
mkdir -p "$HOME/.local/bin" "$HOME/.local/lib"
npm install -g @kilocode/cli@7.4.22 --ignore-scripts
grep -q "HOME/.local/bin" "$HOME/.bashrc" 2>/dev/null ||
  echo '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> "$HOME/.bashrc"
'

  if [ "$USE_LOCAL_MODEL" = true ]; then
    local kilo_config
    kilo_config="$(mktemp)"
    kilo_local_model_config > "$kilo_config"
    merge_json_into_sandbox_file "$kilo_config" /home/agent/.config/kilo/kilo.jsonc
    rm -f "$kilo_config"
  fi
}

runSandboxHarness allow_kilo_network install_kilo true kilo
