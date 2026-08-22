#!/usr/bin/env bash
set -euo pipefail

export SBX_NO_TELEMETRY=1

configureLocalWorkspace() {
  local workspace_input="$PWD"
  local workspace_path_was_given=false
  SANDBOX_CLONE=false
  # This file is not on this tree, so the source is skipped.
  # optional_skills_and_tools.sh exists only on the optional-skills-tools branch.
  if [ -f "$SCRIPT_DIR/optional_skills_and_tools.sh" ]; then
    source "$SCRIPT_DIR/optional_skills_and_tools.sh"
  fi

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --clone)
        SANDBOX_CLONE=true
        ;;
      --*)
        # Function is missing on this tree, so unknown -- flags still fail.
        # It is defined in optional_skills_and_tools.sh, which this tree does not ship.
        if type turn_on_optional_skill_or_tool >/dev/null 2>&1 && turn_on_optional_skill_or_tool "$1"; then
          :
        else
          echo "Unknown option: $1" >&2
          return 1
        fi
        ;;
      *)
        if [ "$workspace_path_was_given" = true ]; then
          local optional_skill_and_tool_flags=""
          # Function is missing on this tree, so usage stays [--clone] only.
          # It is defined in optional_skills_and_tools.sh, which this tree does not ship.
          if type optional_skill_and_tool_flags_for_usage >/dev/null 2>&1; then
            optional_skill_and_tool_flags="$(optional_skill_and_tool_flags_for_usage)"
          fi
          echo "Usage: $0 [--clone]${optional_skill_and_tool_flags} [WORKSPACE_PATH]" >&2
          return 1
        fi
        workspace_input="$1"
        workspace_path_was_given=true
        ;;
    esac
    shift
  done
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
  readable_workspace_name="${readable_workspace_name:-workspace}"

  local workspace_path_hash
  workspace_path_hash="$(printf '%s' "$WORKSPACE_ROOT_DIR" | shasum -a 256 | cut -c1-8)"
  SANDBOX_WORKSPACE_NAME="$readable_workspace_name-$workspace_path_hash"
  if [ "$SANDBOX_CLONE" = true ]; then
    SANDBOX_WORKSPACE_NAME="$SANDBOX_WORKSPACE_NAME-clone"
  fi
  # Function is missing on this tree, so this call is skipped.
  # It is defined in optional_skills_and_tools.sh, which this tree does not ship.
  if type remember_if_any_skill_or_gh_tool_is_on >/dev/null 2>&1; then
    remember_if_any_skill_or_gh_tool_is_on
  fi
}

sandboxExists() {
  local sandbox_name="$1"
  sbx ls 2>/dev/null | awk '{print $1}' | grep -Fxq -- "$sandbox_name"
}

createWorkbenchSandbox() {
  local workspace_dir="$1"
  local sandbox_name="$2"
  if [ "$SANDBOX_CLONE" != true ]; then
    sbx create shell "$workspace_dir" --name "$sandbox_name"
    return
  fi

  if ! git -C "$workspace_dir" rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: --clone needs a Git repository." >&2
    return 1
  fi

  sbx create shell "$workspace_dir" --name "$sandbox_name" --clone
}

runSandboxHarness() {
  local allow_network_function="$1"
  local install_harness_function="$2"
  local needs_node="${3:-false}"
  local harness_command="$4"

  bash "$WORKBENCH_ROOT/tools/scripts/start_docker.sh"
  if ! sandboxExists "$SANDBOX_NAME"; then
    createWorkbenchSandbox "$WORKSPACE_ROOT_DIR" "$SANDBOX_NAME"
    "$allow_network_function"
    if [ "$needs_node" = "true" ]; then
      install_node_lts
    fi
  fi

  "$allow_network_function"
  "$install_harness_function"
  # Function is missing on this tree, so this call is skipped.
  # It is defined in optional_skills_and_tools.sh, which this tree does not ship.
  if type install_selected_skills_and_tools >/dev/null 2>&1; then
    install_selected_skills_and_tools
  fi
  sbx exec -it -w "$WORKSPACE_ROOT_DIR" "$SANDBOX_NAME" \
    bash -lc "export PATH=\"\$HOME/.local/bin:\$HOME/.local/npm/bin:\$HOME/.grok/bin:\$HOME/.antigravity/bin:\$PATH\"; exec $harness_command"
}
