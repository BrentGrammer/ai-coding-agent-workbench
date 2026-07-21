# CLAUDE.md

## Communication

- Keep design discussion and summaries short and in plain words. Avoid dense, jargon-heavy prose and long compound sentences.
- Lead with the plain-terms definition of a thing before proposing any name or design detail for it.
- For open items, use short numbered lists: one sentence of context, one clear question. Mark each item as "decision needed" vs "just say ok".
- Prefer everyday words over jargon.

## Agent skills

- The agentcore Docker image (`infra/aws/microvms/claude-code-agentcore/Dockerfile`) bakes in Matt Pocock's skills plugin (`mattpocock/skills`).
- If you want to use specific issue tracker skills, then you need to run `/setup-matt-pocock-skills` once in this repo. It's interactive, then writes `docs/agents/*.md` and adds an `## Agent skills` block here. Skipping it means `triage`/`to-spec`/`to-tickets` will guess or ask instead of using real repo config.

## Project-specific rules

- Do not read, print, or modify `.env` / `.env.*`.

## Comments

- Do not write comments in the code. If you have to write a comment it means the code is not clear enough, self-explanatory or easy to reason about. It is a smell and means you need to rewrite the code to be more expressive.
- The code should be self-documenting through expressive and meaningful names. If you need to write a comment, that probably means the code is not written clearly and expressively enough. Prefer changing and updating names to make intent and meaning clear over inserting a comment.
- If a comment is absolutely needed, then a comment explain WHY, not WHAT. A comment that restates what the code does is redundant.
- Do not end sentences with a semicolon. End with a period and start a new sentence. This goes for display text in the UI as well such as tooltips and descriptions.

## Naming

- Avoid "resolve" in function names. Do not over-use that terminology unless there is truly no other alternative way to express what the function is doing. Resolve is a vague term and should be avoided where possible.
- Most of the time function names should follow the convention: `verbSubject` - Example: `normalizeInputField` and not `normalizedInputField` (which is a noun, not an action). 
- The name should answer these questions as best as possible:
  - What is the function doing?
  - Why does the function exist and why is it needed?

## Git

- Never push to main
- Always work on a feature branch - check that you are checked out to a branch and not on main
- Never attribute any commits to Claude
- Before committing - pull latest changes on the branch to make sure we are in sync.
