# Add gh-axi to the Cloud Workbench

## What gh-axi does

`gh-axi` wraps the `gh` CLI with agent-ergonomic output: TOON format (~40% token savings), contextual next-step suggestions, pre-computed aggregates, and structured errors. Benchmarks show 100% success at $0.050/task vs 86% for raw `gh` CLI.

## Auth compatibility

The workbench uses a GitHub App token relay — no `gh auth login`. The wrapper at `/usr/local/bin/gh` (`infra/aws/runtime/gh-with-github-app`) sets `GH_TOKEN` from the relay, then exec's the real `gh-cli`. Because gh-axi calls `gh` under the hood, it will hit this wrapper. `WORKSPACE_DIR` is already set in every workbench pane via `infra/aws/ec2/start-herdr`, so the wrapper will work. No auth changes needed.

## Changes

### 1. Pin version and npm-install in setup script

In `infra/aws/ec2/setup-workbench.sh`:

- Add a `GH_AXI_VERSION` variable at the top (alongside the other version pins)
- Pass it into the `USER_SETUP` heredoc environment
- Add `"gh-axi@${GH_AXI_VERSION}"` to the existing `npm install -g` line

This makes `gh-axi` a first-class command on the workbench, version-pinned like every other tool.

### 2. Install the gh-axi skill for all agents

In the same `USER_SETUP` block, use the `npx skills` CLI (already used for Matt Pocock skills at lines 222-234):

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
```

One command installs the skill for all four agents. Same approach as the existing Matt Pocock skills block.

### 3. Set up session hooks (Claude Code, Codex, OpenCode)

Run `gh-axi setup hooks` in the `USER_SETUP` block. This installs a `SessionStart` hook that surfaces open issues, open PRs, and usage guidance at the start of every session. The hook is separate from the existing `PreToolUse` hook in `tools/agents/claude-settings.json` — no conflict.

Note: Cursor does not support `gh-axi setup hooks` — it relies on the skill from step 2.

### 4. Update AGENTS.md

Add a line under `## Tools` in `AGENTS.md`:

```
- Use `gh-axi` instead of `gh` for GitHub operations (issues, PRs, runs, releases, labels, search).
```

## Not changing

- **`/usr/local/bin/gh` wrapper** — no changes. gh-axi calls `gh`, which resolves to the existing wrapper. The token relay chain stays intact.
- **Sandbox network allowlist** — `api.github.com` and `github.com` are already allowed.
- **Local workbench** — scoped to EC2 only for now (the branch name `feature/add-axi` can address local later if desired).
