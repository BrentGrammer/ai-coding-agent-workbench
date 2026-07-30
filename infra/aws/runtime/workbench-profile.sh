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

  HERDR_SESSION_DIR="/tmp/agent-workbench/herdr-$WORKBENCH_SESSION/config/herdr"
  HERDR_LIVE_SOCKET="$(find "$HERDR_SESSION_DIR" -type s -name '*.sock' 2>/dev/null | head -n 1)"

  if [ -n "$HERDR_LIVE_SOCKET" ] && [ -z "${HERDR_WORKSPACE_ID:-}" ] &&
    [ -z "${WORKBENCH_SKIP_HERDR:-}" ]; then
    printf '\nHerdr is still running here. Reattaching to your panes...\n'
    printf 'Set WORKBENCH_SKIP_HERDR=1 for a plain shell instead.\n\n'
    start-herdr
  fi

  printf '\nWorkspace: %s\nAgent: %s\n\n' "$WORKSPACE_DIR" "$WORKBENCH_AGENT"
  printf 'Run /setup-matt-pocock-skills once per repo, if you have not already.\n\n'
  printf 'gh is wrapped to mint a fresh token per call - no gh auth login needed.\n\n'
  printf 'Run:\n  start-herdr\n\n'
  printf 'Herdr keeps your panes and agent in a background server, so they survive a\n'
  printf 'dropped shell. Reattaching runs start-herdr for you.\n\n'
  printf 'Finish up:\n'
  printf '  1. Exit the coding agent with /exit or Ctrl+D.\n'
  printf '  2. Press Ctrl+B, release, then press q to detach from Herdr.\n'
  printf '  3. Run exit to close the AgentCore shell. A countdown appears on your own\n'
  printf '     machine: press s to stop the session and end its billing, or l to leave\n'
  printf '     it running. Doing nothing reconnects you here.\n\n'
else
  echo "No workbench session is configured. Launch it with ./bin/workbench aws."
fi
