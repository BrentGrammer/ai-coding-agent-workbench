#!/usr/bin/env bash
set -euo pipefail

: "${REPO_URL:?REPO_URL is required}"
: "${WORKBENCH_AGENT:?WORKBENCH_AGENT is required}"
: "${WORKBENCH_SESSION:?WORKBENCH_SESSION is required}"
: "${AWS_REGION:?AWS_REGION is required}"
: "${GITHUB_APP_TOKEN_FUNCTION_NAME:?GITHUB_APP_TOKEN_FUNCTION_NAME is required}"

REPO_REF="${REPO_REF:-}"

case "$WORKBENCH_AGENT" in
  codex|claude|opencode|cursor)
    ;;
  *)
    echo "ERROR: Unsupported agent: $WORKBENCH_AGENT"
    exit 1
    ;;
esac

if ! [[ "$REPO_URL" =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(\.git)?$ ]]; then
  echo "ERROR: REPO_URL must be an HTTPS GitHub repository URL."
  exit 1
fi

if [ -n "$REPO_REF" ]; then
  git check-ref-format --branch "$REPO_REF" >/dev/null
fi

REPO_NAME="${REPO_URL##*/}"
REPO_NAME="${REPO_NAME%.git}"
PERSISTENT_ROOT="/mnt/workspace"
WORKSPACE_DIR="$PERSISTENT_ROOT/repos/$REPO_NAME"
SESSION_CONFIG_DIR="$PERSISTENT_ROOT/config"
SESSION_CONFIG_FILE="$SESSION_CONFIG_DIR/session.env"
PERSISTENT_HOME="$PERSISTENT_ROOT/home"

mkdir -p "$PERSISTENT_HOME" "$PERSISTENT_ROOT/repos" "$SESSION_CONFIG_DIR"

export HOME="$PERSISTENT_HOME"
git config --global credential.helper /usr/local/bin/git-credential-github-app
git config --global credential.useHttpPath true
git config --global --add safe.directory "$WORKSPACE_DIR"
mkdir -p "$HOME/.codex"
chmod 700 "$HOME/.codex"
install -m 600 /etc/agent-workbench/codex-config.toml "$HOME/.codex/config.toml"
install -m 600 /etc/agent-workbench/codex-hooks.json "$HOME/.codex/hooks.json"

if [ -d "$WORKSPACE_DIR/.git" ]; then
  CURRENT_REPO_URL="$(git -C "$WORKSPACE_DIR" remote get-url origin)"
  if [ "${CURRENT_REPO_URL%.git}" != "${REPO_URL%.git}" ]; then
    echo "ERROR: The saved workspace belongs to $CURRENT_REPO_URL."
    exit 1
  fi

  git -C "$WORKSPACE_DIR" fetch origin
  CURRENT_REF="$(git -C "$WORKSPACE_DIR" branch --show-current)"
  if [ -n "$REPO_REF" ] && [ "$CURRENT_REF" != "$REPO_REF" ]; then
    if [ -n "$(git -C "$WORKSPACE_DIR" status --short)" ]; then
      echo "ERROR: Commit or stash changes before switching to $REPO_REF."
      exit 1
    fi

    if git -C "$WORKSPACE_DIR" show-ref --verify --quiet "refs/remotes/origin/$REPO_REF"; then
      git -C "$WORKSPACE_DIR" checkout --track "origin/$REPO_REF"
    else
      git -C "$WORKSPACE_DIR" checkout "$REPO_REF"
    fi
  fi
else
  if [ -n "$REPO_REF" ]; then
    git clone --branch "$REPO_REF" "$REPO_URL" "$WORKSPACE_DIR"
  else
    git clone "$REPO_URL" "$WORKSPACE_DIR"
  fi
fi

REPO_REF="$(git -C "$WORKSPACE_DIR" branch --show-current)"

for agent_name in claude codex opencode cursor; do
  case "$agent_name" in
    claude)
      agent_config_dir="$HOME/.claude"
      ;;
    codex)
      agent_config_dir="$HOME/.codex"
      ;;
    opencode)
      agent_config_dir="$HOME/.config/opencode"
      ;;
    cursor)
      agent_config_dir="$HOME/.cursor"
      ;;
  esac

  mkdir -p "$agent_config_dir"
  chmod 700 "$agent_config_dir"
  herdr integration install "$agent_name"
done

hunk_skill_path="$(hunk skill path)"
for agent_skills_dir in \
  "$HOME/.claude/skills" \
  "$HOME/.codex/skills" \
  "$HOME/.config/opencode/skills" \
  "$HOME/.cursor/skills"
do
  mkdir -p "$agent_skills_dir/hunk-review"
  ln -sf "$hunk_skill_path" "$agent_skills_dir/hunk-review/SKILL.md"
done

if claude plugin list 2>/dev/null | grep -q mattpocock-skills; then
  echo "The Matt Pocock skills plugin is already installed."
else
  claude plugin marketplace add mattpocock/skills </dev/null >/dev/null 2>&1 || true
  claude plugin install mattpocock-skills@mattpocock </dev/null >/dev/null 2>&1 || true
fi

