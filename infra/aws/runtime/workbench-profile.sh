case "$-" in
  *i*)
    ;;
  *)
    return 2>/dev/null || exit
    ;;
esac

SESSION_CONFIG_FILE="/mnt/workspace/config/session.env"

if [ -f "$SESSION_CONFIG_FILE" ]; then
  source "$SESSION_CONFIG_FILE"
  export NPM_CONFIG_PREFIX="/home/agent/.local/npm"
  export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"
  export CODEX_SQLITE_HOME="/tmp/agent-workbench/codex-$WORKBENCH_SESSION"
  export TMPDIR="/tmp/agent-workbench/tmp"
  export XDG_CACHE_HOME="/tmp/agent-workbench/cache"
  export npm_config_cache="/tmp/agent-workbench/npm"
  export PIP_CACHE_DIR="/tmp/agent-workbench/pip"
  mkdir -p "$CODEX_SQLITE_HOME" "$TMPDIR" "$XDG_CACHE_HOME" "$npm_config_cache" "$PIP_CACHE_DIR"
  if [ -n "${WORKSPACE_DIR:-}" ] && [ -d "$WORKSPACE_DIR" ]; then
    find "$WORKSPACE_DIR" \( -name node_modules -o -name .venv -o -name venv \) -type d -prune -exec rm -rf {} + 2>/dev/null || true
  fi
  cd "$WORKSPACE_DIR" || return
  printf '\nWorkspace: %s\nAgent: %s\n\n' "$WORKSPACE_DIR" "$WORKBENCH_AGENT"
  printf 'Run:\n  start-herdr\n\n'
  printf 'Exit cleanly:\n'
  printf '  1. Exit the coding agent with /exit or Ctrl+D.\n'
  printf '  2. Press Ctrl+B, release, then press q to exit Herdr.\n'
  printf '  3. Run exit to close the AgentCore shell.\n\n'
else
  echo "No workbench session is configured. Launch it with ./bin/workbench aws."
fi
