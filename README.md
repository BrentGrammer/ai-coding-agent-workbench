# AI Coding Agent Workbench

This branch can install optional skills and tools with launcher flags. For the same project with those stripped out, use [`main`](https://github.com/BrentGrammer/ai-coding-agent-workbench/tree/main).

This project starts AI coding harnesses in Docker sandboxes or on one AWS EC2 workbench.

The launchers install no skills, MCP servers, plugins, helper CLIs, or custom prompts unless you pass a flag. Each harness uses its normal sign-in flow and default model unless you explicitly select the retained local-LLM path. Security controls remain enabled.

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

## Optional skills and tools

Off by default. Pass a flag to install that item in the sandbox. Flags compose. `--full` turns every item on.

```shell
start-claude --full
start-codex --exa --gh
start-herdr claude --full
```

| Flag | Installs |
| --- | --- |
| `--matt-pocock-skills` | Matt Pocock skills |
| `--skill-creator` | skill-creator |
| `--no-mistakes` | no-mistakes |
| `--exa` | Exa web search (where the harness supports it) |
| `--gh` | `gh` plus the login reminder |
| `--gh-axi` | gh-axi CLI and skill (also installs `gh`) |
| `--npm-axi` | npm-axi CLI and skill |
| `--full` | every item in this table |

`--gh`, `--gh-axi`, and `--npm-axi` need `gh auth login` once in each new sandbox. Choose HTTPS.

## Herdr

Herdr can start Claude Code, Codex, Cursor, or OpenCode:

```shell
start-herdr claude
start-herdr codex /path/to/project
start-herdr cursor
start-herdr opencode
```

Herdr installs only the selected harness unless you pass an optional-skills flag. It does not install Hunk or review skills.

## Local LLM

Runs an open model instead of a hosted API. Works with `start-opencode`, `start-pi`, `start-kilo` and `start-qwen`. Two targets, one flag each:

- **Mac** — `--local-model`. Local Ollama. No AWS, no cost, nothing to start first.
- **GPU box** — `--gpu-box`. Runs on AWS or DigitalOcean through Tailscale.

### Prerequisites

- **Local:** Ollama, `python3`, `jq`, and `ollama pull qwen3.8:27b-mlx`.
- **AWS GPU:** CDK bootstrapped, [4 Spot and On-Demand G-family vCPUs](docs/cloud-onetime-setup.md#5-gpu-quotas-local-llm-only), and an [ephemeral Tailscale key](docs/cloud-onetime-setup.md#7-gpu-auth-key).
- **DigitalOcean GPU:** Terraform, `doctl`, and the [one-time secrets setup](infra/digitalocean/README.md#one-time-setup).

### Run on a Mac

```shell
# run the model locally on your machine:
start-opencode --local-model
```

```shell
# run the local model using the AWS hosted GPU box:
start-opencode --gpu-box
```

```shell
start-pi --local-model
start-kilo --gpu-box
start-qwen --gpu-box
```

`--local-model` starts Ollama on loopback and serves `qwen3.8:27b-mlx`. No `workbench llm` command, and no env vars.

Where each harness reads the model, and what you do inside the sandbox:

| Launcher | Config file written | Inside the sandbox |
|---|---|---|
| `start-opencode` | `/etc/opencode/opencode.json` | already the default, nothing to do |
| `start-qwen` | `~/.qwen/settings.json` | already the default, no `/auth` |
| `start-kilo` | `~/.config/kilo/kilo.jsonc` | already the default, no `/connect` |
| `start-pi` | `~/.pi/agent/models.json` and `settings.json` | already the default, no `/login` |

Both flags add a `local-llm` provider and make it the default model. Nothing else changes: an OpenAI or OpenRouter model picked with `/model` still goes to that provider, and still needs its own login. The GPU box serves one model and cannot forward requests to anyone else.

Ollama and the proxy run on the host. A second run reuses them instead of starting more. To stop them:

```shell
stop-local-llm
```

It stops only what the launcher started and it deletes the logs and PID files in `~/.local/state/agent-workbench/`.

Defaults to `medium` thinking. Set it before the launcher command to override:

```shell
LOCAL_LLM_REASONING_EFFORT=low start-opencode --local-model
```

Values: `none`, `low`, `medium`, `high`. Applies to `start-opencode` and `start-pi`. Change it in a session with `Shift+Tab` in pi, or `/effort` in Qwen Code.

Thinking level reaches the model either way. Ollama's OpenAI-compatible route maps `reasoning_effort` onto its own `Think` field, so `none`, `low`, `medium` and `high` all land. Ollama turns thinking on by default when the field is absent. Its native `think` parameter does **not** work on this route — only `reasoning_effort` does.

Context length defaults to 131072 and follows `OLLAMA_CONTEXT_LENGTH` from the box. Override it with `LOCAL_LLM_CONTEXT_LENGTH` when the box runs a smaller context, or the harness sends prompts the server truncates.

### AWS GPU

`workbench llm up` / `status` / `down` deploy, check, and destroy the GPU box.

#### From a Mac

1. `workbench llm up` # 3-5 min
2. `workbench llm status` # confirm it is running
3. `start-opencode --gpu-box` # or start-pi --gpu-box
4. `workbench llm down` # when done

#### From the EC2 workbench box

1. `workbench llm up` # on your Mac — it is a CDK deploy
2. `workbench llm status` # confirm it is running
3. `start-workbench` # connect to the t4g box
4. `start-herdr opencode ~/some-repo --gpu-box` # on the t4g box
5. `workbench llm down` # back on your Mac, when done

- OpenCode only. start-herdr rejects --gpu-box for claude, codex, and cursor.
- One-time check on the t4g box: cat /etc/agent-workbench/workbench.env should show port 11435. If it shows 11434 or the line is missing, that box predates the proxy change and needs an EC2 stack redeploy.

Both paths: --gpu-box sets Qwen as the default model. Switch with /model and you are on the other provider that doesn't use the gpu box.

`workbench llm up` tries Spot capacity first. If AWS has no Spot capacity, the command clears the failed GPU stack and retries once with On-Demand capacity.

The default box is a `g6e.xlarge` (L40S, 48 GB VRAM) serving a 131,072-token context. Override both with env vars on `workbench llm up`:

```shell
WORKBENCH_LLM_INSTANCE_TYPE=g6.xlarge WORKBENCH_LLM_CONTEXT_LENGTH=32768 workbench llm up
```

The KV cache costs ~128 KB per token, so context must fit the card next to the ~15 GB of model weights: a 24 GB `g6.xlarge` caps near 48K, the 48 GB `g6e.xlarge` fits 131K with room to spare. The model cache is keyed by model tag, so switching instance types does not re-pull the model.

A rebuilt box has new SSH host keys, so `ssh agent-llm` refuses to connect. Run `workbench llm trust-host` once after a rebuild.

The box terminates itself about 70 minutes after the last prompt, and again on a 12-hour fuse. Ollama holds the model for 59 minutes so prompts stay fast within a session, and the idle check adds 10 minutes after it unloads. An idle GPU is the expensive mistake here, so the box is built to disappear: `workbench llm up` rebuilds it from the S3 model cache, and clears the dead stack first if the last box terminated itself.

`--local-model` runs the model on your Mac. `--gpu-box` runs it on the GPU box, which keeps the heat and the fans off your MacBook. The hostname, port, and model are built in, so there is nothing to type. Set `LOCAL_LLM_BASE_URL` or `LOCAL_LLM_MODEL` only if you want to override them.

The Docker sandbox routes to the tailnet but cannot resolve MagicDNS names, so the launcher looks `agent-llm` up on the host and puts its Tailscale address in the URL.

### DigitalOcean GPU

After the [one-time setup](infra/digitalocean/README.md#one-time-setup):

```shell
WORKBENCH_LLM_PROVIDER=digitalocean workbench llm up
start-opencode --gpu-box
WORKBENCH_LLM_PROVIDER=digitalocean workbench llm down
```

It serves the same model at `agent-llm:11435`; the launcher needs no other changes.

### Why port 11435

11435 is an inference-only proxy ([ollama_inference_proxy.py](tools/llm/ollama_inference_proxy.py)). Ollama stays on loopback: its port pulls models from any host a caller names, escaping the sandbox network policy.

If the Mac sandbox cannot reach the proxy, set `WORKBENCH_LLM_PROXY_BIND` to the Docker gateway address, not `0.0.0.0`.

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

The harnesses use their normal authentication and model defaults unless `--gpu-box` is selected for OpenCode. The cloud security design remains in place: no inbound security-group rules, Tailscale and SSM access, verified SSH host keys, short-lived repository-scoped GitHub tokens, IMDSv2 isolation, secret-read controls, and automatic idle shutdown.
