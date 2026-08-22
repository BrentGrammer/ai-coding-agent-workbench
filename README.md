# AI Coding Agent Workbench

This project sets up and bootstraps an environment for running AI coding harnesses in Docker sandboxes or on an AWS EC2 dev box.

This branch is the minimalist barebones project and has optional skills and tools stripped out. For the same project with flags to install some useful tools and skills, use [`optional-skills-tools`](https://github.com/BrentGrammer/ai-coding-agent-workbench/tree/optional-skills-tools).

Two ways to run:

- [Local: Docker sandbox on your Mac](#local-docker-sandbox-on-your-mac) — one sandbox per project, on your own machine, with no cloud account.
- [Cloud: AWS EC2 dev box](#cloud-aws-ec2-dev-box) — one persistent instance you connect to over Tailscale.

Either way, [Herdr](#herdr) can start the harness for you, and you can [use a local model instead](#use-a-local-model-instead) of a hosted API.

## Install the commands

Both ways start here.

(Recommended) This installs convenience launcher commands into your PATH and profile. It checks for collisions, makes a backup of your profile and adds the commands to your `PATH`:

Run:

```shell
./bin/install-commands
```

## Local: Docker sandbox on your Mac

### Requirements

- macOS
- [Docker Desktop](https://docs.docker.com/desktop/)
- [Docker Sandboxes (`sbx`)](https://docs.docker.com/ai/sandboxes/get-started/) installed, signed in, and configured for locked-down mode
- Login credentials or an API key for the coding agent you plan to use
- (Recommended) A terminal with OSC 52 clipboard support, such as Ghostty

Node.js and the coding-agent CLIs are installed inside the sandbox by the launchers, so the host does not need them. An IDE is optional.

### Start a harness

Run a launcher from the project that the harness must edit:

```shell
start-claude
start-codex
start-cursor
start-opencode
```

Other launchers are available:

```shell
start-antigravity
start-cline
start-commandcode
start-grok
start-junie
start-kilo
start-pi
start-qwen
```

Pass one project path when the current directory is not the target:

```shell
start-codex /path/to/project
```

Each command creates or reuses one sandbox, installs the harness, and starts it. Complete the harness's normal sign-in flow when requested.

The project directory is mounted into the sandbox by default. Claude Code, Codex, Cursor, and OpenCode receive the repository's secret-read protections.

### Keep secrets out with `--clone`

Research: [Protecting secrets from coding agents](docs/research/secret-file-protection.md) — the layers that stop a harness reading `.env`, and how to verify them.

For any harness, use `--clone` to keep ignored files and local secrets outside the sandbox:

```shell
start-codex --clone /path/to/project
```

The clone contains committed files only. Commit the work that the harness must see before you start it. A separate sandbox name prevents a cloned launch from reusing a live-mount sandbox.

Use `--clone` for Cline, Cursor, Antigravity, Grok, Junie, Kilo, Pi, Qwen, and Command Code. Their own ignore rules are defense-in-depth, not a complete read barrier.

### Remove old sandboxes

Launchers leave sandboxes on disk after you exit. Remove every stopped sandbox and keep the ones that are still running:

```shell
sbx rm $(sbx ls | awk '$3=="stopped"{print $1}')
```

## Cloud: AWS EC2 dev box

The AWS setup creates one persistent EC2 instance, a `t4g.large` reached over Tailscale with mosh. It installs Herdr and four harnesses: Claude Code, Codex, Cursor, and OpenCode.

### Requirements

- An AWS account, with credentials configured locally and permission to deploy CDK stacks
- A [Tailscale](https://tailscale.com/) account. The free personal plan is enough
- A GitHub account that can create a GitHub App. The app supplies the short-lived repository tokens, and you create it in [Cloud one-time setup](docs/cloud-onetime-setup.md#2-github-app)
- Node.js on the machine you deploy from
- Local tools: `brew install mosh awscli`, and the Tailscale macOS app from [tailscale.com/download](https://tailscale.com/download) or `brew install --cask tailscale`
- Login credentials or an API key for each coding agent you plan to use
- (Recommended) A terminal with OSC 52 clipboard support, such as Ghostty

### Deploy

Do the [cloud one-time setup](docs/cloud-onetime-setup.md) first: Tailscale access, the GitHub App, and the SSM parameters. Then see [infra/aws/README.md](infra/aws/README.md) for deployment instructions.

### Connect and run

Connect to the instance:

```shell
start-workbench
```

Then run a harness in a repository:

```shell
cd ~/workspace/project
start-herdr codex
```

The harnesses use their normal authentication and model defaults unless `--gpu-box` is selected for OpenCode. See [Local LLM](docs/local-llm.md#from-the-ec2-workbench-box) for that path.

### Security

The cloud security design remains in place: no inbound security-group rules, Tailscale and SSM access, verified SSH host keys, short-lived repository-scoped GitHub tokens, IMDSv2 isolation, secret-read controls, and automatic idle shutdown.

## Herdr

Herdr can start Claude Code, Codex, Cursor, or OpenCode, in a sandbox on your Mac or on the EC2 box:

```shell
start-herdr claude
start-herdr codex /path/to/project
start-herdr cursor
start-herdr opencode
```

Herdr installs only the selected harness. It does not install Hunk or review skills.

## Use a local model instead

Runs an open model instead of a hosted API. Works with `start-opencode`, `start-pi`, `start-kilo` and `start-qwen`. Two targets, one flag each:

- **Mac** — `--local-model`. Local Ollama. No AWS, no cost, nothing to start first.
- **GPU box** — `--gpu-box`. Runs on AWS or DigitalOcean through Tailscale.

```shell
start-opencode --local-model
start-opencode --gpu-box
```

Full guide: [Local LLM](docs/local-llm.md) — prerequisites, the GPU box lifecycle and its cost controls, thinking level, and context length.

## Reference

- [Protecting secrets from coding agents](docs/research/secret-file-protection.md) — the layers that stop a harness reading `.env`, and how to verify them.
- [Cloud one-time setup](docs/cloud-onetime-setup.md) — Tailscale, GitHub App, and GPU quotas.
- [AWS stack](infra/aws/README.md) — CDK deployment of the EC2 box and the GitHub token Lambda.
- [DigitalOcean GPU](infra/digitalocean/README.md) — Terraform GPU droplet for the local LLM.
