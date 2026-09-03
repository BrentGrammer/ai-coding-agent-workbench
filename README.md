# AI Coding Agent Workbench

This project sets up and bootstraps an environment for running AI coding harnesses in Docker sandboxes or on an AWS EC2 dev box.

**This branch installs ALL [optional skills and tools](#optional-skills-and-tools) by default.** Pass a flag such as `--exa` to install only that tool and not others.

For the same project with tooling and skills stripped out, use [`main`](https://github.com/BrentGrammer/ai-coding-agent-workbench/tree/main).

Two ways to run:

- [Local: Docker sandbox on macOS or Omarchy](#local-docker-sandbox-on-macos-or-omarchy) — one sandbox per project, on your own machine, with no cloud account.
- [Cloud: AWS EC2 dev box](#cloud-aws-ec2-dev-box) — one persistent instance you connect to over Tailscale.

Either way, [Herdr](#herdr) can start the harness for you, and you can [use a local model instead](#use-a-local-model-instead) of a hosted API.

## Install the commands

Both ways start here.

(Recommended) This installs convenience launcher commands into your PATH and profile. It checks for collisions, makes a backup of your profile and adds the commands to your `PATH`:

Run:

```shell
./bin/install-commands
```

## Local: Docker sandbox on macOS or Omarchy

### Requirements

- macOS with [Docker Desktop](https://docs.docker.com/desktop/), or an Omarchy host following the [Omarchy setup guide](docs/omarchy.md)
- [Docker Sandboxes (`sbx`)](https://docs.docker.com/ai/sandboxes/get-started/) installed, signed in, and configured for locked-down mode
- Login credentials or an API key for the coding agent you plan to use
- (Recommended) A terminal with OSC 52 clipboard support, such as Ghostty or Alacritty

Node.js and the coding-agent CLIs are installed inside the sandbox by the launchers, so the host does not need them. An IDE is optional. Host Docker and the isolated Docker Engine inside each sandbox are separate.

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
start-devin
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

The AWS setup creates one persistent EC2 instance, a `t4g.large` reached over Tailscale with mosh. It installs Herdr, four harnesses (Claude Code, Codex, Cursor, Devin, Pi and OpenCode), and all skills and tools by default.

### Requirements

- An AWS account, with credentials configured locally and permission to deploy CDK stacks
- A [Tailscale](https://tailscale.com/) account. The free personal plan is enough
- A GitHub account that can create a GitHub App. The app supplies the short-lived repository tokens, and you create it in [Cloud one-time setup](docs/cloud-onetime-setup.md#2-github-app)
- Node.js on the machine you deploy from
- Local connection tools:
  - macOS: `brew install mosh awscli`, plus the Tailscale app from [tailscale.com/download](https://tailscale.com/download) or `brew install --cask tailscale`
  - Omarchy: follow the [AWS connection setup](docs/omarchy.md#aws-workbench-connection)
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

Herdr can start a harness in a local sandbox or on the EC2 box:

```shell
start-herdr claude
start-herdr codex /path/to/project
start-herdr cursor
start-herdr opencode
start-herdr devin
start-herdr pi
```

Herdr installs only the selected harness. It takes the same skill and tool flags as the other launchers.

## Optional skills and tools

**No skill or tool flags means every item in the table is installed.**

On local launchers, pass one or more of the flags below to install only those items. On the EC2 cloud workbench, **all items in the table are installed** globally during machine setup.

NOTE: `--clone`, `--local-model`, and `--gpu-box` are not skill or tool flags, so will still install all tools unless a skill/tool flag is provided.

```shell
# every optional skill and tool
start-claude

# Exa and gh only
start-codex --exa --gh

# Exa only (Herdr uses the same rule)
start-herdr claude --exa
```

| Flag                   | Installs                                       |
| ---------------------- | ---------------------------------------------- |
| `--matt-pocock-skills` | Matt Pocock skills                             |
| `--skill-creator`      | skill-creator                                  |
| `--pstack-skills`      | PStack skills (unslop)                         |
| `--exa`                | Exa web search (where the harness supports it) |
| `--gh`                 | `gh` plus the login reminder                   |
| `--gh-axi`             | gh-axi CLI and skill (also installs `gh`)      |
| `--npm-axi`            | npm-axi CLI and skill                          |
| `--full`               | every item in this table                       |

`--gh`, `--gh-axi`, and `--npm-axi` need `gh auth login` once in each new sandbox. Choose HTTPS.

## Project instruction files

When you start a launcher on a project that is missing AGENTS/CLAUDE.md, it asks if it should copy the missing files into that project.

1. Copy the missing files once.
2. Copy the missing files and remember this choice for this project.
3. Do not copy this time.
4. Do not copy and remember this choice for this project.

Show the choice again after you remembered it:

```shell
start-codex --prompt-instruction-copy
start-codex --prompt-instruction-copy /path/to/project
```

## Use a local model instead

Runs an open model instead of a hosted API. Works with `start-opencode`, `start-pi`, `start-kilo` and `start-qwen`. Two targets, one flag each:

- **macOS or Linux** — `--local-model`. Local Ollama with `qwen3.8:27b-mlx` on macOS or `qwen3.8:27b` on Linux.
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
