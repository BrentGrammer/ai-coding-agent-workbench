# Optional skills and tools. Present only on the optional-skills-tools branch.
# Thin main sources this file when it exists.

INSTALL_MATT_POCOCK_SKILLS="${INSTALL_MATT_POCOCK_SKILLS:-false}"
INSTALL_SKILL_CREATOR="${INSTALL_SKILL_CREATOR:-false}"
INSTALL_NO_MISTAKES="${INSTALL_NO_MISTAKES:-false}"
INSTALL_EXA="${INSTALL_EXA:-false}"
INSTALL_GH="${INSTALL_GH:-false}"
INSTALL_GH_AXI="${INSTALL_GH_AXI:-false}"
INSTALL_NPM_AXI="${INSTALL_NPM_AXI:-false}"
OPTIONAL_SKILL_OR_TOOL_FLAG_WAS_PASSED=false

optional_skill_and_tool_flags_for_usage() {
  printf '%s' " [--matt-pocock-skills] [--skill-creator] [--no-mistakes] [--exa] [--gh] [--gh-axi] [--npm-axi] [--full]"
}

turn_on_all_optional_skills_and_tools() {
  INSTALL_MATT_POCOCK_SKILLS=true
  INSTALL_SKILL_CREATOR=true
  INSTALL_NO_MISTAKES=true
  INSTALL_EXA=true
  INSTALL_GH=true
  INSTALL_GH_AXI=true
  INSTALL_NPM_AXI=true
}

turn_on_optional_skill_or_tool() {
  OPTIONAL_SKILL_OR_TOOL_FLAG_WAS_PASSED=true
  case "$1" in
    --matt-pocock-skills) INSTALL_MATT_POCOCK_SKILLS=true ;;
    --skill-creator) INSTALL_SKILL_CREATOR=true ;;
    --no-mistakes) INSTALL_NO_MISTAKES=true ;;
    --exa) INSTALL_EXA=true ;;
    --gh) INSTALL_GH=true ;;
    --gh-axi) INSTALL_GH=true; INSTALL_GH_AXI=true ;;
    --npm-axi) INSTALL_NPM_AXI=true ;;
    --full) turn_on_all_optional_skills_and_tools ;;
    *) return 1 ;;
  esac
  return 0
}

remember_if_any_skill_or_gh_tool_is_on() {
  if [ "$OPTIONAL_SKILL_OR_TOOL_FLAG_WAS_PASSED" != true ]; then
    turn_on_all_optional_skills_and_tools
  fi
  if [ "$INSTALL_MATT_POCOCK_SKILLS" = true ] || [ "$INSTALL_SKILL_CREATOR" = true ] ||
    [ "$INSTALL_NO_MISTAKES" = true ] ||
    [ "$INSTALL_GH_AXI" = true ] || [ "$INSTALL_NPM_AXI" = true ]; then
    INSTALL_ANY_SKILL=true
  else
    INSTALL_ANY_SKILL=false
  fi
  if [ "$INSTALL_GH" = true ] || [ "$INSTALL_GH_AXI" = true ] || [ "$INSTALL_NPM_AXI" = true ]; then
    INSTALL_ANY_GH_TOOL=true
  else
    INSTALL_ANY_GH_TOOL=false
  fi
}

skill_agent_names_for_sandbox() {
  case "$SANDBOX_NAME" in
    claude-*) printf '%s\n' claude-code ;;
    codex-*) printf '%s\n' codex ;;
    opencode-*) printf '%s\n' opencode ;;
    cursor-*) printf '%s\n' cursor ;;
    cline-*) printf '%s\n' cline ;;
    commandcode-*) printf '%s\n' command-code ;;
    kilo-*) printf '%s\n' kilo ;;
    qwen-*) printf '%s\n' qwen-code ;;
    pi-*) printf '%s\n' pi ;;
    junie-*) printf '%s\n' junie ;;
    grok-*) printf '%s\n' grok ;;
    antigravity-*) printf '%s\n' antigravity-cli ;;
    herdr-*) printf '%s\n' claude-code codex opencode cursor ;;
    *) return 1 ;;
  esac
}

allow_skills_marketplace_network() {
  [ "${INSTALL_ANY_SKILL:-false}" = true ] || return 0
  local host
  for host in \
    add-skill.vercel.sh:443 \
    github.com:443 \
    api.github.com:443 \
    codeload.github.com:443 \
    registry.npmjs.org:443
  do
    sbx policy allow network --sandbox "$SANDBOX_NAME" "$host"
  done
}

