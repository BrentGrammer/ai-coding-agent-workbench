# AI Coding Agent Workbench

This project runs coding agents locally with `sbx` Docker sandbox MicroVMs for a variety of harnesses, with Claude Code, Codex, Cursor CLI and OpenCode in [Herdr](https://herdr.dev/) using [Hunk](https://www.hunk.dev/). A cloud seat on EC2 is planned in [issue #20](https://github.com/BrentGrammer/ai-coding-agent-workbench/issues/20).

Docker Sandboxes include sbx policies for opening connections for Ubuntu/system updates and each model provider's API routes. Review and adjust these in the scripts as needed (find `sbx policy allow network...` entries).

Launchers also auto-install skills, MCP tools, and hooks for some harnesses. See [Auto-installed tools, skills, and hooks](#auto-installed-tools-skills-and-hooks) for the full list and how to remove them.

Note: CLAUDE.md and AGENTS.md are fine-tuned to a personal workflow (the owner of this repo, of course). Adjust and edit these files to your needs and preferences. Also review the dot files (`.gemini/, .cline/`, and files in the `/tools/agents/` folder: `codex-config.toml`, `claude-settings.json`, `cursor-mcp.json`, `opencode.json`, `cline-global-settings.json`, etc.) which contain some baked in settings for convenience (statusline content, accept all edits mode, etc.) and change any of them to your liking.

## Choose a path

- **Local Docker sandboxes** — run agents on your machine with `sbx`. See [Local Docker sandboxes](#local-docker-sandboxes).
- **Cloud** — a persistent EC2 instance reached over Tailscale and mosh. See [Cloud](#cloud).

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

## Cloud

The cloud seat is a persistent EC2 instance (t4g.large, Ubuntu 24.04 ARM64) reached over Tailscale and mosh. State persists on its disk: agent logins, skills, repos, and `node_modules` survive every stop and start. The box stops itself after 15 minutes with no client connected, and a stopped box bills only its disk (~$2.40/month). Deploy instructions are in [infra/aws/README.md](./infra/aws/README.md).

### Daily flow

```shell
start-workbench          # starts the box if stopped, connects with mosh
cd ~/workspace/<your-repo>
workbench-open [agent]   # claude (default) | codex | opencode | cursor
```

Work, then walk away. mosh survives Wi-Fi drops and laptop sleep. The box stops itself when you disconnect for 15+ minutes.

`workbench ec2 <command>` covers the rest: `up`, `down`, `status`, `ssh`, `mosh`, `ssm` (break-glass access without Tailscale), and `update`.

### One-time setup (new Mac or new instance)

1. Mac tools: `brew install mosh awscli && brew install --cask tailscale session-manager-plugin`, plus AWS credentials configured.
2. Tailscale: create a free account, sign in to the Mac app.
3. Deploy the stacks — see [infra/aws/README.md](./infra/aws/README.md).
4. Join the box to your tailnet: `workbench ec2 ssm`, then on the box `sudo tailscale up --ssh`, approve the link in the browser, `exit`.
5. Connect with `start-workbench`, then log in each agent once on the box: `claude`, `codex`, `opencode auth login`, `cursor-agent login`.
6. Set the git identity once on the box: `git config --global user.name` / `user.email` (use the GitHub noreply address).
7. Run `workbench ec2 update` from the Mac so skill and plugin installs that need agent logins complete.
8. Recommended hardening, in this order:
   - Confirm MFA on the account behind your Tailscale login (GitHub or Google). The tailnet is only as strong as that account.
   - Enable [tailnet lock](https://tailscale.com/kb/1226/tailnet-lock) so a compromised Tailscale control server cannot add a rogue device. Print each device's key with `tailscale lock` (on the Mac the CLI lives at `/Applications/Tailscale.app/Contents/MacOS/Tailscale`). Then, on the box, pass both `tlpub:` keys to one command: `sudo tailscale lock init tlpub:BOX-KEY tlpub:MAC-KEY`. Store the printed disablement secrets somewhere durable outside both devices — an SSM SecureString parameter works well. They are the only recovery if both devices are lost.
   - Keep the tailnet single-user: no invites, no shared nodes. Tailscale SSH means tailnet membership is shell access to the box.
   - Adding a future device needs a signature from a trusted one: `tailscale lock sign <nodekey>`.

### Rebuilding the box

The one-time setup above is the full rebuild procedure — everything else is automated by the deploy and the setup script. Two gotchas:

- The old disk survives termination on purpose. Delete the orphaned EBS volume in the console, or it bills ~$2.40/month forever.
- Agent logins, git identity, and repos lived on that disk. Redo steps 4–7 and re-clone your repos.

### Updates

- The agent CLIs update themselves on the box.
- `workbench ec2 update` updates everything else: it pulls this repo on the box and re-runs the idempotent setup script (Herdr and Hunk pins, configs, skills, plugins). Run it when you feel like it.
- Ubuntu security patches install unattended.

### Cloud troubleshooting

- **Garbled characters when typing over mosh:** the CLI already forces `TERM=xterm-256color` because Ghostty's terminal type is unknown on the box and its keyboard protocol garbles mosh. If you connect manually, do the same.
- **Box stopped while you were away:** by design. `start-workbench` brings it back with everything intact.
- **Tailscale broken or box unreachable:** `workbench ec2 ssm` is the always-available back door; it needs only AWS credentials.
- **mosh stopped connecting after months of working:** the Tailscale node key expires every 180 days. Renew it over the back door: `workbench ec2 ssm`, then `sudo tailscale up --ssh`. To never see this, disable key expiry for the box in the Tailscale admin console (Machines → the box → Disable key expiry).
- **GitHub pushes fail:** the token relay logs are on the box: `systemctl status github-token-relay`.

## Herdr tips

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

## Auto-installed tools, skills, and hooks

Launchers install the items below unless you remove the install steps from the scripts.

| Item | What it does | Local harnesses | Remove / change |
| --- | --- | --- | --- |
| [Exa](https://exa.ai/) MCP / plugin | Web search and fetch for the agent | Claude, Codex, Cursor, Cline (and Claude again via `start-herdr`) | Claude: `install_exa_tools` in `start_claude.sh` / `start_herdr.sh`. Codex: `install_exa_mcp_server` in `start_codex.sh`. Cursor/Cline: `tools/agents/cursor-mcp.json`, `tools/agents/cline-mcp-settings.json`. OpenCode: `tools/agents/opencode.json`. |
| [Matt Pocock skills](https://github.com/mattpocock/skills) | Engineering workflow skills (i.e. Wayfinder) | Claude (plugin), Codex, OpenCode, Cursor, Cline, Antigravity CLI, Pi | Claude: `install_matt_pocock_skills_plugin` in `sandbox_bootstrap.sh`. Others: `install_matt_pocock_skills` / `install_skills` in the matching `start_*.sh`. |
| Secret-file deny hook | Blocks agent reads of `.env` and related secret files | Claude (and Herdr when it installs Claude settings) | Hook binary + settings: `runtime/deny-protected-file-reads`, `tools/agents/claude-settings.json`, `runtime/install-claude-settings`. |
| [Hunk](https://www.hunk.dev/) review skill | Lets the agent open and act on Hunk diff review comments | Herdr local (`start-herdr`) | `hunk skill path` symlink setup in `start_herdr.sh` (Codex also via `~/.agents/skills`). |

**Not installed for every launcher:** Gemini, Grok, Kilo, and Command Code do not currently install Matt Pocock skills.
