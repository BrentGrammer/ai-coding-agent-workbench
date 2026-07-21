# AI Coding Agent Workbench

This project runs Claude Code, Codex, and OpenCode in [Herdr](https://herdr.dev/) using [Hunk](https://www.hunk.dev/). It supports running coding agents locally with `sbx` Docker sandbox MicroVMs and in the Cloud using [AWS Bedrock AgentCore](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/agentcore-get-started-cli.html).

It bootstraps an isolated multi-agent coding workbench running in the Cloud, with options for running a variety of other coding agents locally in Docker sandboxes.

Docker Sandboxes include sbx policies for opening connections for Ubuntu/system updates and each model provider's API routes. Review and adjust these in the scripts as needed (find `sbx policy allow network...` entries).
The agents also come baked in with [Matt Pocock's skills](https://github.com/mattpocock/skills) (remove their installation in the scripts if not desired).

The project supports running a variety of harnesses individually locally inside a Docker Sandbox, or using Herdr with 3 harnesses baked in (Claude Code, Codex and OpenCode).

Note: CLAUDE.md and AGENTS.md are fine-tuned to a personal workflow (the owner of this repo, of course). Adjust and edit these files to your needs and preferences. Also review the dot files which contain some baked in settings for convenience (statusline content, accept all edits modes, etc.) and change any of them to your liking.

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

AWS CDK is installed locally from the project's `/infra/aws` folder with `npm install`. Complete [Deploy AgentCore](#deploy-agentcore) before the first cloud launch.

### Install AWS Bedrock AgentCore locally

```shell
npm install -g @aws/agentcore@latest
```

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

## Create the GitHub App

One GitHub App provides scalable repository access without maintaining a permanent token for each repository.

1. Open GitHub **Settings → Developer settings → GitHub Apps → New GitHub App**.
2. Give the app a unique name and use an appropriate GitHub page as its homepage URL.
3. Disable **Active** under Webhook because this workbench does not receive webhooks.
4. Under Repository permissions, set **Contents** to **Read and write**.
5. Leave callback URLs, user authorization, device flow, post-installation setup, and the IP allow list unset.
6. Create the app and note its **App ID**.
7. Generate and download a private key. Do not generate or store a client secret because this workbench does not use OAuth.
8. If macOS offers to import the PEM file into Keychain, cancel the import.
9. Choose **Install App** and install it on the personal account or organizations containing the target repositories.
10. Choose **All repositories** for current and future repositories, or maintain an explicit selected list.

The app generates repository-limited installation tokens when Git needs them. Tokens expire after one hour and refresh automatically on later Git operations.

## Store the GitHub App configuration

Create these parameters in AWS Systems Manager Parameter Store in the same region as the AgentCore runtime:

| Parameter                                    | Type           | Value                    |
| -------------------------------------------- | -------------- | ------------------------ |
| `/coding-agent-workbench/github/app-id`      | `String`       | GitHub App ID            |
| `/coding-agent-workbench/github/private-key` | `SecureString` | Complete PEM private key |

The AWS console is the simplest way to store the multiline private key. Do not commit it, put it in an environment file, or paste it into logs.

These parameters are required before the first repository launch, but not before stack deployment.

## Deploy AgentCore

```shell
cd infra/aws
npm install
```

If this account and region have not been bootstrapped for CDK, run this once before deployment:

```shell
npx cdk bootstrap
```

Deploy the stack:

```shell
npm run deploy
```

The deploy command:

- Builds and publishes the ARM64 runtime image.
- Deploys the AgentCore runtime.

If the deploying identity will not open workbench sessions, attach the `AgentCoreShellCallerPolicyArn` stack output to the trusted IAM user or role that will.

## Manage AgentCore sessions

Use the lower-level command to select a repository, branch, or persistent session at launch:

```shell
workbench aws https://github.com/owner/repo.git --agent codex
```

`--keep NAME` preserves the checkout and agent home for later use:

```shell
workbench aws https://github.com/owner/repo.git \
  --ref main \
  --agent claude \
  --keep repo-claude
```

Reconnect, stop, or check active AgentCore runtime sessions:

```shell
workbench aws reconnect repo-claude
workbench aws stop repo-claude
workbench aws status
```

Named sessions preserve the checkout and agent home in AgentCore managed session storage. Complete each agent's normal login the first time it runs in a named session.

The AgentCore CLI reconnects the same shell automatically across the one-hour WebSocket cutoff and transient network interruptions. AgentCore shuts down idle compute after 15 minutes and caps each compute lifetime at eight hours. Persistent files remain available to the same named session.

## Cost controls

This section is a convenience checklist, not authoritative billing guidance and could contain incorrect information. Verify current pricing, limits, and billable resources in the official AWS documentation and the AWS billing console before relying on it.

- No Lambda microVM, VPC, NAT gateway, load balancer, EFS, database, AgentCore Memory, Gateway, alarm, or dashboard is created.
- AgentCore runtime billing is usage-based.
- Idle runtime compute stops after 15 minutes.
- Runtime compute has an eight-hour maximum lifetime.
- CloudWatch logs retain one day.
- Deployment keeps one tracked workbench image and removes older tracked images.
- `workbench aws status` checks whether AgentCore reports active runtime sessions.

AWS implementation details are in [infra/aws/README.md](infra/aws/README.md).
