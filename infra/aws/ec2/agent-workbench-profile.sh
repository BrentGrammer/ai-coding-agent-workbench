export DO_NOT_TRACK=1
export DISABLE_ERROR_REPORTING=1
export DISABLE_TELEMETRY=1
export DISABLE_FEEDBACK_COMMAND=1
export CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY=1
export GEMINI_TELEMETRY_ENABLED=false
export GEMINI_TELEMETRY_TRACES_ENABLED=false
export GEMINI_TELEMETRY_LOG_PROMPTS=false
export OPENCODE_DISABLE_SHARE=1
export OPENCODE_AUTO_SHARE=false

export HERDR_CONFIG_PATH=/etc/agent-workbench/herdr-config.toml
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
