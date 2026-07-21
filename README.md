# AI Coding Agent Workbench

This project runs Claude Code, Codex, and OpenCode in [Herdr](https://herdr.dev/) using [Hunk](https://www.hunk.dev/). It supports running coding agents locally with `sbx` Docker sandbox MicroVMs and in the Cloud using [AWS Bedrock AgentCore](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/agentcore-get-started-cli.html).

It bootstraps an isolated multi-agent coding workbench running in the Cloud, with options for running a variety of other coding agents locally in Docker sandboxes.

Docker Sandboxes include sbx policies for opening connections for Ubuntu/system updates and each model provider's API routes. Review and adjust these in the scripts as needed (find `sbx policy allow network...` entries).
The agents also come baked in with [Matt Pocock's skills](https://github.com/mattpocock/skills) (remove their installation in the scripts if not desired).

The project supports running a variety of harnesses individually locally inside a Docker Sandbox, or using Herdr with 3 harnesses baked in (Claude Code, Codex and OpenCode).

Note: CLAUDE.md and AGENTS.md are fine-tuned to a personal workflow (the owner of this repo, of course). Adjust and edit these files to your needs and preferences. Also review the dot files (`.claude/, .codex/`, etc.) which contain some baked in settings for convenience (statusline content, accept all edits mode, etc.) and change any of them to your liking.

## Platform support

- macOS is supported.
- Linux and WSL2 are not yet verified.
- Windows is not currently supported.

## Prerequisites

For local Docker sandboxes:

- [Docker Desktop](https://docs.docker.com/desktop/)
- [Docker Sandboxes (`sbx`)](https://docs.docker.com/ai/sandboxes/get-started/) installed, signed in, and configured for locked-down mode.
- (Recommended) A terminal with OSC 52 clipboard support, such as Ghostty.
- Login credentials or an API key for the coding agent you plan to use.

Node.js, Herdr, Hunk, and the coding-agent CLIs are installed inside the sandbox by the launchers. An IDE is optional.

For [AWS Bedrock AgentCore](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/agentcore-get-started-cli.html):

- [Docker Desktop](https://docs.docker.com/desktop/)
- AWS CLI with credentials for the target account and region.
- Node.js and npm.
- AgentCore CLI 0.24.1 or newer.
- A GitHub App installed for the target repository with **Contents: Read and write** permission.
- The GitHub App ID and private key stored in AWS Systems Manager Parameter Store.

### Deploy the CDK Stack for AgentCore (if using the Herdr setup in the Cloud)

AWS CDK is installed locally from the project's `/infra/aws` folder with `npm install`. Complete [Deploy AgentCore](./infra/aws/README.md) before the first cloud launch.

## Add the agent launcher commands to PATH (Recommended)

To run the launchers which bootstrap coding agents on your machine in Docker Sandbox instead of in the Cloud, convenience commands are included with this project in the bin folder.

Run the installer once to add the commands to PATH:

```shell
./bin/install-commands
```

It checks for command collisions, confirms the profile change, and creates a backup. To select another profile:

```shell
# Optional: override auto detection of profile:
./bin/install-commands --profile /path/to/profile
```

## Configure the environment

Before starting, copy the environment template from the project root:

```shell
cp .env.template .env
```

Edit `.env` and fill in every value:

```shell
GITHUB_REPOSITORY_URL=https://github.com/owner/repository.git
AWS_REGION=YOUR_AWS_REGION
GITHUB_APP_ID_PARAMETER_NAME=/coding-agent-workbench/github/app-id
GITHUB_APP_PRIVATE_KEY_PARAMETER_NAME=/coding-agent-workbench/github/private-key
```

The two Parameter Store names must match exactly in `.env`, AWS Systems Manager Parameter Store, and `infra/aws/lib/workbench-runtime-stack.ts`. If you change the CDK constants, redeploy the stack.

To use AgentCore with another repository, change only `GITHUB_REPOSITORY_URL` in `.env`, then run `start-agentcore` normally. The GitHub App must be installed for the new repository.

## Start AgentCore

Choose the primary agent:

```shell
start-agentcore claude
start-agentcore codex
start-agentcore opencode
```

The argument selects the agent that starts automatically. All three agents and their Herdr integrations are available in the environment.

At the AgentCore shell prompt, run:

```shell
start-herdr
```

This opens the primary agent full-screen with Hunk in a hidden pane. To add another agent:

1. Press `Ctrl+B`, then `z` to show all panes.
2. Press `Ctrl+B`, then `v` to create a pane.
3. Run `claude`, `codex`, or `opencode` in the new pane.

To exit cleanly:

1. Exit the coding agent with `/exit` or `Ctrl+D`.
2. Exit Herdr with `Ctrl+B`, then `q`.
3. Run `exit` at the AgentCore shell to stop the temporary environment and return to the local terminal.

## Local setup

(Make sure you've added the bin folder to the PATH)
Run from the project you want to work on. Claude starts by default:

```shell
cd /path/to/local-project-folder
start-herdr
```

Choose another primary agent or project:

```shell
start-herdr codex
start-herdr claude /path/to/another-project
```

Run one agent without Herdr:

```shell
start-claude
start-codex /path/to/another-project
start-opencode
```

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

Each command uses the current directory unless a project path is passed. Sandboxes are reused by project so logins persist.

Ghostty opens automatically when installed. Override the terminal with `WORKSPACE_TERMINAL=wezterm`, `kitty`, `alacritty`, or `current`:

```shell
WORKSPACE_TERMINAL=current start-herdr
```

The launchers use Docker `sbx` in locked-down mode and add required network policies. Review the `allow_*_network` functions and [sandbox_bootstrap.sh](tools/agents/sandbox_bootstrap.sh), and remove connections you do not want to permit.

Set `WORKSPACE_IDE_COMMAND` to another IDE command. If that command is unavailable, the workspace opens without an IDE.

The default IDE command is `code`, the Visual Studio Code command-line launcher. Set another installed command for a different IDE, or use `OPEN_WORKSPACE_IN_IDE=0` to open no IDE:

```shell
WORKSPACE_IDE_COMMAND=cursor start-claude
OPEN_WORKSPACE_IN_IDE=0 start-claude
```

Each agent stores its login inside the reused local sandbox. For OpenCode with OpenRouter, run `/connect`, select OpenRouter, paste the API key, then choose a model with `/models`.

Hunk runs without `--watch`. Press `r` in Hunk to reload the current changes, or run this from the agent pane:

```shell
hunk session reload --repo . -- diff
```
