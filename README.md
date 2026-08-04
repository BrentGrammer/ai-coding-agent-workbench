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

The cloud implementation is a persistent EC2 instance (t4g.large, Ubuntu 24.04 ARM64) reached via Tailscale and mosh. The box stops itself after 15 minutes with no client connected. Deploy instructions are in [infra/aws/README.md](./infra/aws/README.md).

### Prerequisites

- An AWS account, with credentials configured locally and permission to deploy CDK stacks.
- A [Tailscale](https://tailscale.com/) account. The free personal plan is enough.
- A GitHub account that can create a GitHub App. The app supplies the short-lived repository tokens. You create it in [One-time setup](#one-time-setup).
- Node.js on the machine you deploy from.
- Local tools: 
  - `brew install mosh awscli` 
  - Tailscale macOS app from either [tailscale.com/download](https://tailscale.com/download) or `brew install --cask tailscale`.
- (Recommended) A terminal with OSC 52 clipboard support, such as Ghostty.
- Login credentials or an API key for each coding agent you plan to use.

### Daily flow

```shell
start-workbench          # starts the box if stopped, connects with mosh
cd ~/workspace/<your-repo>
start-herdr [agent]      # claude (default) | codex | opencode | cursor
```

Note: Mosh survives Wi-Fi drops and laptop sleep. The box stops itself when you disconnect for 15+ minutes.

`workbench ec2 <command>` covers the rest. `start-workbench` already does `up` then `mosh`, so you only need these when you want one part on its own:

- `up` — Starts the box and waits until it runs. Use it to warm the box up before you connect.
- `down` — Stops the box now, instead of waiting for the 15-minute idle timer. A stopped box bills only its disk.
- `status` — Prints the state, instance type, start time, and public IP in a table. Use it to check whether the box is running.
- `ssh` — Opens a shell over Tailscale. Use it for a short command, or when mosh acts up.
- `mosh` — Opens a shell over Tailscale that survives Wi-Fi drops and laptop sleep. This is the normal way to connect.
- `ssm` — Opens a shell through AWS Systems Manager instead of Tailscale. This is the break-glass path for when the box is not on the tailnet. It needs `session-manager-plugin` installed locally.
- `update` — Pulls this repo on the box and re-runs the setup script. See [Updates](#updates).

`ssh`, `mosh`, and `update` find the box by its tailnet hostname. Override the host with `WORKBENCH_EC2_HOST` and the login user with `WORKBENCH_EC2_USER`.

### One-time setup

The deploy reads three secrets from AWS Systems Manager Parameter Store: a Tailscale auth key, and a GitHub App ID and private key. Create them before you deploy following Steps 1 and 2 below.

#### 1. Tailscale access

1. Sign in to the Tailscale app on your local machine.
2. In the Tailscale admin console, open **Access controls**. Add a tag for the workbench, a grant that lets your devices reach the workbench, and an SSH rule for the tag:

   ```json
   "tagOwners": { "tag:workbench": ["autogroup:admin"] },
   "grants": [
     { "src": ["autogroup:member"], "dst": ["autogroup:self", "tag:workbench"], "ip": ["*"] }
   ],
   "ssh": [
     { "action": "accept", "src": ["autogroup:member"], "dst": ["tag:workbench"], "users": ["ubuntu", "root"] }
   ]
   ```

   The `ssh` rule is required. The default rule that Tailscale ships covers only your own untagged devices, and the workbench is tagged. If your policy file still has the default allow-all grant (`"src": ["*"], "dst": ["*"]`), remove it.

3. In **Settings → Keys**, create an auth key: **Reusable**, **Pre-approved**, tag `tag:workbench`, make sure it is not marked as ephemeral.

4. If tailnet lock is on, sign the key on a trusted machine (your laptop) and keep the signed key that this command prints:

   ```shell
   tailscale lock sign tskey-auth-...
   ```

5. Store the key that's printed in the terminal after the above command:

   ```shell
   aws ssm put-parameter --type SecureString \
     --name /coding-agent-workbench/tailscale/auth-key \
     --value 'tskey-auth-...'
   ```

An auth key expires after 90 days. That only matters when you rebuild the box after the key expires. Repeat steps 3 to 5 to refresh it.

#### 2. GitHub App

One GitHub App gives repository access without a permanent token for each repository. The box never holds the private key. It can only call the token Lambda, which returns a one-hour token for one repository.

1. Open GitHub **Settings → Developer settings → GitHub Apps → New GitHub App**.
2. Give the app a unique name and use an appropriate GitHub page as its homepage URL.
3. Disable **Active** under Webhook, because this workbench does not receive webhooks.
4. Under Repository permissions, set **Contents** to **Read and write**.
5. Leave callback URLs, user authorization, device flow, post-installation setup, and the IP allow list unset.
6. Create the app and note its **App ID**.
7. Generate and download a private key. Do not generate a client secret, because this workbench does not use OAuth. If macOS offers to import the PEM file into Keychain, cancel the import.
8. Choose **Install App** and install it on the account or organization that holds your repositories. Choose **All repositories**, or keep an explicit selected list.
9. Store both values:

   ```shell
   aws ssm put-parameter --type String \
     --name /coding-agent-workbench/github/app-id \
     --value '<app-id>'

   aws ssm put-parameter --type SecureString \
     --name /coding-agent-workbench/github/private-key \
     --value file://path/to/private-key.pem
   ```

Do not commit the PEM key, put it in an environment file, or paste it into logs. Delete the downloaded file after you store it.

#### 3. Deploy and connect

1. Deploy the stacks — see [infra/aws/README.md](./infra/aws/README.md).
2. Wait 3 to 5 minutes after the deploy. The box joins your tailnet by itself on first boot, using the auth key from Parameter Store.

   If SSH fails with `tailnet policy does not permit you to SSH to this node`, the box joined and your policy file is missing the `ssh` rule from step 1. Add it and retry. If the box never appears on the tailnet, get in with `workbench ec2 ssm` and run `sudo tailscale up --ssh`.
3. In a local terminal, from any directory, run `start-workbench` to connect. Then log in each agent once on the box: `claude`, `codex`, `opencode auth login`, `cursor-agent login`.
4. Set the git identity once on the box: `git config --global user.name` / `user.email`.
5. Clone your repositories on the box, using the HTTPS URL:

   ```shell
   mkdir -p ~/workspace
   git clone https://github.com/<owner>/<repo>.git ~/workspace/<repo>
   ```

   No credential prompt appears — the box mints a short-lived GitHub token for each Git operation via the AWS Lambda setup in CDK. This only works for HTTPS URLs, not `git@github.com:...` SSH ones.
6. Run `workbench ec2 update` once from a local terminal. The first-boot setup ran before any agent was logged in, so the skill and plugin installs that need a logged-in agent were skipped. This run completes them.

#### 4. Recommended hardening

Do these in order:

1. Confirm MFA on the account behind your Tailscale login (GitHub or Google). The tailnet is only as strong as that account.
2. Enable [tailnet lock](https://tailscale.com/kb/1226/tailnet-lock) so a compromised Tailscale control server cannot add a rogue device. Print each device's key with `tailscale lock` (on the Mac the CLI lives at `/Applications/Tailscale.app/Contents/MacOS/Tailscale`). Then, on the box, pass both `tlpub:` keys to one command: `sudo tailscale lock init tlpub:BOX-KEY tlpub:MAC-KEY`. Store the printed disablement secrets somewhere durable outside both devices — an SSM SecureString parameter works well. They are the only recovery if both devices are lost.
3. Keep the tailnet single-user: no invites, no shared nodes. Tailscale SSH means tailnet membership is shell access to the box.
4. Adding a future device needs a signature from a trusted one: `tailscale lock sign <nodekey>`.

### Updates

- The agent CLIs update themselves on the box.
- `workbench ec2 update` updates everything else: it pulls this repo on the box and re-runs the idempotent setup script (Herdr and Hunk pins, configs, skills, plugins). Run it when this repo changed in a way that affects the box — a config edit, a version pin bump, a new skill — or as a repair step when something on the box looks broken, since the script rewrites its files to a known-good state. If the repo has not changed, there is nothing for it to do.
- OS security patches: the box runs Ubuntu's `unattended-upgrades` service (enabled by the setup script), which checks daily on a systemd timer and installs security updates automatically. No action needed.

## Herdr tips

### Closing a empty pane in Herdr

- `Ctrl-B`, then `x`

### Review with Hunk

1. In a pane (`Ctrl+B`, then `v`), run `hunk diff --agent-notes`. (optionally add `--watch`)
2. Put the cursor on a line and press `c` to leave a comment.
3. Tell the agent: `read my hunk comments and fix them`.`

See also the Hunk skill row in [Auto-installed tools, skills, and hooks](#auto-installed-tools-skills-and-hooks).

### Exit cleanly

1. Exit the coding agent with `/exit` or `Ctrl+D`.
2. Exit Herdr with `Ctrl+B`, then `q`.

### Troubleshooting

If you see `error: nested herdr is disabled by default`:

1. Run `herdr server stop`.
2. Reconnect to the EC2 box.
3. Run `cd ~/workspace/<your-repo>`.
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
