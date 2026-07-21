# System Instructions

- Do not be verbose. Communicate the most important information in as concise a manner as possible.
- Read [CONVENTIONS.md](./readonly/CONVENTIONS.md) for coding conventions to follow. IMPORTANT: Do not ever run the full test suite unless asked to.
- Read [REACT_INSTRUCTIONS.md](./readonly/REACT_INSTRUCTIONS.md)

## Communication

- Keep design discussion and summaries short and in plain words. Avoid dense, jargon-heavy prose and long compound sentences.
- Lead with the plain-terms definition of a thing before proposing any name or design detail for it.
- For open items, use short numbered lists: one sentence of context, one clear question. Mark each item as "decision needed" vs "just say ok".
- Prefer everyday words over jargon.

## Restricted Files

Do not inspect, read, print, summarize, or modify:

- `.env`
- `.env.*`

## Code Simplification

- Fundamental Rule: CODE YOU WRITE SHOULD BE EASY TO READ AND EASY TO UNDERSTAND.
- Always prefer deleting code over adding code
- Design things as simple as possible, but no simpler.
- The end goal should be to produce code that is Easy To Change, extensible, maintainable, debuggable, testable and follows good software design principles.

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