allow_exa_mcp_network() {
  [ "${INSTALL_EXA:-false}" = true ] || return 0
  sbx policy allow network --sandbox "$SANDBOX_NAME" mcp.exa.ai:443
  sbx policy allow network --sandbox "$SANDBOX_NAME" auth.exa.ai:443
}

install_matt_pocock_skills() {
  [ "$INSTALL_MATT_POCOCK_SKILLS" = true ] || return 0
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
npx --yes skills@1.5.23 add mattpocock/skills \
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
  [ "$INSTALL_SKILL_CREATOR" = true ] || return 0
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
npx --yes skills@1.5.23 add anthropics/skills \
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
  [ "$INSTALL_NO_MISTAKES" = true ] || return 0
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
npx --yes skills@1.5.23 add kunchenguid/no-mistakes \
  --skill no-mistakes \
  ${agent_flags[*]} \
  --global \
  --yes \
  --copy
"; then
    echo "WARN: Could not install no-mistakes for: $*" >&2
  fi
}

install_github_tools() {
  [ "$INSTALL_ANY_GH_TOOL" = true ] || return 0
  local workspace_dir="$1"
  shift
  local agent_flags=()
  local agent_slug
  for agent_slug in "$@"; do
    agent_flags+=(--agent "$agent_slug")
  done

  if [ "$INSTALL_GH" = true ]; then
    echo "Installing gh for: $*"
    sbx policy allow network --sandbox "$SANDBOX_NAME" github.com:443
    sbx policy allow network --sandbox "$SANDBOX_NAME" api.github.com:443
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
    *) echo "ERROR: Unsupported architecture for gh: $(uname -m)" >&2; exit 1 ;;
  esac
  gh_tmp="$(mktemp -d)"
  gh_release="gh_${gh_version}_linux_${gh_arch}"
  curl -fsSL "https://github.com/cli/cli/releases/download/v${gh_version}/${gh_release}.tar.gz" \
    -o "$gh_tmp/gh.tar.gz"
  tar -xzf "$gh_tmp/gh.tar.gz" -C "$gh_tmp"
  sudo install -m 755 "$gh_tmp/$gh_release/bin/gh" /usr/local/bin/gh
  rm -rf "$gh_tmp"
fi
gh --version
'
  fi

  if [ "$INSTALL_GH_AXI" = true ]; then
    echo "Installing gh-axi for: $*"
    sbx exec "$SANDBOX_NAME" bash -lc 'npm install -g --ignore-scripts gh-axi@0.1.30'
  fi
  if [ "$INSTALL_NPM_AXI" = true ]; then
    echo "Installing npm-axi for: $*"
    sbx exec "$SANDBOX_NAME" bash -lc 'npm install -g --ignore-scripts npm-axi@0.1.1'
  fi
  if [ "$INSTALL_GH_AXI" = true ]; then
    sbx exec "$SANDBOX_NAME" bash -lc "
set -euo pipefail
cd '$workspace_dir'
npx --yes skills@1.5.23 add kunchenguid/gh-axi \
  --skill gh-axi \
  ${agent_flags[*]} \
  --global \
  --yes \
  --copy
" || echo "WARN: Could not install the gh-axi skill for: $*" >&2
  fi
  if [ "$INSTALL_NPM_AXI" = true ]; then
    sbx exec "$SANDBOX_NAME" bash -lc "
set -euo pipefail
cd '$workspace_dir'
npx --yes skills@1.5.23 add SSBrouhard/npm-axi \
  --skill npm-axi \
  ${agent_flags[*]} \
  --global \
  --yes \
  --copy
" || echo "WARN: Could not install the npm-axi skill for: $*" >&2
  fi
  if [ "$INSTALL_GH_AXI" = true ]; then
    sbx exec "$SANDBOX_NAME" bash -lc 'gh-axi setup hooks </dev/null || echo "WARN: Could not set up gh-axi session hooks." >&2'
  fi
  if [ "$INSTALL_NPM_AXI" = true ]; then
    sbx exec "$SANDBOX_NAME" bash -lc 'npm-axi setup hooks </dev/null || echo "WARN: Could not set up npm-axi session hooks." >&2'
  fi
  if [ "$INSTALL_GH" = true ]; then
    sbx exec "$SANDBOX_NAME" bash -lc '
