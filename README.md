# AI Coding Agent Workbench

This project bootstraps Claude Code, Codex, Cursor CLI and OpenCode in [Herdr](https://herdr.dev/) using [Hunk](https://www.hunk.dev/) in the Cloud. It also supports running coding agents locally with `sbx` Docker sandbox MicroVMs for a variety of harnesses.

Docker Sandboxes include sbx policies for opening connections for Ubuntu/system updates and each model provider's API routes. Review and adjust these in the scripts as needed (find `sbx policy allow network...` entries).

Launchers also auto-install skills, MCP tools, and hooks for some harnesses. See [Auto-installed tools, skills, and hooks](#auto-installed-tools-skills-and-hooks) for the full list and how to remove them.

Note: CLAUDE.md and AGENTS.md are fine-tuned to a personal workflow (the owner of this repo, of course). Adjust and edit these files to your needs and preferences. Also review the dot files (`.gemini/, .cline/`, and files in the `/tools/agents/` folder: `codex-config.toml`, `claude-settings.json`, `cursor-mcp.json`, `opencode.json`, `cline-global-settings.json`, etc.) which contain some baked in settings for convenience (statusline content, accept all edits mode, etc.) and change any of them to your liking.

## Choose a path

- **Local Docker sandboxes** — run agents on your machine with `sbx`. See [Local Docker sandboxes](#local-docker-sandboxes).
- **Cloud (AWS Bedrock AgentCore)** — run the Herdr workbench on AWS Bedrock AgentCore. See [Cloud (AWS Bedrock AgentCore)](#cloud-aws-bedrock-agentcore).

## Platform support

- macOS is supported.
- Linux and WSL2 are not yet verified.
- Windows is not currently supported.

## Install launcher commands (PATH)

Convenience commands in the `bin` folder bootstrap local Docker sandbox agents and AgentCore sessions (`start-herdr`, `start-claude`, `start-agentcore`, `workbench`, and others).

Run the installer once to add the commands to PATH:

```shell
./bin/install-commands
```

It checks for command collisions, confirms the profile change, and creates a backup. To select another profile:

```shell
# Optional: override auto detection of profile:
./bin/install-commands --profile /path/to/profile
```

## Local Docker sandboxes

### Prerequisites

- [Docker Desktop](https://docs.docker.com/desktop/)
- [Docker Sandboxes (`sbx`)](https://docs.docker.com/ai/sandboxes/get-started/) installed, signed in, and configured for locked-down mode.
- (Recommended) A terminal with OSC 52 clipboard support, such as Ghostty.
- Login credentials or an API key for the coding agent you plan to use.

Node.js, Herdr, Hunk, and the coding-agent CLIs are installed inside the sandbox by the launchers. An IDE is optional. For skills, MCP tools, and hooks installed on top of those CLIs, see [Auto-installed tools, skills, and hooks](#auto-installed-tools-skills-and-hooks).

### Start locally

Run from the project you want to work on:

```shell
cd /path/to/local-project-folder
start-herdr claude
```

Choose another primary agent or project:

```shell
start-herdr codex
start-herdr cursor
start-herdr opencode /path/to/another-project
```

Run one agent without Herdr:

```shell
start-claude
start-codex /path/to/another-project
start-opencode
```

Run a direct agent from a parent folder:

```shell
cd "/workspace/My Projects"
start-codex
```

Every child repository is writable. Run Git commands inside the child repository that the command applies to.

Other available launchers:

```shell
start-antigravity
start-cline
start-commandcode
start-cursor
start-gemini
start-grok
start-kilo
start-pi
```

Each command uses the current directory unless a project path is passed. Sandbox names use the workspace folder name and a hash of its canonical path. Sandboxes are reused only for the same workspace path, so the first launch with the new name can require a new agent login.

### Project instruction files

When `AGENTS.md` or `CLAUDE.md` is missing, the selected local launchers ask if they should copy the missing files into the project root.

Show the choice again:

```shell
start-codex --prompt-instruction-copy
start-codex --prompt-instruction-copy "/path/to/project"
```

`readonly/CONVENTIONS.md` and `readonly/REACT_INSTRUCTIONS.md` are optional convenience files. You can copy them into a project yourself when needed.

### `--clone`: keep secrets out of the sandbox

Launchers mount your live folder, so a real `.env` is readable by the agent. Some of the harnesses have sufficient protection, but some do not and `--clone` is recommended for:

**Recommended: Use `--clone` with these:** `start-cline`, `start-cursor`, `start-antigravity`, `start-gemini`, `start-grok`, `start-kilo`, `start-pi`, `start-commandcode`. None of them can block a secret read.

**Skip it with these:** `start-claude`, `start-opencode`, `start-codex`. All three block secret reads on their own.

```shell
start-cursor --clone
SANDBOX_CLONE=true start-herdr   # herdr takes positional arguments only
```

The agent then works on a git clone inside the sandbox. The tradeoff: using this option means your original project files drift from the sandbox project so you need to keep them in sync.

### Security findings

The workbench layers several controls to stop agents from reading secrets: instructions, a PreToolUse hook, permission deny rules, and an OS sandbox. The deny hook is listed under [Auto-installed tools, skills, and hooks](#auto-installed-tools-skills-and-hooks). Read more: [docs/research/secret-file-protection.md](docs/research/secret-file-protection.md).

### Terminal and IDE options

Ghostty opens automatically when installed. Override the terminal with `WORKSPACE_TERMINAL=wezterm`, `kitty`, `alacritty`, or `current`:

```shell
WORKSPACE_TERMINAL=current start-herdr
```

Optionally set `WORKSPACE_IDE_COMMAND` to tell what command to run to open a local IDE.

The default IDE command is `code`, to open Visual Studio Code. Set another installed command for a different IDE:

```shell
WORKSPACE_IDE_COMMAND=cursor start-claude
# or without opening:
OPEN_WORKSPACE_IN_IDE=0 start-claude
```

### Network policies

The launchers use Docker `sbx` in locked-down mode and add required network policies. Review the `allow_*_network` functions and [sandbox_bootstrap.sh](tools/agents/sandbox_bootstrap.sh), and remove connections you do not want to permit.

### Agent login notes

Each agent stores its login inside the reused local sandbox. For OpenCode with a provider, run `/connect`, select a provider (e.g. OpenRouter), paste the API key, then choose a model with `/models`.

### Hunk tips

Hunk runs without `--watch` by default. Press `r` in Hunk to reload the current changes. The `hunk-review` skill install is listed under [Auto-installed tools, skills, and hooks](#auto-installed-tools-skills-and-hooks).

## Cloud (AWS Bedrock AgentCore)

### Prerequisites

- [Docker Desktop](https://docs.docker.com/desktop/)
- An AWS Account and a IAM user with sufficient permissions.
- AWS CLI with credentials (run `aws configure`) for the target account and region.
- Node.js and npm.
- AgentCore CLI 0.24.1 or newer.
- A GitHub account with your project repo and a GitHub App installed for the target repository with **Contents: Read and write** permission.
- The GitHub App ID and private key stored in AWS Systems Manager Parameter Store.

See [Deploy AgentCore](./infra/aws/README.md) for GitHub App setup, Parameter Store, and stack deployment.

### Deploy AWS Resources for Bedrock AgentCore Use

AWS CDK is installed locally from the project's `/infra/aws` folder with `npm install`. Complete [Deploy AgentCore](./infra/aws/README.md) before the first cloud launch.

### Configure the environment

Before starting, copy the environment template from the project root:

```shell
cp .env.template .env
```

Edit `.env`. These two values are the only ones it needs:

```shell
GITHUB_REPOSITORY_URL=https://github.com/owner/repository.git
AWS_REGION=YOUR_AWS_REGION
```

#### GitHub App Tokens

Note: The GitHub App private key stays inside the a lambda function to get a token and never reaches the agent container. The container can only ask that function for an installation token, which GitHub expires in one hour and scopes to one repository. To limit which repositories the container may ask for, set `ALLOWED_REPOSITORIES` on the function to a comma-separated list of `owner/repository` values. Leave it unset to allow any repository the App is installed on.

#### GitHub Repos

To use AgentCore with another repository, change only `GITHUB_REPOSITORY_URL` in `.env`, then run `start-agentcore` normally. The GitHub App must be installed for the new repository.

### Start AgentCore

Choose the primary agent:

```shell
start-agentcore claude
start-agentcore codex
start-agentcore cursor
start-agentcore opencode
```

The argument selects the agent that starts automatically. All four agents and their Herdr integrations are available in the environment.

At the AgentCore shell prompt, run:

```shell
start-herdr
```

This opens the primary agent full-screen with Hunk in a hidden pane. To add another agent:

1. Press `Ctrl+B`, then `z` to show all panes.
2. Press `Ctrl+B`, then `v` to create a pane.
3. Run `claude`, `codex`, `cursor-agent`, or `opencode` in the new pane.

### Closing a empty pane in Herdr

- `Ctrl-B`, then `x`

### Second monitor

1. Open a terminal window on the other monitor and run `start-new-herdr-window`.
2. Press `Ctrl+B`, then `q`.
3. Run `herdr-pane`, then pick a pane by number. It fills that window on its own.

Both windows share one session. Closing this one leaves everything running.

This window is keyboard only. Mouse clicks do not work in the new window.

### Review with Hunk

1. In a pane (`Ctrl+B`, then `v`), run `hunk diff --agent-notes`. (optionally add `--watch`)
2. Put the cursor on a line and press `c` to leave a comment.
3. Tell the agent: `read my hunk comments and fix them`.`

See also the Hunk skill row in [Auto-installed tools, skills, and hooks](#auto-installed-tools-skills-and-hooks).

### Exit cleanly

1. Exit the coding agent with `/exit` or `Ctrl+D`.
2. Exit Herdr with `Ctrl+B`, then `q`.
3. Run `exit` at the AgentCore shell. A countdown appears on your own machine with three choices:
   - `s` stops the session and ends its billing.
   - `l` leaves it running so you can reconnect later.
   - `r` reconnects now.

   Doing nothing reconnects you, because a dropped connection looks the same as a deliberate exit. Press `s` when you are finished.

## Auto-installed tools, skills, and hooks

Launchers install the items below unless you remove the install steps from the scripts.

| Item | What it does | Local harnesses | AgentCore harnesses | Remove / change |
| --- | --- | --- | --- | --- |
| [Exa](https://exa.ai/) MCP / plugin | Web search and fetch for the agent | Claude, Codex, Cursor, Cline (and Claude again via `start-herdr`) | Claude, Codex, Cursor, OpenCode | Claude: `install_exa_tools` in `start_claude.sh` / `start_herdr.sh`; AgentCore: `bootstrap-repo.sh`. Codex: `install_exa_mcp_server` in `start_codex.sh`; AgentCore: `bootstrap-repo.sh`. Cursor/Cline: `tools/agents/cursor-mcp.json`, `tools/agents/cline-mcp-settings.json`. OpenCode: `tools/agents/opencode.json`. |
| [Matt Pocock skills](https://github.com/mattpocock/skills) | Engineering workflow skills (i.e. Wayfinder) | Claude (plugin), Codex, OpenCode, Cursor, Cline, Antigravity CLI, Pi | Claude (plugin), Codex, OpenCode, Cursor | Claude: `install_matt_pocock_skills_plugin` in `sandbox_bootstrap.sh` (and AgentCore `bootstrap-repo.sh`). Others: `install_matt_pocock_skills` / `install_skills` in the matching `start_*.sh`, or the Codex/OpenCode/Cursor block in `bootstrap-repo.sh`. |
| [Probity](https://github.com/nizos/probity) | Hooks that enforce TDD with the harness | Claude, Codex (also via `start-herdr`) | Claude, Codex | Package + config install: `install_probity` in `sandbox_bootstrap.sh`. Claude hook: `tools/agents/claude-settings.json`. Codex hooks: `tools/agents/codex-hooks.json` + `codex_hooks` in `codex-config.toml`. Config: `tools/agents/probity.config.ts` (hooks point at `/etc/agent-workbench/probity.config.ts`). AgentCore also installs the package in the Dockerfile. |
| Secret-file deny hook | Blocks agent reads of `.env` and related secret files | Claude (and Herdr when it installs Claude settings) | Claude | Hook binary + settings: `runtime/deny-protected-file-reads`, `tools/agents/claude-settings.json`, `runtime/install-claude-settings`. |
| [Hunk](https://www.hunk.dev/) review skill | Lets the agent open and act on Hunk diff review comments | Herdr local (`start-herdr`) | Claude, Codex, Cursor, OpenCode | `hunk skill path` symlink setup in `start_herdr.sh` / `bootstrap-repo.sh`. |

**Probity detail:** Hooks run on every matching tool call. The workbench config enables `enforceTdd()` for common source file types. You do not ask the agent to “use Probity.” To turn TDD enforcement off, remove or empty the Probity rules in `tools/agents/probity.config.ts`, or remove the Probity PreToolUse entries and `install_probity` calls. AgentCore needs `cd infra/aws && npm run deploy` after those changes.

**Not installed for every launcher:** Gemini, Grok, Kilo, and Command Code do not currently install Matt Pocock skills or Probity. OpenCode and Cursor do not support Probity (Probity only supports Claude Code, Codex, and GitHub Copilot CLI).

## Known Issues

- AgentCore session will suddenly exit or end. Cause is not determined, but probably has something to do with the 15 minute timeout for sessions currently set.
  - Update is in place to auto-reconnect - select `r` if prompted.
  - Resize the terminal window to redraw and resolve graphics glitches from the session interruption.
