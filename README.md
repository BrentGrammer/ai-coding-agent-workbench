# AI Coding Agent Workbench

This project sets up and bootstraps an environment for running AI coding harnesses in Docker sandboxes or on an AWS EC2 dev box.

This branch is the minimalist barebones project and has optional skills and tools stripped out. For the same project with flags to install some useful tools and skills, use [`optional-skills-tools`](https://github.com/BrentGrammer/ai-coding-agent-workbench/tree/optional-skills-tools).

- [Requirements](#requirements)
- [Install the commands](#install-the-commands)
- [Start a harness](#start-a-harness)
- [Keep secrets out with `--clone`](#keep-secrets-out-with---clone)
- [Herdr](#herdr)
- [Remove old sandboxes](#remove-old-sandboxes)

Two setups have their own guide:

- [Local LLM](docs/local-llm.md) — serve a local open model with Ollama instead, on your Mac or on a GPU box.
- [Cloud workbench](docs/cloud-workbench.md) — run a harness on a persistent AWS EC2 dev box.

## Requirements

- macOS
- Docker Desktop
- Docker Sandboxes (`sbx`)
- Login access or an API key for the selected harness

## Install the commands

(Recommended) This installs convenience launcher commands into your PATH and profile. It checks for collisions, makes a backup of your profile and adds the commands to your `PATH`:

Run:

```shell
./bin/install-commands
```

## Start a harness

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

## Keep secrets out with `--clone`

Research: [Protecting secrets from coding agents](docs/research/secret-file-protection.md) — the layers that stop a harness reading `.env`, and how to verify them.

For any harness, use `--clone` to keep ignored files and local secrets outside the sandbox:

```shell
start-codex --clone /path/to/project
```

The clone contains committed files only. Commit the work that the harness must see before you start it. A separate sandbox name prevents a cloned launch from reusing a live-mount sandbox.

Use `--clone` for Cline, Cursor, Antigravity, Grok, Junie, Kilo, Pi, Qwen, and Command Code. Their own ignore rules are defense-in-depth, not a complete read barrier.

## Herdr

Herdr can start Claude Code, Codex, Cursor, or OpenCode:

```shell
start-herdr claude
start-herdr codex /path/to/project
start-herdr cursor
start-herdr opencode
```

Herdr installs only the selected harness. It does not install Hunk or review skills. With OpenCode it can also read from a [GPU box](docs/local-llm.md#run-on-an-aws-gpu-box).

## Remove old sandboxes

Launchers leave sandboxes on disk after you exit. Remove every stopped sandbox and keep the ones that are still running:

```shell
sbx rm $(sbx ls | awk '$3=="stopped"{print $1}')
```

## Reference

- [Protecting secrets from coding agents](docs/research/secret-file-protection.md) — the layers that stop a harness reading `.env`, and how to verify them.
- [Cloud one-time setup](docs/cloud-onetime-setup.md) — Tailscale, GitHub App, and GPU quotas.
- [AWS stack](infra/aws/README.md) — CDK deployment of the EC2 box and the GitHub token Lambda.
- [DigitalOcean GPU](infra/digitalocean/README.md) — Terraform GPU droplet for the local LLM.
