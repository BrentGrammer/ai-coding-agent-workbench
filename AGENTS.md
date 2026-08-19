# Project Instructions

## Communication

- Use ASD-STE100 Simplified Technical English. Keep reports short and clear.
- Use plain words. Define a thing before you give it a name or design detail.
- For open items, use a short numbered list. State the context and ask one clear question. Mark it as `decision needed` or `just say ok`.

## Restricted Files

- Do not inspect, print, summarize, or modify `.env` or `.env.*`.

## Code

- Keep code easy to read, change, debug, and test.
- Prefer deleting code over adding code.
- Use clear names that state the action and purpose.
- Do not use `resolve` in a function name unless no clearer name exists.
- Do not write code comments unless they explain a necessary reason that the code cannot state clearly.
- If writing comments in code, they must be no longer than 2 lines at most.
- Do not end user-facing text with a semicolon.

## Tests

- Write focused tests for new behavior.
- Do not run the full test suite unless the user asks.

## Tools

- Use `gh-axi` instead of `gh` for GitHub operations (issues, PRs, runs, releases, labels, search).
- GitHub CLI setup in this environment: `gh` is a wrapper script (`/usr/local/bin/gh`). It reads `$WORKSPACE_DIR`, gets the `origin` remote of that directory, and mints a token for that one repo. `WORKSPACE_DIR` points at the workspace root, which is not a git repo. So `gh` and `gh-axi` fail with `fatal: not a git repository` from every directory. Fix: set `WORKSPACE_DIR` to the repo you want to operate on, for example `WORKSPACE_DIR=/home/ubuntu/workspace/Stockglasses/stockglasses-backend gh api ...` (use the `stockglasses-frontend` path for frontend operations — the token is scoped per repo). The git credential helper (`git-credential-github-app`) uses the same scope, so `git pull` and `git push` fail with `Repository not found` without the same `WORKSPACE_DIR` override. Run these commands with the sandbox disabled: the token comes from a host the sandbox does not allow. Do not use unauthenticated `curl` to `api.github.com` — the repos are private and return 404.
- Use `npm-axi` for npm registry lookups (search, view, versions, downloads).
- Use the Exa MCP server for documentation when it is available.
  IMPORTANT: If Exa hangs and takes longer than 10 seconds to fetch, abandon using it and try something else. Do not wait minutes for it.

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues (github.com/BrentGrammer/ai-coding-agent-workbench), using the gh CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default label vocabulary (needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: CONTEXT.md + docs/adr/ at the repo root. See `docs/agents/domain.md`.
