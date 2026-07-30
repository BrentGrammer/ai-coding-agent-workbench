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
  local readable_workspace_name
  readable_workspace_name="$(
    printf '%s' "$WORKSPACE_NAME" |
      tr '[:upper:]_' '[:lower:]-' |
      tr -cs '[:alnum:]-' '-' |
      sed 's/^-//; s/-$//'
  )"

  if [ -z "$readable_workspace_name" ]; then
    readable_workspace_name="workspace"
  fi
  # prevent collisions - add hash to end of folder name
  local workspace_path_hash
  workspace_path_hash="$(printf '%s' "$WORKSPACE_ROOT_DIR" | shasum -a 256 | cut -c1-8)"
  WORKSPACE_PATH_HASH="$workspace_path_hash"
  SANDBOX_WORKSPACE_NAME="$readable_workspace_name-$workspace_path_hash"

  openPreferredTerminal "$@"
}

copyMissingProjectInstructions() {
  local ask_again="${1:-false}"
  local instruction_files=(AGENTS.md CLAUDE.md)
  local missing_instruction_files=()
  local instruction_file

  for instruction_file in "${instruction_files[@]}"; do
    if [ ! -e "$WORKSPACE_ROOT_DIR/$instruction_file" ] && [ ! -L "$WORKSPACE_ROOT_DIR/$instruction_file" ]; then
      missing_instruction_files+=("$instruction_file")
    fi
  done

  if [ "${#missing_instruction_files[@]}" -eq 0 ]; then
    return
  fi

  local instruction_copy_directory="$HOME/.local/state/agent-workbench/instruction-copy"
  local instruction_copy_file="$instruction_copy_directory/$WORKSPACE_PATH_HASH"
  local instruction_choice=""

  if [ "$ask_again" != "true" ] && [ -f "$instruction_copy_file" ]; then
    local saved_workspace_path
    local saved_instruction_choice
    saved_workspace_path="$(sed -n '1p' "$instruction_copy_file")"
    saved_instruction_choice="$(sed -n '2p' "$instruction_copy_file")"

    if [ "$saved_workspace_path" = "$WORKSPACE_ROOT_DIR" ]; then
      case "$saved_instruction_choice" in
        copy|skip)
          instruction_choice="$saved_instruction_choice"
          ;;
      esac
    fi
  fi

  local remember_choice="false"
  if [ -z "$instruction_choice" ]; then
    echo "Missing project instruction files: ${missing_instruction_files[*]}"
    echo "1. Copy the missing files once."
    echo "2. Copy the missing files and remember this choice."
    echo "3. Do not copy the files this time."
    echo "4. Do not copy the files and remember this choice."

    local selected_choice
    while true; do
      if ! read -r -p "Choose 1, 2, 3, or 4: " selected_choice; then
        echo "No project instruction files were copied."
        return
      fi

      case "$selected_choice" in
        1)
          instruction_choice="copy"
          break
          ;;
        2)
          instruction_choice="copy"
          remember_choice="true"
          break
          ;;
        3)
          instruction_choice="skip"
          break
          ;;
        4)
          instruction_choice="skip"
          remember_choice="true"
          break
          ;;
        *)
          echo "Enter 1, 2, 3, or 4."
          ;;
      esac
    done
  fi

  if [ "$remember_choice" = "true" ]; then
    mkdir -p "$instruction_copy_directory"
    printf '%s\n%s\n' "$WORKSPACE_ROOT_DIR" "$instruction_choice" > "$instruction_copy_file"
  fi

  if [ "$instruction_choice" = "skip" ]; then
    echo "Project instruction files were not copied."
    return
  fi

  for instruction_file in "${missing_instruction_files[@]}"; do
    cp "$WORKBENCH_ROOT/$instruction_file" "$WORKSPACE_ROOT_DIR/$instruction_file"
  done

  echo "Copied project instruction files: ${missing_instruction_files[*]}"
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

sandboxExists() {
  local sandbox_name="$1"
  sbx ls 2>/dev/null | awk '{print $1}' | grep -Fxq -- "$sandbox_name"
}
