# Local sandboxes

Run a harness on your Mac, inside a Docker sandbox, on one project directory.

- [Requirements](#requirements)
- [Install](#install)
- [Start a harness](#start-a-harness)
- [Keep secrets out with `--clone`](#keep-secrets-out-with---clone)
- [Remove old sandboxes](#remove-old-sandboxes)

Related: [Herdr](herdr.md) starts one of four harnesses through Herdr. [Local LLM](local-llm.md) replaces the hosted API with an open model.

## Requirements

- macOS
- Docker Desktop
- Docker Sandboxes (`sbx`)
- Login access or an API key for the selected harness

## Install

Add the launcher commands to `PATH`:

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

For any harness, use `--clone` to keep ignored files and local secrets outside the sandbox:

```shell
start-codex --clone /path/to/project
```

The clone contains committed files only. Commit the work that the harness must see before you start it. A separate sandbox name prevents a cloned launch from reusing a live-mount sandbox.

Use `--clone` for Cline, Cursor, Antigravity, Grok, Junie, Kilo, Pi, Qwen, and Command Code. Their own ignore rules are defense-in-depth, not a complete read barrier.

## Remove old sandboxes

Launchers leave sandboxes on disk after you exit. Remove every stopped sandbox and keep the ones that are still running:

```shell
sbx rm $(sbx ls | awk '$3=="stopped"{print $1}')
```
