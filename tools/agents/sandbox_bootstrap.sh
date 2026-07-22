#!/bin/bash

install_file_into_sandbox() {
  local src="$1" dest="$2"
  local file_mode="${3:-600}" dir_mode="${4:-700}" owner="${5:-agent:agent}"
  local dest_dir user group staged
  dest_dir="$(dirname "$dest")"
  user="${owner%:*}"
  group="${owner#*:}"
  staged="/tmp/sbx-staged-$(basename "$dest")"

  sbx cp "$src" "$SANDBOX_NAME":"$staged"
  sbx exec "$SANDBOX_NAME" bash -c "
set -euo pipefail
[ -d '$dest_dir' ] || sudo install -d -m $dir_mode -o $user -g $group '$dest_dir'
sudo install -m $file_mode -o $user -g $group '$staged' '$dest'
sudo rm -f '$staged'
"
}

allow_system_update_network() {
  sbx policy allow network --sandbox "$SANDBOX_NAME" debian.org:443

  sbx policy allow network --sandbox "$SANDBOX_NAME" ports.ubuntu.com:80
  sbx policy allow network --sandbox "$SANDBOX_NAME" ports.ubuntu.com:443

  sbx policy allow network --sandbox "$SANDBOX_NAME" deb.debian.org:80
  sbx policy allow network --sandbox "$SANDBOX_NAME" deb.debian.org:443

  sbx policy allow network --sandbox "$SANDBOX_NAME" archive.ubuntu.com:80
  sbx policy allow network --sandbox "$SANDBOX_NAME" archive.ubuntu.com:443

  sbx policy allow network --sandbox "$SANDBOX_NAME" security.ubuntu.com:80
  sbx policy allow network --sandbox "$SANDBOX_NAME" security.ubuntu.com:443

  sbx policy allow network --sandbox "$SANDBOX_NAME" astral.sh:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" github.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" objects.githubusercontent.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" release-assets.githubusercontent.com:443

  sbx policy allow network --sandbox "$SANDBOX_NAME" download.docker.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" files.pythonhosted.org:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" pypi.org:443
}

allow_vendor_docs_network() {
  sbx policy allow network --sandbox "$SANDBOX_NAME" docs.claude.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" code.claude.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" docs.anthropic.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" developers.openai.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" opencode.ai:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" docs.cline.bot:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" cursor.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" json.schemastore.org:443
}

allow_exa_mcp_network() {
  sbx policy allow network --sandbox "$SANDBOX_NAME" mcp.exa.ai:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" auth.exa.ai:443
}

allow_serena_mcp_network() {
  sbx policy allow network --sandbox "$SANDBOX_NAME" github.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" api.github.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" objects.githubusercontent.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" pypi.org:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" files.pythonhosted.org:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" astral.sh:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" uv.sh:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" oraios-software.de:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" release-assets.githubusercontent.com:443
}

configure_sandbox_env() {
  echo "Configuring privacy/telemetry environment inside sandbox..."

  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail

sudo tee /etc/sandbox-persistent.sh >/dev/null <<\EOF
export DO_NOT_TRACK=1
export SBX_NO_TELEMETRY=1
export DISABLE_TELEMETRY=1
export DISABLE_ERROR_REPORTING=1
export DISABLE_FEEDBACK_COMMAND=1
export CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY=1
export GEMINI_TELEMETRY_ENABLED=false
export GEMINI_TELEMETRY_TRACES_ENABLED=false
export GEMINI_TELEMETRY_LOG_PROMPTS=false
export OPENCODE_DISABLE_SHARE=1
export OPENCODE_AUTO_SHARE=false
export TERM=xterm-256color
export NPM_CONFIG_PREFIX="$HOME/.local/npm"
export PATH="$HOME/.local/bin:$HOME/.local/npm/bin:$PATH"

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

for rcfile in "$HOME/.bashrc" "$HOME/.profile"; do
  if [ -f "$rcfile" ]; then
    if ! grep "source /etc/sandbox-persistent.sh" "$rcfile"; then
      echo "source /etc/sandbox-persistent.sh" >> "$rcfile"
    fi
  fi
done
'

}

install_bash_sandbox_runtime() {
  echo "Installing bubblewrap so the Claude Code Bash sandbox can start..."

  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail

if ! command -v bwrap >/dev/null 2>&1 || ! command -v socat >/dev/null 2>&1; then
  while sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    echo "Waiting for apt lock..."
    sleep 2
  done

  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    bubblewrap socat
fi

bwrap --version
command -v socat

if ! bwrap --ro-bind / / --dev /dev true 2>/dev/null; then
  echo "ERROR: bubblewrap is installed but cannot create a sandbox here." >&2
  echo "Unprivileged user namespaces are probably disabled on the host." >&2
  echo "Claude Code will refuse to start until this is fixed." >&2
  exit 1
fi

echo "Bubblewrap sandbox verified."
'
}

install_node_lts() {
  echo "Installing Node LTS..."
  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail

case "$(uname -m)" in
  aarch64|arm64)
    node_arch="arm64"
    ;;
  x86_64|amd64)
    node_arch="x64"
    ;;
  *)
    echo "ERROR: Unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

curl -fsSL "https://nodejs.org/dist/v24.9.0/node-v24.9.0-linux-${node_arch}.tar.gz" |
  sudo tar -xz -C /usr/local --strip-components=1
'
}

# upgrade_system_packages() {
#   sbx exec "$SANDBOX_NAME" bash -c "sudo apt update && sudo apt upgrade -y"
# }

upgrade_system_packages() {
  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail

while sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
  echo "Waiting for apt lock..."
  sleep 2
done

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
'
}

allow_gemini_access() {
  sbx policy allow network --sandbox "$SANDBOX_NAME" generativelanguage.googleapis.com:443
}
