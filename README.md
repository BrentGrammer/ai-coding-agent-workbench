# AI Coding Agent Workbench

This project runs coding agents two ways:

- **Local** — `sbx` Docker sandbox MicroVMs for a variety of harnesses, with [Herdr](https://herdr.dev/) as an option. See [Local Docker sandboxes](#local-docker-sandboxes).
- **Cloud** — a persistent AWS EC2 dev box running Claude Code, Codex, Cursor CLI, and OpenCode in Herdr, with [Hunk](https://www.hunk.dev/) for diff review. See [Cloud](#cloud).

Docker Sandboxes include sbx policies for opening connections for Ubuntu/system updates and each model provider's API routes. Review and adjust these in the scripts as needed (find `sbx policy allow network...` entries).

Launchers also auto-install skills, MCP tools, and hooks for some harnesses. See [Auto-installed tools, skills, and hooks](#auto-installed-tools-skills-and-hooks) for the full list and how to remove them.

Note: CLAUDE.md and AGENTS.md are fine-tuned to a personal workflow (the owner of this repo, of course). Adjust and edit these files to your needs and preferences. Also review the dot files (`.gemini/, .cline/`, and files in the `/tools/agents/` folder: `codex-config.toml`, `claude-settings.json`, `cursor-mcp.json`, `opencode.json`, `cline-global-settings.json`, etc.) which contain some baked in settings for convenience (statusline content, accept all edits mode, etc.) and change any of them to your liking.

## Platform support

- macOS is supported.
- Linux and WSL2 are not yet verified.
- Windows is not currently supported.

## Install launcher commands (PATH)

Convenience commands in the `bin` folder bootstrap local Docker sandbox agents (`start-herdr`, `start-claude`, and others).

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
start-junie
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

`readonly/CONVENTIONS.md` and `readonly/REACT_INSTRUCTIONS.md` are optional convenience files. You can copy them into a project when needed.

### `--clone`: keep secrets out of the sandbox

Launchers mount the live folder, so a real `.env` is readable by the agent. Some of the harnesses have sufficient protection, but some do not and `--clone` is recommended for:

**Recommended: Use `--clone` with these:** `start-cline`, `start-cursor`, `start-antigravity`, `start-gemini`, `start-grok`, `start-junie`, `start-kilo`, `start-pi`, `start-commandcode`. None of them can block a secret read.

**Skip it with these:** `start-claude`, `start-opencode`, `start-codex`. All three block secret reads on their own.

```shell
start-cursor --clone
SANDBOX_CLONE=true start-herdr   # herdr takes positional arguments only
```

The agent then works on a git clone inside the sandbox. The tradeoff: using this option means original project files drift from the sandbox project so you need to keep them in sync.

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

## Cloud

The cloud implementation is a persistent EC2 instance (t4g.large, Ubuntu 24.04 ARM64) reached via Tailscale and mosh. The box stops itself after 15 minutes with no client connected. Deploy instructions are in [infra/aws/README.md](./infra/aws/README.md).

### Prerequisites

- An AWS account, with credentials configured locally and permission to deploy CDK stacks.
- A [Tailscale](https://tailscale.com/) account. The free personal plan is enough.
- A GitHub account that can create a GitHub App. The app supplies the short-lived repository tokens. You create it in [Cloud one-time setup](docs/cloud-onetime-setup.md#2-github-app).
- Node.js on the machine you deploy from.
- Local tools: 
  - `brew install mosh awscli` 
  - Tailscale macOS app from either [tailscale.com/download](https://tailscale.com/download) or `brew install --cask tailscale`.
- (Recommended) A terminal with OSC 52 clipboard support, such as Ghostty.
- Login credentials or an API key for each coding agent you plan to use.

### Daily flow

```shell
start-workbench          # starts the box if stopped, connects with mosh
cd ~/workspace/<repo>
start-herdr [agent]      # cursor (default) | claude | codex | opencode
```

Note: Mosh survives Wi-Fi drops and laptop sleep. The box stops itself when you disconnect for 15+ minutes.

`workbench ec2 <command>` covers the rest. `start-workbench` already does `up` then `mosh`, so you only need these when you want one part on its own:

- `up` — Starts the box and waits until it runs. Use it to warm the box up before you connect.
- `down` — Stops the box now, instead of waiting for the 15-minute idle timer. A stopped box bills only its disk.
- `status` — Prints the state, instance type, start time, and public IP in a table. Use it to check whether the box is running.
- `ssh` — Opens a shell over Tailscale. Use it for a short command, or when mosh acts up.
- `mosh` — Opens a shell over Tailscale that survives Wi-Fi drops and laptop sleep. This is the normal way to connect.
- `ssm` — Opens a shell through AWS Systems Manager instead of Tailscale. This is the break-glass path for when the box is not on the tailnet. It needs `session-manager-plugin` installed locally.
- `update` — Pulls this repo on the box and re-runs the setup script. See [Updates and maintenance](#updates-and-maintenance).

`ssh`, `mosh`, and `update` find the box by its tailnet hostname. Override the host with `WORKBENCH_EC2_HOST` and the login user with `WORKBENCH_EC2_USER`.

### One-time setup

Do this once before the first deploy: [docs/cloud-onetime-setup.md](docs/cloud-onetime-setup.md) covers Tailscale access, the GitHub App, deploy and connect, hardening, and the GPU spot quota.

## Local LLM

Runs an open model instead of a hosted API. Two targets, same launcher flag:

- **Mac** — local Ollama. No AWS, no cost, nothing to start first.
- **GPU box** — an optional spot GPU instance in the cloud, managed with `workbench llm`.

### Prerequisites

- On Mac host (Local only): [Ollama](https://ollama.com/download), `python3`, and `jq` on the host.
- On Mac host (Local only): the model pulled once with `ollama pull qwen3.8:27b-mlx`.
- GPU box: a reusable Tailscale auth key at `/coding-agent-workbench/tailscale/llm-auth-key`, created and signed the same way as [Tailscale access](docs/cloud-onetime-setup.md#1-tailscale-access).
- GPU box: the [GPU spot quota](docs/cloud-onetime-setup.md#5-gpu-spot-quota-local-llm-only) raised, before the first `workbench llm up`.

### Run on a Mac

```shell
start-opencode --local-model
```

Starts Ollama on loopback and serves `qwen3.8:27b-mlx`. No `workbench llm` command, and no env vars.

Inside the sandbox, `opencode` already defaults to the local model by updating `/etc/opencode/opencode.json` — no `/connect` needed.

Ollama and the proxy run on the host. A second run reuses them instead of starting more. To stop them:

```shell
stop-local-llm
```

It stops only what the launcher started and it deletes the logs and PID files in `~/.local/state/agent-workbench/`.

### Run on the GPU box

```shell
workbench llm up               # from anywhere with AWS credentials
start-workbench                # connect to the workbench box
start-opencode --local-model   # on the box
workbench llm down             # when you are done
```

- `up` — Deploys the GPU box. It serves `qwen3.8:27b` at `http://agent-llm:11435/v1`.
- `status` — Shows whether you left it on.
- `down` — Destroys the GPU box. The S3 model cache stays.

The workbench box already points at the GPU box, reading `LOCAL_LLM_BASE_URL` and `LOCAL_LLM_MODEL` from `/etc/agent-workbench/workbench.env` after `workbench ec2 update`. To drive the GPU box from a Mac instead, set `LOCAL_LLM_BASE_URL=http://agent-llm:11435/v1`.

### Why port 11435

11435 is an inference-only proxy ([ollama_inference_proxy.py](tools/llm/ollama_inference_proxy.py)). Ollama stays on loopback: its port pulls models from any host a caller names, escaping the sandbox network policy.

If the Mac sandbox cannot reach the proxy, set `WORKBENCH_LLM_PROXY_BIND` to the Docker gateway address, not `0.0.0.0`.

## Herdr tips

### Closing a empty pane in Herdr

- `Ctrl-B`, then `x`

### Review with Hunk

1. In a pane (`Ctrl+B`, then `v`), run `hunk diff --agent-notes`. (optionally add `--watch`)
2. Put the cursor on a line and press `c` to leave a comment.
3. Tell the agent: `read my hunk comments and fix them`.

Hunk runs without `--watch` by default. Press `r` to reload the current changes. The `hunk-review` skill install is listed under [Auto-installed tools, skills, and hooks](#auto-installed-tools-skills-and-hooks).

### Exit cleanly

1. Exit the coding agent with `/exit` or `Ctrl+D`.
2. Exit Herdr with `Ctrl+B`, then `q`.

### Troubleshooting

If you see `error: nested herdr is disabled by default`:

1. Run `herdr server stop`.
2. Reconnect to the EC2 box.
3. Run `cd ~/workspace/<repo>`.
4. Run `start-herdr`.

## Auto-installed tools, skills, and hooks

Launchers install the items below unless you remove the install steps from the scripts.

| Item | What it does | Where | Remove / change |
| --- | --- | --- | --- |
| [Exa](https://exa.ai/) MCP / plugin | Web search and fetch | Claude, Codex, Cursor, Cline, Herdr | `install_exa_tools` / agent MCP configs |
| [Matt Pocock skills](https://github.com/mattpocock/skills) | Workflow skills (e.g. Wayfinder) | Claude (plugin), Codex, OpenCode, Cursor, Cline, Antigravity, Pi, Grok, Kilo, Command Code, Herdr | `install_matt_pocock_skills(_plugin)` in `sandbox_bootstrap.sh` / `start_*.sh` |
| [gh-axi](https://github.com/kunchenguid/gh-axi) | Agent-friendly `gh` wrapper (TOON output) | EC2 | `setup-workbench.sh` npm pin + skills/hooks |
| [npm-axi](https://github.com/SSBrouhard/npm-axi) | Agent-friendly npm registry CLI | EC2 | `setup-workbench.sh` npm pin + skills/hooks |
| [skill-creator](https://github.com/anthropics/skills/tree/main/skills/skill-creator) | Create and refine agent skills | EC2 + local agents above (not Gemini) | `install_skill_creator` / `setup-workbench.sh` |
| [no-mistakes](https://github.com/kunchenguid/no-mistakes) | Validate/ship gate before push/PR/CI | EC2 + local agents above (not Gemini) | `install_no_mistakes` / `setup-workbench.sh` |
| Secret-file deny hook | Blocks reads of `.env` and related files | Claude, Herdr | `runtime/deny-protected-file-reads`, `claude-settings.json` |
| [Hunk](https://www.hunk.dev/) review skill | Act on Hunk diff review comments | Herdr (local + EC2) | `hunk skill path` symlink in setup / `start_herdr.sh` |

## Updates and maintenance

- The agent CLIs update themselves on the box.
- `workbench ec2 update` updates everything else: it pulls this repo on the box and re-runs the idempotent setup script (Herdr and Hunk pins, configs, skills, plugins). Run it when this repo changed in a way that affects the box — a config edit, a version pin bump, a new skill — or as a repair step when something on the box looks broken, since the script rewrites its files to a known-good state. If the repo has not changed, there is nothing for it to do.
- OS security patches: the box runs Ubuntu's `unattended-upgrades` service (enabled by the setup script), which checks daily on a systemd timer and installs security updates automatically. No action needed.
- Docker disk cleanup: monthly, run `docker system prune -f` on the box. Rebuilding images leaves orphaned layers and build cache behind and prune clears them without touching named volumes or running containers. Check usage anytime with `docker system df`.
