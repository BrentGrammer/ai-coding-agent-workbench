# AI Coding Agent Workbench

This project sets up and bootstraps an environment for running AI coding harnesses in Docker sandboxes or on an AWS EC2 dev box.

**This branch installs ALL optional skills and tools by default.** Pass a flag such as `--exa` to install only that tool and not others.

For the same project with tooling and skills stripped out, use [`main`](https://github.com/BrentGrammer/ai-coding-agent-workbench/tree/main).

- [Requirements](#requirements)
- [Install the commands](#install-the-commands)
- [Start a harness](#start-a-harness)
- [Keep secrets out with `--clone`](#keep-secrets-out-with---clone)
- [Optional skills and tools](#optional-skills-and-tools)
- [Project instruction files](#project-instruction-files)
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

## Optional skills and tools

**No skill or tool flags means every item in the table is installed.**

Pass one or more of the flags below to install only those items.

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
| `--no-mistakes`        | no-mistakes                                    |
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

## Herdr

Herdr can start Claude Code, Codex, Cursor, or OpenCode:

```shell
start-herdr claude
start-herdr codex /path/to/project
start-herdr cursor
start-herdr opencode
```

Herdr installs only the selected harness. It takes the same skill and tool flags as the other launchers. With OpenCode it can also read from a [GPU box](docs/local-llm.md#run-on-an-aws-gpu-box).

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
