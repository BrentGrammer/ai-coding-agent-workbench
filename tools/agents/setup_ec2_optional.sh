#!/usr/bin/env bash
set -euo pipefail

GH_VERSION=2.103.3
GH_AXI_VERSION=0.1.44
NPM_AXI_VERSION=0.1.1
SKILLS_CLI_VERSION=1.7.4

export NPM_CONFIG_PREFIX="$HOME/.local/npm"
export PATH="$HOME/.local/npm/bin:$HOME/.local/bin:$HOME/.grok/bin:$HOME/.antigravity/bin:$PATH"

mkdir -p "$HOME/.local/lib" "$HOME/.agents/skills"

npm install -g --ignore-scripts \
  "gh-axi@${GH_AXI_VERSION}" \
  "npm-axi@${NPM_AXI_VERSION}"
gh-axi --version
npm-axi --version

# gh-axi needs gh. The wrapper takes the gh name and hands the real binary a
# fresh GitHub App token per call, so no login is stored.
gh_dir="$HOME/.local/lib/gh"
if ! "$gh_dir/bin/gh" --version 2>/dev/null | grep -q "gh version $GH_VERSION "; then
  gh_tmp="$(mktemp -d)"
  gh_release="gh_${GH_VERSION}_linux_arm64"
  curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/${gh_release}.tar.gz" \
    -o "$gh_tmp/gh.tar.gz"
  tar -xzf "$gh_tmp/gh.tar.gz" -C "$gh_tmp"
  rm -rf "$gh_dir"
  mv "$gh_tmp/$gh_release" "$gh_dir"
  rm -rf "$gh_tmp"
fi
install -m 755 "$REPO_DIR/infra/aws/runtime/gh-with-app-token" "$HOME/.local/bin/gh"
"$gh_dir/bin/gh" --version

echo "Installing the Matt Pocock skills plugin for Claude Code..."
if claude plugin list 2>/dev/null | grep -q mattpocock-skills; then
  claude plugin update mattpocock-skills </dev/null >/dev/null 2>&1 || true
else
  claude plugin marketplace add mattpocock/skills </dev/null >/dev/null 2>&1 || true
  claude plugin install mattpocock-skills@mattpocock </dev/null >/dev/null 2>&1 || true
fi
if ! claude plugin list 2>/dev/null | grep -q mattpocock-skills; then
  echo "WARN: The Matt Pocock skills plugin did not install for Claude Code." >&2
fi

echo "Installing Matt Pocock skills for Codex, OpenCode, and Cursor..."
if ! (
  cd "$HOME"
  npx --yes "skills@${SKILLS_CLI_VERSION}" add mattpocock/skills \
    --agent codex \
    --agent opencode \
    --agent cursor \
    --skill '*' \
    --global \
    --yes \
    --copy
) </dev/null; then
  echo "WARN: Could not install Matt Pocock skills for Codex, OpenCode, or Cursor." >&2
fi

echo "Installing gh-axi, npm-axi, skill-creator, and PStack skills..."
if ! (
  cd "$HOME"
  npx --yes "skills@${SKILLS_CLI_VERSION}" add kunchenguid/gh-axi \
    --skill gh-axi \
    --agent claude-code \
    --agent codex \
    --agent opencode \
    --agent cursor \
    --global \
    --yes \
    --copy
  npx --yes "skills@${SKILLS_CLI_VERSION}" add SSBrouhard/npm-axi \
    --skill npm-axi \
    --agent claude-code \
    --agent codex \
    --agent opencode \
    --agent cursor \
    --global \
    --yes \
    --copy
  npx --yes "skills@${SKILLS_CLI_VERSION}" add anthropics/skills \
    --skill skill-creator \
    --agent claude-code \
    --agent codex \
    --agent opencode \
    --agent cursor \
    --global \
    --yes \
    --copy
  npx --yes "skills@${SKILLS_CLI_VERSION}" add cursor/plugins/pstack \
    --skill unslop \
    --agent claude-code \
    --agent codex \
    --agent opencode \
    --agent cursor \
    --global \
    --yes \
    --copy
) </dev/null; then
  echo "WARN: Could not install gh-axi, npm-axi, skill-creator, or PStack skills." >&2
fi

echo "Setting up gh-axi and npm-axi session hooks..."
gh-axi setup hooks </dev/null || echo "WARN: Could not set up gh-axi session hooks." >&2
npm-axi setup hooks </dev/null || echo "WARN: Could not set up npm-axi session hooks." >&2

for skill_dir in "$HOME/.codex/skills"/*; do
  [ -d "$skill_dir" ] || continue
  skill_name="$(basename "$skill_dir")"
  [ "$skill_name" = ".system" ] && continue
  ln -sfn "$skill_dir" "$HOME/.agents/skills/$skill_name"
done
