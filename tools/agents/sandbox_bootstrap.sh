#!/bin/bash

find_user_owned_home_dir() {
  local dest_dir="$1" user="$2"
  local user_home home_relative_dir
  user_home="/home/$user"

  case "$dest_dir" in
    "$user_home"/*)
      home_relative_dir="${dest_dir#"$user_home"/}"
      echo "$user_home/${home_relative_dir%%/*}"
      ;;
  esac
}

install_file_into_sandbox() {
  local src="$1" dest="$2"
  local file_mode="${3:-600}" dir_mode="${4:-700}" owner="${5:-agent:agent}"
  local dest_dir user group staged user_owned_home_dir
  dest_dir="$(dirname "$dest")"
  user="${owner%:*}"
  group="${owner#*:}"
  staged="/tmp/sbx-staged-$(basename "$dest")"

  # Agent/harness tools create runtime files here (i.e. settings config such as mcp_config.json etc.), 
  # so the sandbox user must be able to write to it.
  user_owned_home_dir="$(find_user_owned_home_dir "$dest_dir" "$user")"

  sbx cp "$src" "$SANDBOX_NAME":"$staged"
  sbx exec "$SANDBOX_NAME" bash -c "
set -euo pipefail
# Keep the tool's runtime directory writable by the sandbox user.
if [ -n '$user_owned_home_dir' ]; then
  sudo install -d -m $dir_mode -o $user -g $group '$user_owned_home_dir'
fi
# Create the copied file's parent directory with private, user-owned permissions.
sudo install -d -m $dir_mode -o $user -g $group '$dest_dir'
# Copy the staged file with its required permissions and ownership.
sudo install -m $file_mode -o $user -g $group '$staged' '$dest'
# Remove the temporary file from the sandbox.
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

allow_skills_marketplace_network() {
  sbx policy allow network --sandbox "$SANDBOX_NAME" add-skill.vercel.sh:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" github.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" api.github.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" codeload.github.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" registry.npmjs.org:443
}

# Agent slugs come from the Supported Agents table in vercel-labs/skills, which
# decides where each agent reads its skills from.
install_matt_pocock_skills() {
  local workspace_dir="$1"
  shift

  local agent_flags=()
  local agent_slug
  for agent_slug in "$@"; do
    agent_flags+=(--agent "$agent_slug")
  done

  echo "Installing Matt Pocock skills for: $*"

  if ! sbx exec "$SANDBOX_NAME" bash -lc "
set -euo pipefail
cd '$workspace_dir'

npx --yes skills@1.5.20 add mattpocock/skills \
  ${agent_flags[*]} \
  --skill '*' \
  --global \
  --yes \
  --copy
"; then
    echo "WARN: Could not install Matt Pocock skills for: $*" >&2
  fi
}

install_skill_creator() {
  local workspace_dir="$1"
  shift

  local agent_flags=()
  local agent_slug
  for agent_slug in "$@"; do
    agent_flags+=(--agent "$agent_slug")
  done

  echo "Installing skill-creator for: $*"

  if ! sbx exec "$SANDBOX_NAME" bash -lc "
set -euo pipefail
cd '$workspace_dir'

npx --yes skills@1.5.20 add anthropics/skills \
  --skill skill-creator \
  ${agent_flags[*]} \
  --global \
  --yes \
  --copy
"; then
    echo "WARN: Could not install skill-creator for: $*" >&2
  fi
}

install_no_mistakes() {
  local workspace_dir="$1"
  shift

  local agent_flags=()
  local agent_slug
  for agent_slug in "$@"; do
    agent_flags+=(--agent "$agent_slug")
  done

  echo "Installing no-mistakes for: $*"

  if ! sbx exec "$SANDBOX_NAME" bash -lc "
set -euo pipefail
cd '$workspace_dir'

npx --yes skills@1.5.20 add kunchenguid/no-mistakes \
  --skill no-mistakes \
  ${agent_flags[*]} \
  --global \
  --yes \
  --copy
"; then
    echo "WARN: Could not install no-mistakes for: $*" >&2
  fi
}

# gh-axi and npm-axi give agents compact GitHub and npm registry output. gh-axi
# shells out to gh, so the gh binary goes in first. The EC2 box authenticates gh
# from its GitHub App token relay, which does not exist here, so the sandbox
# needs `gh auth login` once. The sandbox keeps that login until it is deleted.
install_github_tools() {
  local workspace_dir="$1"
  shift

  local agent_flags=()
  local agent_slug
  for agent_slug in "$@"; do
    agent_flags+=(--agent "$agent_slug")
  done

  echo "Installing gh, gh-axi, and npm-axi for: $*"

  # gh downloads its release from GitHub and `gh auth login` talks to the API,
  # so open those hosts here instead of trusting each launcher to do it.
  allow_skills_marketplace_network
  sbx policy allow network --sandbox "$SANDBOX_NAME" objects.githubusercontent.com:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" release-assets.githubusercontent.com:443

  sbx exec "$SANDBOX_NAME" bash -lc '
set -euo pipefail
source /etc/sandbox-persistent.sh 2>/dev/null || true

gh_version=2.97.0

if ! gh --version 2>/dev/null | grep -q "gh version $gh_version"; then
  case "$(uname -m)" in
    aarch64|arm64) gh_arch="arm64" ;;
    x86_64|amd64) gh_arch="amd64" ;;
    *)
      echo "ERROR: Unsupported architecture for gh: $(uname -m)" >&2
      exit 1
      ;;
  esac

  gh_tmp="$(mktemp -d)"
  gh_release="gh_${gh_version}_linux_${gh_arch}"
  curl -fsSL "https://github.com/cli/cli/releases/download/v${gh_version}/${gh_release}.tar.gz" \
    -o "$gh_tmp/gh.tar.gz"
  tar -xzf "$gh_tmp/gh.tar.gz" -C "$gh_tmp"
  sudo install -m 755 "$gh_tmp/$gh_release/bin/gh" /usr/local/bin/gh
  rm -rf "$gh_tmp"
fi

npm install -g --ignore-scripts gh-axi@0.1.29 npm-axi@0.1.1

gh --version
gh-axi --version
npm-axi --version
'

  if ! sbx exec "$SANDBOX_NAME" bash -lc "
set -euo pipefail
cd '$workspace_dir'

npx --yes skills@1.5.20 add kunchenguid/gh-axi \
  --skill gh-axi \
  ${agent_flags[*]} \
  --global \
  --yes \
  --copy

npx --yes skills@1.5.20 add SSBrouhard/npm-axi \
  --skill npm-axi \
  ${agent_flags[*]} \
  --global \
  --yes \
  --copy
"; then
    echo "WARN: Could not install the gh-axi or npm-axi skills for: $*" >&2
  fi

  sbx exec "$SANDBOX_NAME" bash -lc '
set -euo pipefail
source /etc/sandbox-persistent.sh 2>/dev/null || true

gh-axi setup hooks </dev/null || echo "WARN: Could not set up gh-axi session hooks." >&2
npm-axi setup hooks </dev/null || echo "WARN: Could not set up npm-axi session hooks." >&2

# Every launcher shares this reminder, and it stops showing after the login.
cat > "$HOME/.gh-login-reminder.sh" <<'"'"'REMINDER'"'"'
if ! gh auth status >/dev/null 2>&1; then
  printf "\ngh has no GitHub login. gh, gh-axi, and no-mistakes need one.\nRun once in this sandbox: gh auth login\nChoose HTTPS, not SSH. HTTPS shares one token with git and adds no key to your account.\n\n"
fi
REMINDER

if ! grep ".gh-login-reminder.sh" "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<'"'"'HOOK'"'"'

if [ -t 1 ] && [ -f "$HOME/.gh-login-reminder.sh" ]; then
  bash "$HOME/.gh-login-reminder.sh"
fi
HOOK
fi

bash "$HOME/.gh-login-reminder.sh"
'
}

# The skills repo doubles as a Claude Code plugin marketplace, so Claude gets the
# plugin rather than files copied into its skills directory.
install_matt_pocock_skills_plugin() {
  echo "Installing the Matt Pocock skills plugin for Claude Code..."

  sbx exec "$SANDBOX_NAME" bash -lc '
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"

if claude plugin list 2>/dev/null | grep -q mattpocock-skills; then
  echo "Matt Pocock skills plugin already installed."
else
  claude plugin marketplace add mattpocock/skills </dev/null >/dev/null 2>&1 || true
  claude plugin install mattpocock-skills@mattpocock </dev/null >/dev/null 2>&1 || true
fi

if ! claude plugin list 2>/dev/null | grep -q mattpocock-skills; then
  echo "WARN: The Matt Pocock skills plugin did not install for Claude Code." >&2
fi
'
}

# Codex discovers user skills from ~/.agents/skills. Global Codex installs still
# land in ~/.codex/skills, so link those folders for discovery.
link_codex_skills_for_discovery() {
  echo "Linking Codex skills into ~/.agents/skills for discovery..."

  sbx exec "$SANDBOX_NAME" bash -lc '
set -euo pipefail

mkdir -p "$HOME/.agents/skills"
for skill_dir in "$HOME/.codex/skills"/*; do
  [ -d "$skill_dir" ] || continue
  skill_name="$(basename "$skill_dir")"
  case "$skill_name" in
    .system) continue ;;
  esac
  ln -sfn "$skill_dir" "$HOME/.agents/skills/$skill_name"
done
'
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
export DISABLE_AUTOUPDATER=1
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
