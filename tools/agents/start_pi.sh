#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_llm.sh"

if [ -f /etc/agent-workbench/workbench.env ] &&
  grep -Fqx 'WORKBENCH_INSTANCE=true' /etc/agent-workbench/workbench.env; then
  use_gpu_box=false
  workspace_dir="$PWD"
  workspace_path_was_given=false
  for argument in "$@"; do
    case "$argument" in
      --gpu-box) use_gpu_box=true ;;
      -*) echo "ERROR: Unknown option: $argument" >&2; exit 1 ;;
      *)
        if [ "$workspace_path_was_given" = true ]; then
          echo "Usage: start-pi [--gpu-box] [WORKSPACE_PATH]" >&2
          exit 1
        fi
        workspace_dir="$argument"
        workspace_path_was_given=true
        ;;
    esac
  done
  if [ ! -d "$workspace_dir" ]; then
    echo "ERROR: Workspace directory does not exist: $workspace_dir" >&2
    exit 1
  fi
  if [ "$use_gpu_box" = true ]; then
    USE_GPU_BOX=true
    resolve_local_llm
    config_dir="$HOME/.pi/agent"
    mkdir -p "$config_dir"
    models_config="$(mktemp)"
    settings_config="$(mktemp)"
    pi_models_config > "$models_config"
    pi_default_model_settings > "$settings_config"
    merge_json_file "$models_config" "$config_dir/models.json"
    merge_json_file "$settings_config" "$config_dir/settings.json"
    rm -f "$models_config" "$settings_config"
    echo "Model: $LOCAL_LLM_MODEL at $LOCAL_LLM_BASE_URL"
  fi
  cd "$workspace_dir"
  exec pi
fi

source "$SCRIPT_DIR/local_workspace.sh"
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

  if [ "$USE_LOCAL_MODEL" = true ]; then
    local models_config settings_config
    models_config="$(mktemp)"
    settings_config="$(mktemp)"
    pi_models_config > "$models_config"
    pi_default_model_settings > "$settings_config"
    merge_json_into_sandbox_file "$models_config" /home/agent/.pi/agent/models.json
    merge_json_into_sandbox_file "$settings_config" /home/agent/.pi/agent/settings.json
    rm -f "$models_config" "$settings_config"
  fi
}

runSandboxHarness allow_pi_network install_pi true pi
