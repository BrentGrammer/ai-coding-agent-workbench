# Wayfinder installation

Date: 2026-07-30

## Result

Wayfinder is part of the main `mattpocock/skills` repository. It is not a separate repository or package. It is a user-invoked skill for work that is too large for one agent session.

The direct install command is:

```shell
npx skills@latest add https://github.com/mattpocock/skills --skill wayfinder
```

The [Wayfinder page on skills.sh](https://www.skills.sh/mattpocock/skills/wayfinder) gives this command. The [source skill](https://github.com/mattpocock/skills/blob/main/skills/engineering/wayfinder/SKILL.md) also says to run `/setup-matt-pocock-skills` before use if the project does not have issue tracker setup.

## Claude Code

Matt Pocock recommends the managed Claude Code plugin:

```shell
claude plugin install mattpocock-skills
```

The [Matt Pocock skills README](https://github.com/mattpocock/skills#installation-30-second-setup) says that this plugin installs the full set and receives updates. The current [Claude Code plugin reference](https://code.claude.com/docs/en/plugins-reference#plugin-install) confirms the singular `claude plugin install` command form.

Do not also install the same skills with the `skills` CLI for Claude Code. This gives Claude two copies of each skill.

## Codex and other agents

The `skills` CLI supports a named skill, a named agent, a global install, and a non-interactive install. For example:

```shell
npx --yes skills@latest add mattpocock/skills \
  --skill wayfinder \
  --agent codex \
  --global \
  --yes \
  --copy
```

Change the `--agent` value for another harness. The [skills CLI documentation](https://github.com/vercel-labs/skills#supported-agents) gives these values:

| Harness | `--agent` value | Global skill path |
| --- | --- | --- |
| Codex | `codex` | `~/.codex/skills/` |
| OpenCode | `opencode` | `~/.config/opencode/skills/` |
| Cursor | `cursor` | `~/.cursor/skills/` |
| Cline | `cline` | `~/.agents/skills/` |
| Antigravity CLI | `antigravity-cli` | `~/.gemini/antigravity-cli/skills/` |
| Pi | `pi` | `~/.pi/agent/skills/` |
| Command Code | `command-code` | `~/.commandcode/skills/` |
| Gemini CLI | `gemini-cli` | `~/.gemini/skills/` |
| Grok Build | `grok` | `~/.grok/skills/` |
| Kilo Code | `kilo` | `~/.kilocode/skills/` |

The CLI supports all these harnesses.

For Codex, `$HOME/.agents/skills` is a supported user skill location. Codex detects skill changes automatically. Use `/skills` or type `$wayfinder` to invoke Wayfinder. Restart Codex only if the skill does not appear after installation.

Codex limits the skill metadata placed in its initial prompt. When many skills are installed, a skill can be absent from that initial list and still be installed and available through `/skills`.

## This project

The project already uses `--skill '*'` for Codex, OpenCode, Cursor, Cline, Antigravity CLI, and Pi. The Herdr launcher installs the full set for Codex, OpenCode, and Cursor. These install calls include Wayfinder when they run against the current Matt Pocock repository.

Claude and Herdr use the Matt Pocock Claude plugin. The project uses an older custom marketplace flow. The current Matt Pocock instructions use the official marketplace command shown above.

Four launchers do not call the shared Matt Pocock installer:

1. Command Code
2. Gemini CLI
3. Grok Build
4. Kilo Code

They are feasible because the `skills` CLI lists all four as supported agents. Each launcher can call `allow_skills_marketplace_network`, then call:

```shell
install_matt_pocock_skills "$REPO_ROOT" <agent-value>
```

Use `command-code`, `gemini-cli`, `grok`, or `kilo` as `<agent-value>`.

## Recommended project action

1. Keep `--skill '*'` for the harnesses that already use it. No Codex restart is normally required because Codex detects skill changes automatically.
2. Change the Claude installer to `claude plugin install mattpocock-skills`.
3. Add the shared installer to Command Code, Gemini CLI, Grok Build, and Kilo Code.
4. Run `/setup-matt-pocock-skills` once in each target project before the first Wayfinder run.

## Prerequisites for this project

Beyond installing the skill, Wayfinder needs two things set up in this repo before first use.

1. **`gh` (GitHub CLI)**, installed and able to create/read/close issues. In the AgentCore sandbox this is not `gh auth login` — that would leave a durable token in `~/.config/gh/hosts.yml` inside the sandbox. Instead, the existing `gh` wrapper gets a fresh, repo-scoped, one-hour token from the same GitHub App broker Lambda that the git credential helper uses. Claude's managed network settings allow the Lambda and GitHub API endpoints. The GitHub CLI runs inside the agent's Bash sandbox. The GitHub App private key stays in Lambda, and nothing persists.

   In the local (non-AgentCore) sandbox launched by `tools/agents/start_claude.sh`, this wrapper does not exist — `gh` must be installed and authenticated manually there, and the welcome banner prints a one-line reminder of that prerequisite.

2. **`/setup-matt-pocock-skills`**, run once per repo. For this project it wrote:
   - `docs/agents/issue-tracker.md` — GitHub via `gh`, PRs-as-triage-surface off
   - `docs/agents/triage-labels.md` — default label vocabulary
   - `docs/agents/domain.md` — single-context layout
   - An `## Agent skills` section in `AGENTS.md` pointing at the three files above

   The AgentCore welcome banner (`infra/aws/runtime/workbench-profile.sh`) reminds you to run this if you have not already.

## GitHub App permissions

Wayfinder stores its map and tickets as GitHub issues, so the GitHub App used by this project's AgentCore sandbox needs these permissions:

| Permission | Level | Why |
| --- | --- | --- |
| Contents | Read & write | git clone/fetch/push |
| Issues | Read & write | Create/comment/close issues, labels, assignees, sub-issues, and issue dependencies (`blocked_by`) — all Wayfinder operations |
| Metadata | Read-only | Mandatory default for any GitHub App, added automatically |

Not needed unless the "PRs as a request surface" flag in `docs/agents/issue-tracker.md` is turned on:

| Permission | Level | Why |
| --- | --- | --- |
| Pull requests | Read & write | Only if external PRs are treated as triage requests |

## Sources

- [Matt Pocock skills installation](https://github.com/mattpocock/skills#installation-30-second-setup)
- [Wayfinder on skills.sh](https://www.skills.sh/mattpocock/skills/wayfinder)
- [Wayfinder source](https://github.com/mattpocock/skills/blob/main/skills/engineering/wayfinder/SKILL.md)
- [Skills CLI options and supported agents](https://github.com/vercel-labs/skills#supported-agents)
- [Claude Code plugin command reference](https://code.claude.com/docs/en/plugins-reference#plugin-install)
- [OpenAI Codex skill loading and invocation](https://learn.chatgpt.com/docs/build-skills)
