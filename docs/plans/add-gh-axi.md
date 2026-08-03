# Add AXI tools to the Cloud Workbench

## AXI tools to add

### gh-axi

Wraps the `gh` CLI with agent-ergonomic output: TOON format (~40% token savings), contextual next-step suggestions, pre-computed aggregates, and structured errors. Benchmarks show 100% success at $0.050/task vs 86% for raw `gh` CLI.

- npm: `gh-axi` (v0.1.29, 3400+ weekly downloads)
- Repo: `kunchenguid/gh-axi`
- Skills repo: `kunchenguid/gh-axi`
- Session hooks: `gh-axi setup hooks` (Claude Code, Codex, OpenCode)

### npm-axi

Wraps the public npm registry in an agent-ergonomic CLI. Search packages, view details, check versions and downloads — all with TOON output. Read-only, no auth required.

- npm: `npm-axi` (v0.1.1)
- Repo: `SSBrouhard/npm-axi`
- Skills repo: `SSBrouhard/npm-axi`
- Session hooks: `npm-axi setup hooks` (Claude Code, Codex, OpenCode)

## Auth compatibility (gh-axi)

The workbench uses a GitHub App token relay — no `gh auth login`. The wrapper at `/usr/local/bin/gh` (`infra/aws/runtime/gh-with-github-app`) sets `GH_TOKEN` from the relay, then exec's the real `gh-cli`. Because gh-axi calls `gh` under the hood, it will hit this wrapper. `WORKSPACE_DIR` is already set in every workbench pane via `infra/aws/ec2/start-herdr`, so the wrapper will work. No auth changes needed.

npm-axi has no auth — it reads the public npm registry.

## Changes

### 1. Pin versions and npm-install in setup script

In `infra/aws/ec2/setup-workbench.sh`:

- Add `GH_AXI_VERSION` and `NPM_AXI_VERSION` variables at the top
- Pass them into the `USER_SETUP` heredoc environment
- Add `"gh-axi@${GH_AXI_VERSION}"` and `"npm-axi@${NPM_AXI_VERSION}"` to the existing `npm install -g` line

### 2. Install skills for all agents

Use the `npx skills` CLI (already used for Matt Pocock skills at lines 222-234):

```bash
npx --yes skills@latest add kunchenguid/gh-axi \
  --skill gh-axi \
  --agent claude-code \
  --agent codex \
  --agent opencode \
  --agent cursor \
  --global \
  --yes \
  --copy

npx --yes skills@latest add SSBrouhard/npm-axi \
  --skill npm-axi \
  --agent claude-code \
  --agent codex \
  --agent opencode \
  --agent cursor \
  --global \
  --yes \
  --copy
```

### 3. Set up session hooks (Claude Code, Codex, OpenCode)

Run `gh-axi setup hooks` and `npm-axi setup hooks` in the `USER_SETUP` block. These install `SessionStart` hooks that surface contextual guidance at the start of every session. Separate from the existing `PreToolUse` hook in `tools/agents/claude-settings.json` — no conflict.

Cursor does not support these hooks — it relies on skills from step 2.

### 4. Update AGENTS.md

Add under `## Tools`:

```
- Use `gh-axi` instead of `gh` for GitHub operations (issues, PRs, runs, releases, labels, search).
- Use `npm-axi` for npm registry lookups (search, view, versions, downloads).
```

## Not changing

- **`/usr/local/bin/gh` wrapper** — no changes. gh-axi calls `gh`, which hits the existing wrapper. The token relay chain stays intact.
- **Sandbox network allowlist** — `api.github.com` and `github.com` are already allowed. npm-axi calls `registry.npmjs.org` which may need to be added if sandboxed agents use it.
- **Local workbench** — scoped to EC2 only for now.

## Test plan

Test on the EC2 workbench only. Local workbench is out of scope.

### Deploy the change onto the box

**After merge to `main`:**

```shell
workbench ec2 up          # if the box is stopped
workbench ec2 update      # fetches origin/main and re-runs setup
workbench ec2 mosh
```

**Before merge (branch smoke test):**

```shell
workbench ec2 ssh
sudo git -C /opt/agent-workbench fetch origin feature/add-axi
sudo git -C /opt/agent-workbench reset --hard origin/feature/add-axi
sudo bash /opt/agent-workbench/infra/aws/ec2/setup-workbench.sh
```

Setup must finish without fatal errors. Warnings on skill/hook install are acceptable to investigate, but `gh-axi` and `npm-axi` must be on `PATH`.

### Verify CLIs

```shell
gh-axi --version          # expect 0.1.29
npm-axi --version         # expect 0.1.1

gh-axi issue list --repo BrentGrammer/ai-coding-agent-workbench --limit 3
npm-axi view gh-axi
```

- `gh-axi` must succeed via the existing `/usr/local/bin/gh` token wrapper (no `gh auth login`).
- `npm-axi` must return package metadata from the public registry.

### Verify skills

Skills exist for each agent:

```shell
ls ~/.claude/skills/gh-axi ~/.codex/skills/gh-axi \
   ~/.config/opencode/skills/gh-axi ~/.cursor/skills/gh-axi

ls ~/.claude/skills/npm-axi ~/.codex/skills/npm-axi \
   ~/.config/opencode/skills/npm-axi ~/.cursor/skills/npm-axi
```

Codex discovery also needs the symlink under `~/.agents/skills/` (setup already links `~/.codex/skills/*` there).

### Verify session hooks

Confirm `gh-axi setup hooks` and `npm-axi setup hooks` registered SessionStart hooks for Claude Code, Codex, and OpenCode. Cursor has no hooks — skills only.

### Verify agent guidance

`AGENTS.md` on the box (via `/opt/agent-workbench`) tells agents to prefer `gh-axi` and `npm-axi`. In a fresh Herdr pane, ask an agent to list issues or look up an npm package and confirm it uses those CLIs.
