#!/usr/bin/env bash
set -euo pipefail

PREFIX_NAME="codex"

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
  allow_exa_mcp_network

  sbx policy allow network --sandbox "$SANDBOX_NAME" nodejs.org:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" registry.npmjs.org:443
  # needed for lean ctx
  sbx policy allow network --sandbox "$SANDBOX_NAME" api.github.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" github.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" raw.githubusercontent.com:443

  sbx policy allow network --sandbox "$SANDBOX_NAME" files.openai.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" chatgpt.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" api.openai.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" ab.chatgpt.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" auth.openai.com:443
}

install_or_update() {
  echo "Installing/updating Codex CLI..."

  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail

source /etc/sandbox-persistent.sh 2>/dev/null || true

if ! command -v npm >/dev/null 2>&1; then
  echo "ERROR: npm is not installed."
  exit 1
fi

sudo npm install -g @openai/codex@latest --ignore-scripts

codex --version

codex update
'
}

copy_config() {
  local codex_config="$REPO_ROOT/.codex/config.toml"

  if [ -f "$codex_config" ]; then
    echo "Syncing Codex config into sandbox..."
    CONFIG_B64="$(base64 < "$codex_config" | tr -d '\n')"

    sbx exec "$SANDBOX_NAME" bash -lc "
      set -euo pipefail
      mkdir -p /home/agent/.codex
      chmod 700 /home/agent/.codex
      rm -f /home/agent/.codex/config.toml
      printf '%s' '$CONFIG_B64' | base64 -d > /home/agent/.codex/config.toml
      chmod 600 /home/agent/.codex/config.toml
    "
  fi

  if [ -f "$REPO_ROOT/.npmrc" ]; then
    NPMRC_B64="$(base64 < "$REPO_ROOT/.npmrc" | tr -d '\n')"

    sbx exec "$SANDBOX_NAME" bash -lc "
      set -euo pipefail
      rm -f /home/agent/.npmrc
      printf '%s' '$NPMRC_B64' | base64 -d > /home/agent/.npmrc
      chmod 600 /home/agent/.npmrc
    "
  fi
}

install_skills() {
  echo "Installing Matt Pocock skills..."

  sbx exec "$SANDBOX_NAME" bash -lc "
    set -euo pipefail
    cd '$REPO_ROOT'

    npx --yes skills@latest add mattpocock/skills \
      --agent codex \
      --skill '*' \
      --global \
      --yes \
      --copy
  "
}

# install_or_update_lean_ctx() {
#   echo "Installing/updating LeanCTX..."

#   sbx exec "$SANDBOX_NAME" bash -lc '
# set -u

# echo "Installing LeanCTX package..."

# if ! command -v npm >/dev/null 2>&1; then
#   echo "WARN: npm is not installed; skipping LeanCTX."
#   exit 0
# fi

# sudo npm install -g lean-ctx-bin@latest || {
#   echo "WARN: lean-ctx-bin install failed; continuing without LeanCTX."
#   exit 0
# }

# sudo npm rebuild -g lean-ctx-bin || true

# if ! command -v lean-ctx >/dev/null 2>&1; then
#   echo "WARN: lean-ctx binary not found after install; continuing without LeanCTX."
#   exit 0
# fi

# lean-ctx --version || true
# lean-ctx doctor --fix || true

# lean-ctx init --agent codex --mode hybrid || {
#   echo "WARN: lean-ctx init failed; continuing without LeanCTX MCP integration."
#   exit 0
# }
# lean-ctx doctor || true

# echo "LeanCTX setup complete."
# '
# }

usage_instructions() {
  sbx exec "$SANDBOX_NAME" bash -c '
cat > "$HOME/.codex-welcome.sh" <<EOF
cat <<MSG

✅ sandbox is ready: '"$SANDBOX_NAME"'

Run Codex:

  codex

Update codex:

  codex update

Use Skills in Codex:
  
  Inside Codex type: /skills
  Select setup-matt-pocock-skills and run it.

MSG
EOF

if ! grep ".codex-welcome.sh" "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<EOF

if [ -t 1 ] && [ -f "\$HOME/.codex-welcome.sh" ]; then
  bash "\$HOME/.codex-welcome.sh"
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
  install_or_update
  copy_config
  install_skills
  # install_or_update_lean_ctx
  usage_instructions

  sbx run "$SANDBOX_NAME"
else
  echo "🆕 Creating new sandbox: $SANDBOX_NAME"

  sbx create shell "$REPO_ROOT" --name "$SANDBOX_NAME"

  allow_network
  upgrade_system_packages
  install_node_lts
  configure_sandbox_env
  install_or_update
  copy_config
  install_skills
  # install_or_update_lean_ctx
  usage_instructions

  sbx run "$SANDBOX_NAME"
fi
