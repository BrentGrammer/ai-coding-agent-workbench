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
  mkdir -p "$CODEX_SQLITE_HOME"
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