set -euo pipefail
source /etc/sandbox-persistent.sh 2>/dev/null || true
cat > "$HOME/.gh-login-reminder.sh" <<'"'"'REMINDER'"'"'
if ! gh auth status >/dev/null 2>&1 || ! gh api user --jq .login >/dev/null 2>&1; then
  printf "\nGitHub access is not ready. gh and gh-axi need it.\nRun once in this sandbox: gh auth login\nChoose HTTPS, not SSH. HTTPS shares one token with git and adds no key to your account.\nThen run: gh-workbench-check\n\n"
fi
REMINDER
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/gh-workbench-check" <<'"'"'CHECK'"'"'
#!/usr/bin/env bash
set -euo pipefail
gh auth status
login="$(gh api user --jq .login)"
if command -v gh-axi >/dev/null 2>&1; then
  gh-axi issue list --limit 1 >/dev/null
fi
printf "GitHub access is ready for %s. gh and gh-axi can use this repository.\n" "$login"
CHECK
chmod 755 "$HOME/.local/bin/gh-workbench-check"
if ! grep ".gh-login-reminder.sh" "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<'"'"'HOOK'"'"'

if [ -t 1 ] && [ -f "$HOME/.gh-login-reminder.sh" ]; then
  bash "$HOME/.gh-login-reminder.sh"
fi
HOOK
fi
bash "$HOME/.gh-login-reminder.sh"
'
  fi
}

install_matt_pocock_skills_plugin() {
  [ "$INSTALL_MATT_POCOCK_SKILLS" = true ] || return 0
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

install_exa_for_harness() {
  [ "$INSTALL_EXA" = true ] || return 0
  allow_exa_mcp_network
  case "$SANDBOX_NAME" in
    claude-*|herdr-*)
      echo "Installing Exa web search for Claude Code..."
      sbx exec "$SANDBOX_NAME" bash -lc '
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
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
    claude mcp add --transport http --scope user exa https://mcp.exa.ai/mcp
  fi
fi
'
      ;;
    codex-*)
      echo "Registering the Exa MCP server with Codex..."
      sbx exec "$SANDBOX_NAME" bash -lc '
set -euo pipefail
if codex mcp get exa >/dev/null 2>&1; then
  echo "Exa MCP server already registered."
else
  timeout 20 codex mcp add exa --url https://mcp.exa.ai/mcp </dev/null >/dev/null 2>&1 || true
fi
'
      ;;
    grok-*)
      echo "Registering the Exa MCP server with Grok Build..."
      sbx exec "$SANDBOX_NAME" bash -lc '
set -euo pipefail
export PATH="$HOME/.grok/bin:$HOME/.local/bin:$PATH"
if grok mcp list 2>/dev/null | grep -q exa; then
  echo "Exa MCP server already registered."
else
  timeout 20 grok mcp add --transport http exa https://mcp.exa.ai/mcp </dev/null >/dev/null 2>&1 || true
fi
'
      ;;
  esac
}

install_selected_skills_and_tools() {
  remember_if_any_skill_or_gh_tool_is_on
  local slugs=()
  local slug
  while IFS= read -r slug; do
    slugs+=("$slug")
  done < <(skill_agent_names_for_sandbox || true)
  if [ "${#slugs[@]}" -eq 0 ]; then
    echo "WARN: No skill-agent name for sandbox $SANDBOX_NAME." >&2
    return 0
  fi

  allow_skills_marketplace_network
  allow_exa_mcp_network
  install_exa_for_harness
  case "$SANDBOX_NAME" in
    claude-*|herdr-*) install_matt_pocock_skills_plugin ;;
  esac
  install_matt_pocock_skills "$WORKSPACE_ROOT_DIR" "${slugs[@]}"
  install_skill_creator "$WORKSPACE_ROOT_DIR" "${slugs[@]}"
  install_no_mistakes "$WORKSPACE_ROOT_DIR" "${slugs[@]}"
  install_github_tools "$WORKSPACE_ROOT_DIR" "${slugs[@]}"
  case "$SANDBOX_NAME" in
    codex-*|herdr-*)
      if [ "$INSTALL_ANY_SKILL" = true ]; then
        link_codex_skills_for_discovery
      fi
      ;;
  esac
}
