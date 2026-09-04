export DO_NOT_TRACK=1
export DISABLE_ERROR_REPORTING=1
export DISABLE_TELEMETRY=1
export DISABLE_FEEDBACK_COMMAND=1
export GEMINI_TELEMETRY_ENABLED=false
export GEMINI_TELEMETRY_TRACES_ENABLED=false
export GEMINI_TELEMETRY_LOG_PROMPTS=false
export NPM_CONFIG_PREFIX="$HOME/.local/npm"

if [ -f /etc/agent-workbench/workbench.env ]; then
  set -a
  . /etc/agent-workbench/workbench.env
  set +a
fi

case ":$PATH:" in
  *":$HOME/.local/npm/bin:"*) ;;
  *) export PATH="$HOME/.local/npm/bin:$HOME/.local/bin:$PATH" ;;
esac

umask 002

if [ "$(id -un)" = "agent" ]; then
  export HTTP_PROXY="http://127.0.0.1:8888"
  export HTTPS_PROXY="http://127.0.0.1:8888"
  export http_proxy="http://127.0.0.1:8888"
  export https_proxy="http://127.0.0.1:8888"
  export NO_PROXY="127.0.0.1,localhost"
  export no_proxy="127.0.0.1,localhost"
fi

# Interactive login shells only.
case $- in
  *i*)
    if [ -t 1 ] && [ -f /etc/agent-workbench/login-welcome ]; then
      cat /etc/agent-workbench/login-welcome
    fi
    ;;
esac
