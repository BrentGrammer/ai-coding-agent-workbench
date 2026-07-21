#!/bin/bash

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
export OPENCODE_CONFIG_CONTENT='{"share":"disabled"}'
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
