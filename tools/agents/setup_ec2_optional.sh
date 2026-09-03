#!/usr/bin/env bash
set -euo pipefail

GH_AXI_VERSION=0.1.30
NPM_AXI_VERSION=0.1.1
SKILLS_CLI_VERSION=1.5.23

export NPM_CONFIG_PREFIX="$HOME/.local/npm"
export PATH="$HOME/.local/npm/bin:$HOME/.local/bin:$PATH"

mkdir -p "$HOME/.agents/skills" "$HOME/.config/opencode" "$HOME/.cursor"

npm install -g --ignore-scripts \
  "gh-axi@${GH_AXI_VERSION}" \
  "npm-axi@${NPM_AXI_VERSION}"
gh-axi --version
npm-axi --version

if [ ! -f "$HOME/.cursor/mcp.json" ]; then
  cat > "$HOME/.cursor/mcp.json" <<'EOF'
{
  "mcpServers": {
    "exa": {
      "type": "http",
      "url": "https://mcp.exa.ai/mcp"
    }
  }
}
EOF
  chmod 600 "$HOME/.cursor/mcp.json"
fi

if [ -f "$HOME/.config/opencode/opencode.json" ] &&
  ! jq -e '.mcp.exa' "$HOME/.config/opencode/opencode.json" >/dev/null 2>&1; then
  tmp_json="$(mktemp)"
  jq '.mcp.exa = {"type": "remote", "url": "https://mcp.exa.ai/mcp", "enabled": true}' \
    "$HOME/.config/opencode/opencode.json" > "$tmp_json"
  mv "$tmp_json" "$HOME/.config/opencode/opencode.json"
  chmod 600 "$HOME/.config/opencode/opencode.json"
fi

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

echo "Installing Exa for Claude Code..."
if ! claude plugin list 2>/dev/null | grep -q exa; then
  claude plugin marketplace add anthropics/claude-plugins-official </dev/null >/dev/null 2>&1 || true
  if ! claude plugin install exa@claude-plugins-official </dev/null >/dev/null 2>&1 &&
    ! claude mcp get exa >/dev/null 2>&1; then
    claude mcp add --transport http --scope user exa https://mcp.exa.ai/mcp </dev/null >/dev/null 2>&1 || true
  fi
fi
if ! claude plugin list 2>/dev/null | grep -q exa &&
  ! claude mcp list 2>/dev/null | grep -q exa; then
  echo "WARN: Claude Code has neither the Exa plugin nor the Exa MCP server." >&2
fi

echo "Registering the Exa MCP server with Codex..."
if ! codex mcp get exa >/dev/null 2>&1; then
  timeout 20 codex mcp add exa --url https://mcp.exa.ai/mcp </dev/null >/dev/null 2>&1 || true
fi
if ! codex mcp get exa >/dev/null 2>&1; then
  echo "WARN: Codex does not list the Exa MCP server." >&2
fi
