#!/usr/bin/env bash
set -euo pipefail

install_file_into_sandbox() {
  local source_file="$1"
  local target_file="$2"
  local file_mode="${3:-600}"
  local directory_mode="${4:-700}"
  local owner="${5:-agent:agent}"
  local staged_file="/tmp/sbx-staged-$(basename "$target_file")"

  sbx cp "$source_file" "$SANDBOX_NAME:$staged_file"
  sbx exec "$SANDBOX_NAME" bash -c "
set -euo pipefail
sudo install -d -m $directory_mode -o ${owner%:*} -g ${owner#*:} '$(dirname "$target_file")'
sudo install -m $file_mode -o ${owner%:*} -g ${owner#*:} '$staged_file' '$target_file'
sudo rm -f '$staged_file'
"
}

allow_system_update_network() {
  local host
  for host in \
    debian.org:443 \
    ports.ubuntu.com:80 \
    ports.ubuntu.com:443 \
    deb.debian.org:80 \
    deb.debian.org:443 \
    archive.ubuntu.com:80 \
    archive.ubuntu.com:443 \
    security.ubuntu.com:80 \
    security.ubuntu.com:443 \
    nodejs.org:443 \
    registry.npmjs.org:443
  do
    sbx policy allow network --sandbox "$SANDBOX_NAME" "$host"
  done
}

allow_standard_model_network() {
  local host
  for host in \
    api.openai.com:443 \
    api.anthropic.com:443 \
    generativelanguage.googleapis.com:443 \
    openrouter.ai:443 \
    api.openrouter.ai:443
  do
    sbx policy allow network --sandbox "$SANDBOX_NAME" "$host"
  done
}

install_bash_sandbox_runtime() {
  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail
if ! command -v bwrap >/dev/null 2>&1 || ! command -v socat >/dev/null 2>&1; then
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    bubblewrap socat
fi
if ! bwrap --ro-bind / / --dev /dev true 2>/dev/null; then
  echo "ERROR: The Claude Code Bash sandbox cannot start." >&2
  exit 1
fi
'
}

install_node_lts() {
  sbx exec "$SANDBOX_NAME" bash -c '
set -euo pipefail
case "$(uname -m)" in
  aarch64|arm64) node_arch="arm64" ;;
  x86_64|amd64) node_arch="x64" ;;
  *) echo "ERROR: Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
curl -fsSL "https://nodejs.org/dist/v24.9.0/node-v24.9.0-linux-${node_arch}.tar.gz" |
  sudo tar -xz -C /usr/local --strip-components=1
'
}
