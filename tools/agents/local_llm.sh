#!/usr/bin/env bash
# Shared --local-model bootstrap for launchers. Source after local_workspace.sh
# (needs $WORKBENCH_ROOT) and set $SANDBOX_NAME before calling allow_local_llm_network.

LOCAL_OLLAMA_PORT=11434
LOCAL_PROXY_PORT=11435
# The GPU box joins the tailnet under this name and serves LLM_MODEL from the
# CDK stack. Set USE_GPU_BOX=true to target it instead of a local Ollama.
GPU_BOX_HOST=agent-llm
GPU_BOX_MODEL=qwen3.8:27b
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

host_from_url() {
  local rest="${1#*://}"
  rest="${rest%%/*}"
  echo "${rest%%:*}"
}

# The online node only. A dead node keeps the name until Tailscale reaps it,
# so the live box joins as name-1 and the name itself times out.
tailnet_ip() {
  command -v tailscale >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  local ip
  ip="$(tailscale status --json 2>/dev/null |
    jq -r --arg name "$1" \
      '[.Peer[]? | select(.Online and (.HostName == $name or (.HostName | test("^\($name)-[0-9]+$"))))][0].TailscaleIPs[0] // empty' \
      2>/dev/null)" || return 1
  [ -n "$ip" ] || return 1
  echo "$ip"
}

# The Docker sandbox routes to the tailnet but cannot resolve MagicDNS names,
# so swap a tailnet hostname for its address before the agent ever sees the URL.
use_tailnet_address() {
  local host ip
  host="$(host_from_url "$LOCAL_LLM_BASE_URL")"
  case "$host" in
    "" | localhost | host.docker.internal) return 0 ;;
    *[!0-9.]*) ;;
    *) return 0 ;;
  esac
  ip="$(tailnet_ip "$host")" || return 0
  LOCAL_LLM_BASE_URL="${LOCAL_LLM_BASE_URL/$host/$ip}"
  echo "Resolved $host to $ip on the tailnet."
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
  if [ "${USE_GPU_BOX:-false}" = true ]; then
    LOCAL_LLM_BASE_URL="${LOCAL_LLM_BASE_URL:-http://$GPU_BOX_HOST:$LOCAL_PROXY_PORT/v1}"
    LOCAL_LLM_MODEL="${LOCAL_LLM_MODEL:-$GPU_BOX_MODEL}"
  fi
  LOCAL_LLM_BASE_URL="${LOCAL_LLM_BASE_URL:-http://host.docker.internal:$LOCAL_PROXY_PORT/v1}"
  LOCAL_LLM_MODEL="${LOCAL_LLM_MODEL:-qwen3.8:27b-mlx}"
  LOCAL_LLM_CONTEXT_LENGTH="${LOCAL_LLM_CONTEXT_LENGTH:-${OLLAMA_CONTEXT_LENGTH:-131072}}"
  # none | low | medium | high
  LOCAL_LLM_REASONING_EFFORT="${LOCAL_LLM_REASONING_EFFORT:-medium}"
  if [[ "$LOCAL_LLM_BASE_URL" == *host.docker.internal* ]]; then
    start_local_ollama
    start_local_inference_proxy
  else
    use_tailnet_address
  fi
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required for --local-model." >&2
    exit 1
  fi
}

# reasoningEffort may be dropped for custom providers (anomalyco/opencode#27361).
opencode_local_model_config() {
  require_jq
  jq -n --arg url "$LOCAL_LLM_BASE_URL" --arg model "$LOCAL_LLM_MODEL" \
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

kilo_local_model_config() {
  require_jq
  jq -n --arg url "$LOCAL_LLM_BASE_URL" --arg model "$LOCAL_LLM_MODEL" \
     --argjson context "$LOCAL_LLM_CONTEXT_LENGTH" \
    '{
       "$schema": "https://app.kilo.ai/config.json",
       model: ("local-llm/" + $model),
       provider: {
         "local-llm": {
           npm: "@ai-sdk/openai-compatible",
           name: "Local LLM",
           options: { baseURL: $url, apiKey: "ollama" },
           models: {
             ($model): {
               name: $model,
               tool_call: true,
               limit: { context: $context, output: 32768 }
             }
           }
         }
       }
     }'
}

qwen_local_model_config() {
  require_jq
  jq -n --arg url "$LOCAL_LLM_BASE_URL" --arg model "$LOCAL_LLM_MODEL" \
     --argjson context "$LOCAL_LLM_CONTEXT_LENGTH" \
    '{
       env: { OLLAMA_API_KEY: "ollama" },
       security: { auth: { selectedType: "openai" } },
       model: { name: $model },
       modelProviders: {
         openai: [ {
           id: $model,
           name: "Local LLM",
           envKey: "OLLAMA_API_KEY",
           baseUrl: $url,
           generationConfig: {
             timeout: 300000,
             maxRetries: 1,
             contextWindowSize: $context
           }
         } ]
       }
     }'
}

# Harnesses write their own state back to these files, so replacing one would
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

  # Docker Desktop routes host.docker.internal to the host's loopback
  # interface, and sbx's network policy checks the resolved destination, so
  # it reports the connection as "localhost", not "host.docker.internal".
  if [[ "$hostport" == host.docker.internal:* ]]; then
    sbx policy allow network --sandbox "$SANDBOX_NAME" "localhost:${hostport#*:}"
  fi
}
