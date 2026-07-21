#!/usr/bin/env bash
set -euo pipefail

export SBX_NO_TELEMETRY=1

findTerminalCommand() {
  local terminal_name="$1"

  if command -v "$terminal_name" >/dev/null 2>&1; then
    command -v "$terminal_name"
    return
  fi

  case "$terminal_name" in
    ghostty)
      [ -x /Applications/Ghostty.app/Contents/MacOS/ghostty ] &&
        printf '%s\n' /Applications/Ghostty.app/Contents/MacOS/ghostty
      ;;
    wezterm)
      [ -x /Applications/WezTerm.app/Contents/MacOS/wezterm ] &&
        printf '%s\n' /Applications/WezTerm.app/Contents/MacOS/wezterm
      ;;
    kitty)
      [ -x /Applications/kitty.app/Contents/MacOS/kitty ] &&
        printf '%s\n' /Applications/kitty.app/Contents/MacOS/kitty
      ;;
    alacritty)
      [ -x /Applications/Alacritty.app/Contents/MacOS/alacritty ] &&
        printf '%s\n' /Applications/Alacritty.app/Contents/MacOS/alacritty
      ;;
  esac
}

isCurrentTerminal() {
  case "$1" in
    ghostty)
      [ "${TERM_PROGRAM:-}" = "ghostty" ] ||
        [ "${TERM_PROGRAM:-}" = "Ghostty" ]
      ;;
    wezterm)
      [ "${TERM_PROGRAM:-}" = "WezTerm" ]
      ;;
    kitty)
      [ -n "${KITTY_WINDOW_ID:-}" ]
      ;;
    alacritty)
      [ -n "${ALACRITTY_WINDOW_ID:-}" ] ||
        [ "${TERM_PROGRAM:-}" = "Alacritty" ]
      ;;
    current)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

openPreferredTerminal() {
  if [ "${WORKBENCH_TERMINAL_ACTIVE:-}" = "1" ]; then
    return
  fi

  local terminal_name="${WORKSPACE_TERMINAL:-ghostty}"
  if isCurrentTerminal "$terminal_name"; then
    return
  fi

  local terminal_command
  terminal_command="$(findTerminalCommand "$terminal_name" || true)"
  if [ -z "$terminal_command" ]; then
    if [ "$terminal_name" != "ghostty" ]; then
      echo "Terminal not found: $terminal_name. Continuing in the current terminal." >&2
    fi
    return
  fi

  local launcher_path
  launcher_path="$(cd "$(dirname "$0")" && pwd -P)/$(basename "$0")"

  case "$terminal_name" in
    ghostty)
      "$terminal_command" \
        --working-directory="$WORKSPACE_ROOT_DIR" \
        -e env WORKBENCH_TERMINAL_ACTIVE=1 "$launcher_path" "$@"
      ;;
    wezterm)
      "$terminal_command" start \
        --cwd "$WORKSPACE_ROOT_DIR" \
        -- env WORKBENCH_TERMINAL_ACTIVE=1 "$launcher_path" "$@"
      ;;
    kitty)
      "$terminal_command" \
        --directory "$WORKSPACE_ROOT_DIR" \
        env WORKBENCH_TERMINAL_ACTIVE=1 "$launcher_path" "$@"
      ;;
    alacritty)
      "$terminal_command" \
        --working-directory "$WORKSPACE_ROOT_DIR" \
        -e env WORKBENCH_TERMINAL_ACTIVE=1 "$launcher_path" "$@"
      ;;
    *)
      echo "Unsupported terminal: $terminal_name" >&2
      return 1
      ;;
  esac

  exit $?
}

# Shared setup for local agent launchers. Uses the current directory or
# optional local project path and creates a Docker sandbox name from it.
configureLocalWorkspace() {
  if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [WORKSPACE_PATH]" >&2
    return 1
  fi

  local workspace_input="${1:-${WORKSPACE_ROOT_DIR:-$PWD}}"
  if [ ! -d "$workspace_input" ]; then
    echo "ERROR: Workspace directory does not exist: $workspace_input" >&2
    return 1
  fi

  WORKBENCH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
  WORKSPACE_ROOT_DIR="$(cd "$workspace_input" && pwd -P)"
  WORKSPACE_NAME="$(basename "$WORKSPACE_ROOT_DIR")"
  SANDBOX_WORKSPACE_NAME="$(
    printf '%s' "$WORKSPACE_NAME" |
      tr '[:upper:]_' '[:lower:]-' |
      tr -cs '[:alnum:]-' '-' |
      sed 's/^-//; s/-$//'
  )"

  if [ -z "$SANDBOX_WORKSPACE_NAME" ]; then
    SANDBOX_WORKSPACE_NAME="workspace"
  fi

  openPreferredTerminal "$@"
}

openLocalWorkspace() {
  if [ "${OPEN_WORKSPACE_IN_IDE:-${OPEN_WORKSPACE_IN_VSCODE:-1}}" = "0" ]; then
    return
  fi

  local ide_command="${WORKSPACE_IDE_COMMAND:-code}"
  if ! command -v "$ide_command" >/dev/null 2>&1; then
    return
  fi

  "$ide_command" "$WORKSPACE_ROOT_DIR" || true
}
