#!/usr/bin/env bash
set -euo pipefail

PREFIX_NAME="kilo"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_workspace.sh"
configureLocalWorkspace "$@"
REPO_ROOT="$WORKSPACE_ROOT_DIR"
REPO_REPLACE_UNDERSCORES="$SANDBOX_WORKSPACE_NAME"
SANDBOX_NAME="$PREFIX_NAME-$REPO_REPLACE_UNDERSCORES"
START_DOCKER="$WORKBENCH_ROOT/tools/scripts/start_docker.sh"

source "$SCRIPT_DIR/sandbox_bootstrap.sh"

echo "Using sandbox name: $SANDBOX_NAME"

chmod +x "$START_DOCKER"
"$START_DOCKER"

openLocalWorkspace

allow_network() {
  allow_system_update_network

  sbx policy allow network --sandbox "$SANDBOX_NAME" kilo.ai:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" app.kilo.ai:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" api.kilo.ai:443

  sbx policy allow network --sandbox "$SANDBOX_NAME" registry.npmjs.org:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" nodejs.org:443

  # Common BYOK/provider targets Kilo may need after /connect.
  sbx policy allow network --sandbox "$SANDBOX_NAME" api.openai.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" platform.openai.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" api.anthropic.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" console.anthropic.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" openrouter.ai:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" api.openrouter.ai:443
}

configure_kilo_env() {
  echo "Configuring Kilo Code-specific env..."

  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail

PERSISTENT_ENV="/etc/sandbox-persistent.sh"

sudo touch "$PERSISTENT_ENV"
sudo sed -i "/^export NPM_CONFIG_PREFIX=/d" "$PERSISTENT_ENV"
sudo tee -a "$PERSISTENT_ENV" >/dev/null <<EOF
export NPM_CONFIG_PREFIX="\$HOME/.local"
EOF
'
}

install_or_update() {
  echo "Installing/updating Kilo Code CLI..."

  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail

source /etc/sandbox-persistent.sh 2>/dev/null || true
export PATH="$HOME/.local/bin:$PATH"
export NPM_CONFIG_PREFIX="${NPM_CONFIG_PREFIX:-$HOME/.local}"

mkdir -p "$HOME/.local/bin" "$HOME/.local/lib"

npm install -g @kilocode/cli --ignore-scripts

if ! grep "HOME/.local/bin" "$HOME/.bashrc" 2>/dev/null; then
  echo '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> "$HOME/.bashrc"
fi
'
}

copy_config() {
  # Kilo project config is usually ./kilo.jsonc or ./.kilo/kilo.jsonc.
  # .kilo takes priority if both exist. Global config lives at ~/.config/kilo/kilo.jsonc.
  # Source: Kilo settings docs.
  local kilo_config_dir="$WORKBENCH_ROOT/.kilo"
  local kilo_config_file="$WORKBENCH_ROOT/kilo.jsonc"

  if [ -d "$kilo_config_dir" ]; then
    echo "Copying workbench Kilo config into sandbox home..."
    sbx exec "$SANDBOX_NAME" bash -c "mkdir -p /home/agent/.config/kilo"
    sbx cp "$kilo_config_dir/." "$SANDBOX_NAME":/home/agent/.config/kilo/
  fi

  if [ -f "$kilo_config_file" ]; then
    echo "Copying workbench kilo.jsonc into sandbox home..."
    sbx exec "$SANDBOX_NAME" bash -c "mkdir -p /home/agent/.config/kilo"
    sbx cp "$kilo_config_file" "$SANDBOX_NAME":/home/agent/.config/kilo/kilo.jsonc
  fi
}

usage_instructions() {
  sbx exec "$SANDBOX_NAME" bash -c '
cat > "$HOME/.kilo-code-welcome.sh" <<EOF
cat <<MSG

✅ sandbox is ready: '"$SANDBOX_NAME"'

Run Kilo Code CLI:

  kilo

First-time provider setup:

  kilo
  /connect

Or use CLI auth:

  kilo auth login

Helpful commands:

  kilo --help
  kilo auth list
  kilo models
  kilo config check
  kilo debug paths

MSG
EOF

if ! grep -q ".kilo-code-welcome.sh" "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<EOF

if [ -t 1 ] && [ -f "\$HOME/.kilo-code-welcome.sh" ]; then
  bash "\$HOME/.kilo-code-welcome.sh"
fi
EOF
fi
'
}

if sbx ls | grep "$SANDBOX_NAME"; then
  echo "✅ Existing sandbox found: $SANDBOX_NAME"
  echo "Reconnecting..."

  allow_network
  configure_sandbox_env
  configure_kilo_env
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
  configure_kilo_env
  install_or_update
  copy_config
  usage_instructions

  sbx run "$SANDBOX_NAME"
fi
