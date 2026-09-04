#!/usr/bin/env bash
# Shared --local-model bootstrap for Pi. Source after local_workspace.sh
# (needs $WORKBENCH_ROOT) and set $SANDBOX_NAME before calling allow_local_llm_network.

LOCAL_OLLAMA_PORT=11434
LOCAL_PROXY_PORT=11435
GPU_BOX_MODEL=qwen3.8:27b
LOCAL_PROXY_BIND="${WORKBENCH_LLM_PROXY_BIND:-127.0.0.1}"
LOCAL_LLM_STATE_DIR="$HOME/.local/state/agent-workbench"

configureLocalLlmWorkspace() {
  USE_LOCAL_MODEL=false
  USE_GPU_BOX=false
  local workspace_args=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --local-model)
        USE_LOCAL_MODEL=true
        ;;
      --gpu-box)
        USE_LOCAL_MODEL=true
        USE_GPU_BOX=true
        ;;
      *)
        workspace_args+=("$1")
        ;;
    esac
    shift
  done

  configureLocalWorkspace "${workspace_args[@]}"
}

port_is_open() {
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

# stop-local-llm reads these files, so it only ever stops processes this
# launcher started and never an Ollama the user runs themselves.
start_local_ollama() {
  if port_is_open "$LOCAL_OLLAMA_PORT"; then
    return 0
  fi
  echo "Starting Ollama..."
  mkdir -p "$LOCAL_LLM_STATE_DIR"
  OLLAMA_HOST="127.0.0.1:$LOCAL_OLLAMA_PORT" \
    nohup ollama serve >"$LOCAL_LLM_STATE_DIR/ollama.log" 2>&1 &
  echo "$!" > "$LOCAL_LLM_STATE_DIR/ollama.pid"
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
  mkdir -p "$LOCAL_LLM_STATE_DIR"
  nohup python3 "$WORKBENCH_ROOT/tools/llm/ollama_inference_proxy.py" \
    "$LOCAL_PROXY_BIND:$LOCAL_PROXY_PORT" "127.0.0.1:$LOCAL_OLLAMA_PORT" \
    >"$LOCAL_LLM_STATE_DIR/llm-proxy.log" 2>&1 &
  echo "$!" > "$LOCAL_LLM_STATE_DIR/llm-proxy.pid"
  sleep 1
}

defaultLocalLlmModelForHost() {
  local host_kernel_name
  local macos_kernel_name="Darwin"
  local linux_kernel_name="Linux"
  host_kernel_name="$(uname -s)"

  case "$host_kernel_name" in
    "$macos_kernel_name") printf '%s\n' "qwen3.8:27b-mlx" ;;
    "$linux_kernel_name") printf '%s\n' "qwen3.8:27b" ;;
    *)
      echo "ERROR: No default local LLM model is configured for $host_kernel_name." >&2
      echo "Set LOCAL_LLM_MODEL explicitly." >&2
      return 1
      ;;
  esac
}

# Sets the local LLM configuration and starts host Ollama and its proxy.
resolve_local_llm() {
  if [ -f /etc/agent-workbench/workbench.env ]; then
    set -a
    # shellcheck disable=SC1091
    . /etc/agent-workbench/workbench.env
    set +a
  fi
  if [ "${USE_GPU_BOX:-false}" = true ]; then
    if [ "${WORKBENCH_INSTANCE:-false}" != true ]; then
      echo "ERROR: --gpu-box runs on the AWS workbench. Connect with start-aws-workbench first." >&2
      exit 1
    fi
    local gpu_ip
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
    LOCAL_LLM_BASE_URL="${LOCAL_LLM_BASE_URL:-http://$gpu_ip:$LOCAL_PROXY_PORT/v1}"
    LOCAL_LLM_MODEL="${LOCAL_LLM_MODEL:-$GPU_BOX_MODEL}"
  fi
  LOCAL_LLM_BASE_URL="${LOCAL_LLM_BASE_URL:-http://host.docker.internal:$LOCAL_PROXY_PORT/v1}"
  LOCAL_LLM_MODEL="${LOCAL_LLM_MODEL:-$(defaultLocalLlmModelForHost)}"
  # none | low | medium | high
  LOCAL_LLM_REASONING_EFFORT="${LOCAL_LLM_REASONING_EFFORT:-medium}"
  if [[ "$LOCAL_LLM_BASE_URL" == *host.docker.internal* ]]; then
    start_local_ollama
    start_local_inference_proxy
  fi
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required for local-model configuration." >&2
    exit 1
  fi
}

pi_default_model_settings() {
  require_jq
  jq -n --arg model "$LOCAL_LLM_MODEL" --arg thinking "$LOCAL_LLM_REASONING_EFFORT" \
    '{
       defaultProvider: "local-llm",
       defaultModel: $model,
       defaultThinkingLevel: (if $thinking == "" then "medium" else $thinking end)
     }'
}

pi_models_config() {
  require_jq
  jq -n --arg url "$LOCAL_LLM_BASE_URL" --arg model "$LOCAL_LLM_MODEL" \
    '{providers:{"local-llm":{baseUrl:$url,api:"openai-completions",apiKey:"ollama",models:[{id:$model,reasoning:true,thinkingLevelMap:{off:"none",minimal:null,low:"low",medium:"medium",high:"high",xhigh:null,max:null},compat:{supportsReasoningEffort:true}}]}}}'
}

merge_json_file() {
  local fragment="$1" destination="$2"
  local existing merged
  existing="$(mktemp)"
  merged="$(mktemp)"
  if ! jq -e . "$destination" > "$existing" 2>/dev/null; then
    echo '{}' > "$existing"
  fi
  jq -s '.[0] * .[1]' "$existing" "$fragment" > "$merged"
  install -m 600 "$merged" "$destination"
  rm -f "$existing" "$merged"
}

# Pi writes its own state back to these files, so replacing one would
# discard the model, permission and MCP choices made in the last session.
merge_json_into_sandbox_file() {
  local fragment="$1" dest="$2"
  require_jq
  local existing merged
  existing="$(mktemp)"
  merged="$(mktemp)"

  sbx exec "$SANDBOX_NAME" bash -c "cat '$dest' 2>/dev/null" > "$existing" || true
  if ! jq -e . "$existing" >/dev/null 2>&1; then
    if [ -s "$existing" ]; then
      echo "WARN: $dest is not plain JSON in the sandbox, replacing it." >&2
    fi
    echo '{}' > "$existing"
  fi

  jq -s '.[0] * .[1]' "$existing" "$fragment" > "$merged"
  install_file_into_sandbox "$merged" "$dest"
  rm -f "$existing" "$merged"
}

# Allowlists the sandbox to reach LOCAL_LLM_BASE_URL. Needs $SANDBOX_NAME.
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

  # sbx maps host.docker.internal to host loopback, which network policy
  # identifies as localhost.
  if [[ "$hostport" == host.docker.internal:* ]]; then
    sbx policy allow network --sandbox "$SANDBOX_NAME" "localhost:${hostport#*:}"
  fi
}
