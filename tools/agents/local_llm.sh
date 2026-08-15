#!/usr/bin/env bash
# Shared --local-model bootstrap for launchers. Source after local_workspace.sh
# (needs $WORKBENCH_ROOT) and set $SANDBOX_NAME before calling allow_local_llm_network.

LOCAL_OLLAMA_PORT=11434
LOCAL_PROXY_PORT=11435
LOCAL_PROXY_BIND="${WORKBENCH_LLM_PROXY_BIND:-127.0.0.1}"
LOCAL_LLM_STATE_DIR="$HOME/.local/state/agent-workbench"

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

# Sets LOCAL_LLM_BASE_URL / LOCAL_LLM_MODEL, and starts Ollama and the proxy
# on a Mac. On the EC2 workbench box, workbench.env already points at the GPU
# box, so nothing local needs to start.
resolve_local_llm() {
  if [ -f /etc/agent-workbench/workbench.env ]; then
    set -a
    # shellcheck disable=SC1091
    . /etc/agent-workbench/workbench.env
    set +a
  fi
  LOCAL_LLM_BASE_URL="${LOCAL_LLM_BASE_URL:-http://host.docker.internal:$LOCAL_PROXY_PORT/v1}"
  LOCAL_LLM_MODEL="${LOCAL_LLM_MODEL:-qwen3.8:27b-mlx}"
  # none | low | medium | high
  LOCAL_LLM_REASONING_EFFORT="${LOCAL_LLM_REASONING_EFFORT:-medium}"
  if [[ "$LOCAL_LLM_BASE_URL" == *host.docker.internal* ]]; then
    start_local_ollama
    start_local_inference_proxy
  fi
}

# One line, because the EC2 box carries this in OPENCODE_CONFIG_CONTENT.
# reasoningEffort may be dropped for custom providers (anomalyco/opencode#27361).
opencode_local_model_config() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required for --local-model." >&2
    exit 1
  fi
  jq -nc --arg url "$LOCAL_LLM_BASE_URL" --arg model "$LOCAL_LLM_MODEL" \
     --arg effort "$LOCAL_LLM_REASONING_EFFORT" \
    '{
       model: ("local-llm/" + $model),
       provider: {
         "local-llm": {
           npm: "@ai-sdk/openai-compatible",
           name: "Local LLM",
           options: { baseURL: $url, apiKey: "ollama" },
           models: {
             ($model): (
               { name: $model }
               + (if $effort == "" then {} else { options: { reasoningEffort: $effort } } end)
             )
           }
         }
       }
     }'
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

  # Docker Desktop routes host.docker.internal to the host's loopback
  # interface, and sbx's network policy checks the resolved destination, so
  # it reports the connection as "localhost", not "host.docker.internal".
  if [[ "$hostport" == host.docker.internal:* ]]; then
    sbx policy allow network --sandbox "$SANDBOX_NAME" "localhost:${hostport#*:}"
  fi
}
