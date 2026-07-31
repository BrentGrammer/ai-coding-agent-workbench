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
- Do not end user-facing text with a semicolon.

## Tests

- Write focused tests for new behavior.
- Do not run the full test suite unless the user asks.

## Tools

- Use the Exa MCP server for documentation when it is available.
IMPORTANT: If Exa hangs and takes longer than 10 seconds to fetch, abandon using it and try something else. Do not wait minutes for it.

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues (github.com/BrentGrammer/ai-coding-agent-workbench), using the gh CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default label vocabulary (needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: CONTEXT.md + docs/adr/ at the repo root. See `docs/agents/domain.md`.
