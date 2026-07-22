# AI Coding Agent Workbench

This project bootstraps Claude Code, Codex, and OpenCode in [Herdr](https://herdr.dev/) using [Hunk](https://www.hunk.dev/) in the Cloud. It also supports running coding agents locally with `sbx` Docker sandbox MicroVMs for a variety of harnesses.

Docker Sandboxes include sbx policies for opening connections for Ubuntu/system updates and each model provider's API routes. Review and adjust these in the scripts as needed (find `sbx policy allow network...` entries).
The agents also come baked in with [Matt Pocock's skills](https://github.com/mattpocock/skills) (remove their installation in the scripts if not desired).

Note: CLAUDE.md and AGENTS.md are fine-tuned to a personal workflow (the owner of this repo, of course). Adjust and edit these files to your needs and preferences. Also review the dot files (`.claude/, .codex/`, etc.) which contain some baked in settings for convenience (statusline content, accept all edits mode, etc.) and change any of them to your liking.

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

Node.js, Herdr, Hunk, and the coding-agent CLIs are installed inside the sandbox by the launchers. An IDE is optional.

### Start locally

Run from the project you want to work on:

```shell
cd /path/to/local-project-folder
start-herdr claude
```

Choose another primary agent or project:

```shell
start-herdr codex
start-herdr opencode /path/to/another-project
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

Hunk runs without `--watch` by default. Press `r` in Hunk to reload the current changes.

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

Edit `.env` and fill in every value:

```shell
GITHUB_REPOSITORY_URL=https://github.com/owner/repository.git
AWS_REGION=YOUR_AWS_REGION
GITHUB_APP_ID_PARAMETER_NAME=/coding-agent-workbench/github/app-id
GITHUB_APP_PRIVATE_KEY_PARAMETER_NAME=/coding-agent-workbench/github/private-key
```

The two Parameter Store names must match exactly in `.env`, AWS Systems Manager Parameter Store, and `infra/aws/lib/workbench-runtime-stack.ts`. If you change the CDK constants, redeploy the stack.

To use AgentCore with another repository, change only `GITHUB_REPOSITORY_URL` in `.env`, then run `start-agentcore` normally. The GitHub App must be installed for the new repository.

### Start AgentCore

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

### Exit cleanly

1. Exit the coding agent with `/exit` or `Ctrl+D`.
2. Exit Herdr with `Ctrl+B`, then `q`.
3. Run `exit` at the AgentCore shell to stop the temporary environment and return to the local terminal.
