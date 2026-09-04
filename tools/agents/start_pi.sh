#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_llm.sh"

if [ -f /etc/agent-workbench/workbench.env ] &&
  grep -Fqx 'WORKBENCH_INSTANCE=true' /etc/agent-workbench/workbench.env; then
  use_gpu_box="${USE_GPU_BOX:-false}"
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

  if [ "$workspace_path_was_given" = false ] && { [ "$workspace_dir" = "$HOME" ] || [ "$workspace_dir" = "/home/ubuntu" ]; }; then
    workspace_dir="/home/agent/workspace"
  fi

  if [ ! -d "$workspace_dir" ]; then
    echo "ERROR: Workspace directory does not exist: $workspace_dir" >&2
    exit 1
  fi
  workspace_dir="$(cd "$workspace_dir" && pwd)"

  # ubuntu queries AWS because the agent user has IMDS blocked by nftables.
  if [ "$(id -un)" != "agent" ]; then
    gpu_ip=""
    if [ "$use_gpu_box" = true ]; then
      if [ -f /etc/agent-workbench/workbench.env ]; then
        # shellcheck disable=SC1091
        . /etc/agent-workbench/workbench.env
      fi
      gpu_ip="$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters \
          'Name=tag:Name,Values=aws-native-agent-workbench-gpu-llm' \
          'Name=instance-state-name,Values=running' \
        --query 'Reservations[0].Instances[0].PrivateIpAddress' \
        --output text)"
      if [ -z "$gpu_ip" ] || [ "$gpu_ip" = "None" ]; then
        echo "ERROR: No AWS GPU box is running. Run aws-workbench llm up from your laptop first." >&2
        exit 1
      fi
    fi
    exec sudo -u agent -i \
      GPU_BOX_IP="$gpu_ip" \
      USE_GPU_BOX="$use_gpu_box" \
      /opt/agent-workbench/tools/agents/start_pi.sh "$workspace_dir"
  fi

  # Running as agent user inside the setgid workspace.
  if [ "$use_gpu_box" = true ]; then
    if [ -z "${GPU_BOX_IP:-}" ]; then
      echo "ERROR: Run start-pi as ubuntu so it can discover the GPU box instance." >&2
      exit 1
    fi
    LOCAL_LLM_BASE_URL="http://${GPU_BOX_IP}:${LOCAL_PROXY_PORT}/v1"
    LOCAL_LLM_MODEL="${LOCAL_LLM_MODEL:-$GPU_BOX_MODEL}"
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