if ! claude plugin list 2>/dev/null | grep -q mattpocock-skills; then
  echo "WARN: The Matt Pocock skills plugin did not install for Claude Code." >&2
fi

# Claude uses the plugin above. Codex, OpenCode, and Cursor get skill files via the skills CLI.
echo "Installing Matt Pocock skills for Codex, OpenCode, and Cursor..."
if ! (
  cd "$WORKSPACE_DIR"
  npx --yes skills@latest add mattpocock/skills \
    --agent codex \
    --agent opencode \
    --agent cursor \
    --skill '*' \
    --global \
    --yes \
    --copy
); then
  echo "WARN: Could not install Matt Pocock skills for Codex, OpenCode, or Cursor." >&2
fi

install -m 600 /etc/agent-workbench/cursor-mcp.json "$HOME/.cursor/mcp.json"
install -m 600 /etc/agent-workbench/cursor-cli-config.json "$HOME/.cursor/cli-config.json"

# Cursor and OpenCode get Exa from their config files. Claude and Codex need an install step.
echo "Installing Exa for Claude Code..."
if claude plugin list 2>/dev/null | grep -q exa; then
  echo "Exa plugin already installed."
else
  claude plugin marketplace add anthropics/claude-plugins-official </dev/null >/dev/null 2>&1 || true
  if claude plugin install exa@claude-plugins-official </dev/null >/dev/null 2>&1; then
    echo "Installed the Exa plugin."
  elif claude mcp get exa >/dev/null 2>&1; then
    echo "Exa MCP server already registered."
  else
    echo "Plugin install did not work, falling back to the MCP server."
    claude mcp add --transport http --scope user exa https://mcp.exa.ai/mcp </dev/null >/dev/null 2>&1 || true
  fi
fi

if ! claude plugin list 2>/dev/null | grep -q exa &&
  ! claude mcp list 2>/dev/null | grep -q exa; then
  echo "WARN: Claude Code has neither the Exa plugin nor the Exa MCP server." >&2
fi

echo "Registering the Exa MCP server with Codex..."
if codex mcp get exa >/dev/null 2>&1; then
  echo "Exa MCP server already registered."
else
  timeout 20 codex mcp add exa --url https://mcp.exa.ai/mcp </dev/null >/dev/null 2>&1 || true
fi

if codex mcp get exa >/dev/null 2>&1; then
  echo "Exa MCP server ready."
else
  echo "WARN: Codex does not list the Exa MCP server." >&2
fi

if [ -n "${GIT_USER_NAME:-}" ]; then
  git -C "$WORKSPACE_DIR" config user.name "$GIT_USER_NAME"
fi

if [ -n "${GIT_USER_EMAIL:-}" ]; then
  git -C "$WORKSPACE_DIR" config user.email "$GIT_USER_EMAIL"
fi

write_shell_value() {
  printf '%q' "$1"
}

{
  printf 'export HOME=%s\n' "$(write_shell_value "$PERSISTENT_HOME")"
  printf 'export REPO_URL=%s\n' "$(write_shell_value "$REPO_URL")"
  printf 'export REPO_REF=%s\n' "$(write_shell_value "$REPO_REF")"
  printf 'export WORKSPACE_DIR=%s\n' "$(write_shell_value "$WORKSPACE_DIR")"
  printf 'export WORKBENCH_AGENT=%s\n' "$(write_shell_value "$WORKBENCH_AGENT")"
  printf 'export WORKBENCH_SESSION=%s\n' "$(write_shell_value "$WORKBENCH_SESSION")"
  printf 'export AWS_REGION=%s\n' "$(write_shell_value "$AWS_REGION")"
  printf 'export GITHUB_APP_TOKEN_FUNCTION_NAME=%s\n' "$(write_shell_value "$GITHUB_APP_TOKEN_FUNCTION_NAME")"
  printf 'export HERDR_CONFIG_PATH=/etc/agent-workbench/herdr-config.toml\n'
  printf 'export DO_NOT_TRACK=1\n'
  printf 'export DISABLE_TELEMETRY=1\n'
  printf 'export DISABLE_ERROR_REPORTING=1\n'
  printf 'export DISABLE_FEEDBACK_COMMAND=1\n'
  printf 'export CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY=1\n'
  printf 'export GEMINI_TELEMETRY_ENABLED=false\n'
  printf 'export GEMINI_TELEMETRY_TRACES_ENABLED=false\n'
  printf 'export GEMINI_TELEMETRY_LOG_PROMPTS=false\n'
  printf 'export OPENCODE_DISABLE_SHARE=1\n'
  printf 'export OPENCODE_AUTO_SHARE=false\n'
} > "$SESSION_CONFIG_FILE"

cat >> "$SESSION_CONFIG_FILE" <<'EOF'
codex() {
  command codex \
    -c analytics.enabled=false \
    -c feedback.enabled=false \
    -c 'otel.exporter="none"' \
    -c 'otel.metrics_exporter="none"' \
    -c 'otel.trace_exporter="none"' \
    -c otel.log_user_prompt=false \
    "$@"
}
export -f codex
EOF

echo "Workspace ready at $WORKSPACE_DIR."
