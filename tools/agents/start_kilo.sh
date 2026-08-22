#!/usr/bin/env bash
set -euo pipefail

PREFIX_NAME="kilo"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"

selectModelHost "$@"
configureLocalWorkspace ${LAUNCHER_ARGS[@]+"${LAUNCHER_ARGS[@]}"}
copyMissingProjectInstructions "$PROMPT_INSTRUCTION_COPY"
REPO_ROOT="$WORKSPACE_ROOT_DIR"
REPO_REPLACE_UNDERSCORES="$SANDBOX_WORKSPACE_NAME"
SANDBOX_NAME="$PREFIX_NAME-$REPO_REPLACE_UNDERSCORES"
START_DOCKER="$WORKBENCH_ROOT/tools/scripts/start_docker.sh"

source "$SCRIPT_DIR/sandbox_bootstrap.sh"
source "$SCRIPT_DIR/local_llm.sh"

if [ "$USE_LOCAL_MODEL" = true ]; then
  resolve_local_llm
fi

echo "Using sandbox name: $SANDBOX_NAME"

bash "$START_DOCKER"

openLocalWorkspace

allow_network() {
  allow_system_update_network
  allow_vendor_docs_network
  allow_skills_marketplace_network

  sbx policy allow network --sandbox "$SANDBOX_NAME" kilo.ai:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" app.kilo.ai:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" api.kilo.ai:443

  sbx policy allow network --sandbox "$SANDBOX_NAME" registry.npmjs.org:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" nodejs.org:443

  # Common BYOK/provider targets Kilo may need after /connect.
  sbx policy allow network --sandbox "$SANDBOX_NAME" api.openai.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" platform.openai.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" api.anthropic.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" console.anthropic.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" openrouter.ai:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" api.openrouter.ai:443

  if [ "$USE_LOCAL_MODEL" = true ]; then
    allow_local_llm_network
  fi
}

configure_kilo_env() {
  echo "Configuring Kilo Code-specific env..."

  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail

PERSISTENT_ENV="/etc/sandbox-persistent.sh"

sudo touch "$PERSISTENT_ENV"
sudo sed -i "/^export NPM_CONFIG_PREFIX=/d" "$PERSISTENT_ENV"
sudo tee -a "$PERSISTENT_ENV" >/dev/null <<EOF
export NPM_CONFIG_PREFIX="\$HOME/.local"
EOF
'
}

install_pinned_kilo() {
  echo "Installing pinned Kilo Code CLI..."

  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail

source /etc/sandbox-persistent.sh 2>/dev/null || true
export PATH="$HOME/.local/bin:$PATH"
export NPM_CONFIG_PREFIX="${NPM_CONFIG_PREFIX:-$HOME/.local}"

mkdir -p "$HOME/.local/bin" "$HOME/.local/lib"

npm install -g @kilocode/cli@7.4.22 --ignore-scripts

if ! grep "HOME/.local/bin" "$HOME/.bashrc" 2>/dev/null; then
  echo '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> "$HOME/.bashrc"
fi
'
}

copy_config() {
  local kilo_config_file="$SCRIPT_DIR/kilo.jsonc"

  if [ -f "$kilo_config_file" ]; then
    echo "Copying bundled Kilo config into sandbox home..."
    install_file_into_sandbox "$kilo_config_file" /home/agent/.config/kilo/kilo.jsonc
  fi
}

install_kilo_local_model_config() {
  if [ "$USE_LOCAL_MODEL" != true ]; then
    return
  fi
  local kilo_config
  kilo_config="$(mktemp)"
  kilo_local_model_config > "$kilo_config"
  merge_json_into_sandbox_file "$kilo_config" /home/agent/.config/kilo/kilo.jsonc
  rm -f "$kilo_config"
}

usage_instructions() {
  local local_model_lines=""
  if [ "$USE_LOCAL_MODEL" = true ]; then
    local_model_lines="
Already set as the default model:

  $LOCAL_LLM_MODEL at $LOCAL_LLM_BASE_URL

"
  fi
  sbx exec "$SANDBOX_NAME" bash -c '
cat > "$HOME/.kilo-code-welcome.sh" <<EOF
cat <<MSG

✅ sandbox is ready: '"$SANDBOX_NAME"'

Run Kilo Code CLI:

  kilo
'"$local_model_lines"'
First-time provider setup:

  kilo
  /connect

Or use CLI auth:

  kilo auth login

Switch models with /models inside the session.

Kilo published command list is stale, so ask the binary:

  kilo help --all --format md

There is no kilo update. The version is pinned in start_kilo.sh.

MSG
EOF

if ! grep -q ".kilo-code-welcome.sh" "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<EOF

if [ -t 1 ] && [ -f "\$HOME/.kilo-code-welcome.sh" ]; then
  bash "\$HOME/.kilo-code-welcome.sh"
fi
EOF
fi
'
}

if sandboxExists "$SANDBOX_NAME"; then
  echo "✅ Existing sandbox found: $SANDBOX_NAME"
  echo "Reconnecting..."

  allow_network
  configure_sandbox_env
  configure_kilo_env
  install_pinned_kilo
  copy_config
  install_kilo_local_model_config
  install_matt_pocock_skills "$REPO_ROOT" kilo
  install_skill_creator "$REPO_ROOT" kilo
  install_github_tools "$REPO_ROOT" kilo
  usage_instructions

  sbx run "$SANDBOX_NAME"
else
  echo "🆕 Creating new sandbox: $SANDBOX_NAME"

  createWorkbenchSandbox "$REPO_ROOT" "$SANDBOX_NAME"

  allow_network
  upgrade_system_packages
  install_node_lts
  configure_sandbox_env
  configure_kilo_env
  install_pinned_kilo
  copy_config
  install_kilo_local_model_config
  install_matt_pocock_skills "$REPO_ROOT" kilo
  install_skill_creator "$REPO_ROOT" kilo
  install_github_tools "$REPO_ROOT" kilo
  usage_instructions

  sbx run "$SANDBOX_NAME"
fi
