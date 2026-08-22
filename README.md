# AI Coding Agent Workbench

This project sets up and bootstraps an environment for running AI coding harnesses in Docker sandboxes or on an AWS EC2 dev box.

This branch is the minimalist barebones project and has optional skills and tools stripped out. For the same project with flags to install some useful tools and skills, use [`optional-skills-tools`](https://github.com/BrentGrammer/ai-coding-agent-workbench/tree/optional-skills-tools).

## Install the commands

(Recommended) This installs convenience launcher commands into your PATH and profile. It checks for collisions, makes a backup of your profile and adds the commands to your `PATH`:

Run:

```shell
./bin/install-commands
```

## Guides

| Guide                                      | What it covers                                                              |
| ------------------------------------------ | --------------------------------------------------------------------------- |
| [Local sandboxes](docs/local-sandboxes.md) | Run a harness on your Mac, in a Docker sandbox.                             |
| [Cloud workbench](docs/cloud-workbench.md) | Run a harness on a persistent AWS EC2 dev box.                              |
| [Local LLM](docs/local-llm.md)             | Serve a local open model instead using Ollama, on your Mac or on a GPU box. |
| [Herdr](docs/herdr.md)                     | Start Claude Code, Codex, Cursor, or OpenCode through Herdr.                |

## Reference

- [Cloud one-time setup](docs/cloud-onetime-setup.md) — Tailscale, GitHub App, and GPU quotas.
- [AWS stack](infra/aws/README.md) — CDK deployment of the EC2 box and the GitHub token Lambda.
- [DigitalOcean GPU](infra/digitalocean/README.md) — Terraform GPU droplet for the local LLM.
