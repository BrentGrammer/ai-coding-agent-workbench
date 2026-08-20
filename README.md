# AI Coding Agent Workbench

This project starts AI coding harnesses in Docker sandboxes or on one AWS EC2 workbench.

The launchers install no skills, MCP servers, plugins, helper CLIs, custom prompts, or custom model settings. Each harness uses its normal sign-in flow and default model. Security controls remain enabled.

## Local use

Requirements:

- macOS
- Docker Desktop
- Docker Sandboxes (`sbx`)
- Login access or an API key for the selected harness

Add the launcher commands to `PATH`:

```shell
./bin/install-commands
```

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

Herdr installs only the selected harness. It does not install Hunk or review skills.

## AWS workbench

The AWS setup creates one persistent EC2 instance. It installs Herdr and four harnesses: Claude Code, Codex, Cursor, and OpenCode.

See [infra/aws/README.md](infra/aws/README.md) for deployment instructions.

Connect to the instance:

```shell
start-workbench
```

Then run a harness in a repository:

```shell
cd ~/workspace/project
start-herdr codex
```

The harnesses use their normal authentication and model defaults. The cloud security design remains in place: no inbound security-group rules, Tailscale and SSM access, verified SSH host keys, short-lived repository-scoped GitHub tokens, IMDSv2 isolation, secret-read controls, and automatic idle shutdown.
