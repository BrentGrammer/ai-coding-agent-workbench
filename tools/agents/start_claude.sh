#!/usr/bin/env bash
set -euo pipefail

PREFIX_NAME="claude"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
configureLocalWorkspace "$@"
REPO_ROOT="$WORKSPACE_ROOT_DIR"
REPO_REPLACE_UNDERSCORES="$SANDBOX_WORKSPACE_NAME"
SANDBOX_NAME="$PREFIX_NAME-$REPO_REPLACE_UNDERSCORES"
START_DOCKER="$WORKBENCH_ROOT/tools/scripts/start_docker.sh"

source "$SCRIPT_DIR/sandbox_bootstrap.sh"

echo "Using sandbox name: $SANDBOX_NAME"

bash "$START_DOCKER"

openLocalWorkspace

allow_network() {
  allow_system_update_network
  
  sbx policy allow network --sandbox "$SANDBOX_NAME" claude.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" downloads.claude.ai:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" api.anthropic.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" console.anthropic.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" claude.ai:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" platform.claude.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" downloads.claude.ai:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" storage.googleapis.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" challenges.cloudflare.com:443
  
  sbx policy allow network --sandbox "$SANDBOX_NAME" raw.githubusercontent.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" github.com:443

  sbx policy allow network --sandbox "$SANDBOX_NAME" registry.npmjs.org:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" nodejs.org:443
}

get_anthropic_api_key() {
  if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    printf '%s' "$ANTHROPIC_API_KEY"
    return 0
  fi

  if command -v sbx >/dev/null 2>&1; then
    sbx secret get ANTHROPIC_API_KEY 2>/dev/null || true
  fi
}

configure_claude_env() {
  echo "Configuring Claude Code-specific env..."

  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail

PERSISTENT_ENV="/etc/sandbox-persistent.sh"

sudo touch "$PERSISTENT_ENV"
sudo sed -i "/^export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1$/d" "$PERSISTENT_ENV"
'
}

install_or_update() {
  echo "Installing/updating Claude Code..."

  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail

source /etc/sandbox-persistent.sh 2>/dev/null || true
export PATH="$HOME/.local/bin:$PATH"

if command -v claude >/dev/null 2>&1; then
  claude update || true
else
  curl -fsSL https://claude.ai/install.sh | bash
fi

if ! grep "HOME/.local/bin" "$HOME/.bashrc" 2>/dev/null; then
  echo '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> "$HOME/.bashrc"
fi

claude --version
'
}

copy_config() {
  local claude_config_dir="$WORKBENCH_ROOT/.claude"

  if [ ! -d "$claude_config_dir" ]; then
    echo "WARN: No workbench Claude config at $claude_config_dir" >&2
    return
  fi

  echo "Copying workbench Claude Code config/settings into sandbox home..."
  sbx exec "$SANDBOX_NAME" bash -c "mkdir -p /home/agent/.claude"
  sbx cp "$claude_config_dir/." "$SANDBOX_NAME":/home/agent/.claude/
  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail
sudo chown -R agent:agent /home/agent/.claude
python3 - <<PY
import json
from pathlib import Path
path = Path("/home/agent/.claude/settings.local.json")
if not path.is_file():
    raise SystemExit(0)
data = json.loads(path.read_text())
sandbox = data.get("sandbox")
if isinstance(sandbox, dict):
    sandbox["enabled"] = False
    sandbox.pop("failIfUnavailable", None)
    data["sandbox"] = sandbox
    path.write_text(json.dumps(data, indent=2) + "\n")
PY
'
}

usage_instructions() {
  sbx exec "$SANDBOX_NAME" bash -c '
cat > "$HOME/.claude-code-welcome.sh" <<EOF
cat <<MSG

✅ sandbox is ready: '"$SANDBOX_NAME"'

Run Claude Code:

  claude

Bypass all permissions:

  claude --permission-mode bypassPermissions

Allow switching to bypass mode with Shift+Tab:

  claude --allow-dangerously-skip-permissions

Run Claude Code with Fable:

  claude --model fable

In Claude, log in with your Claude subscription:

  /login

If the browser cannot reach this sandbox, press c to copy the URL,
sign in on the host, then paste the code back into the terminal.
Note: Make sure ANTHROPIC_API_KEY is unset, or it overrides subscription auth.

MSG
EOF

if ! grep ".claude-code-welcome.sh" "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<EOF

if [ -t 1 ] && [ -f "\$HOME/.claude-code-welcome.sh" ]; then
  bash "\$HOME/.claude-code-welcome.sh"
fi
EOF
fi
'
}

if sandboxExists "$SANDBOX_NAME"; then
  echo "✅ Existing sandbox found: $SANDBOX_NAME"
  echo "Reconnecting..."

  allow_network
  configure_sandbox_env
  configure_claude_env
  install_or_update
  copy_config
  usage_instructions

  sbx run "$SANDBOX_NAME"
else
  echo "🆕 Creating new sandbox: $SANDBOX_NAME"

  sbx create shell "$REPO_ROOT" --name "$SANDBOX_NAME"

  allow_network
  upgrade_system_packages
  install_node_lts
  configure_sandbox_env
  configure_claude_env
  install_or_update
  copy_config
  usage_instructions

  sbx run "$SANDBOX_NAME"
fi
