# Project Instructions

## Restricted Files

- Do not inspect, print, summarize, or modify `.env` or `.env.*`.

## Communication

- Be short and concise in responses preferring plain English and terms over jargon.

## Code

- Code you write should be easy to understand, easy to read, easy to change, maintain and test.
- Prefer deleting code over adding code.
- Use clear names that express the intent and purpose of the function or variable.
- Do not use `resolve` in a function name unless no clearer name exists.
- If writing comments in code, they must be no longer than 2 lines at most and explain the WHY, not the WHAT.
- Do not end text with a semicolon, use periods and sentences.

## Tests

- Tests should cover observable behavior and not be tied closely to implementation details.
- Test descriptions and names should be understandable by a stakeholder and non-technical business person or domain expert.
- Do not run the full test suite unless the user asks.

## Tools

- Use `gh-axi` instead of `gh` for GitHub operations (issues, PRs, runs, releases, labels, search).
- GitHub CLI setup in this environment: `gh` is a wrapper script (`/usr/local/bin/gh`). It reads`$WORKSPACE_DIR`, gets the `origin` remote of that directory, and mints a token for that one repo. `WORKSPACE_DIR` points at the workspace root, which is not a git repo. So `gh` and `gh-axi` fail with `fatal: not a git repository` from every directory. Fix: set `WORKSPACE_DIR` to the repo you want to operate on, for example `WORKSPACE_DIR=/home/ubuntu/workspace/Stockglasses/stockglasses-backend gh api ...` (use the `stockglasses-frontend` path for frontend operations — the token is scoped per repo). The git credential helper (`git-credential-github-app`) uses the same scope, so `git pull` and `git push` fail with `Repository not found` without the same `WORKSPACE_DIR` override. Run these commands with the sandbox disabled: the token comes from a host the sandbox does not allow. Do not use unauthenticated `curl` to `api.github.com` — the repos are private and return 404.
- Use `npm-axi` for npm registry lookups (search, view, versions, downloads).
- If tools are missing, say so instead of working around them.
- Use the Exa MCP server for documentation when it is available.
  IMPORTANT: If Exa hangs and takes longer than 10 seconds to fetch, abandon using it and try something else. Do not wait minutes for it.

## Agent skills

### Triage labels

Default label vocabulary (needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: CONTEXT.md (if it exists) + docs/adr/ at the repo root. See `docs/agents/domain.md`.
