#!/usr/bin/env bash
set -euo pipefail

export SBX_NO_TELEMETRY=1

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
