# Optional Skills and Tools Instructions

Optional skills and tools are opt-in. Do not assume they are installed unless their files or commands are present.

## Communication

- If `~/.agents/skills/unslop/SKILL.md` exists, read and follow it for writing and responses.

## Tools

- If `gh-axi` is installed, use it instead of `gh` for GitHub operations.
- If `npm-axi` is installed, use it for npm registry lookups.
- If an optional tool is unavailable, say so instead of installing it implicitly.
- Use the Exa MCP server for documentation when it is available. If it takes longer than 10 seconds, stop waiting and use another source.

## Agent Documentation

### Triage labels

Default label vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Use `CONTEXT.md` when it exists and the ADRs under `docs/adr/`. See `docs/agents/domain.md`.
