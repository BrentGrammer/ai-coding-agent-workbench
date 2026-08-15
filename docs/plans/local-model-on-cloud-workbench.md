# Use the GPU box from the Cloud Workbench

## Goal

Let `opencode` on the EC2 t4g workbench box use the Qwen model on the GPU box.

Today `workbench llm up` deploys the GPU box and it serves the model. Nothing on the
workbench box points an agent at it. This plan closes that gap.

## Scope

In scope:

- The native path on the EC2 box: `start-herdr` -> `herdr-session` -> `herdr` -> `opencode`.
- `opencode` only.

Out of scope, deferred (see [Follow-up work](#follow-up-work)):

- `pi` on the EC2 box.
- Driving the GPU box from a Mac over Tailscale.
- `--local-model` for the Mac `start-herdr`.

## Background

### The two paths

There are two separate ways an agent starts, and only one of them supports a local model.

**Mac path.** `bin/start-opencode` -> `tools/agents/start_opencode.sh`. It runs
`opencode` inside a Docker sandbox. `--local-model` works here. The launcher writes the
provider into the sandbox file `/etc/opencode/opencode.json`
(`start_opencode.sh:133-152`) and allowlists the sandbox network
(`local_llm.sh:68-89`).

**Cloud path.** `infra/aws/ec2/start-herdr` -> `runtime/herdr-session` ->
`herdr` -> `runtime/workbench-pane-shell` -> the agent binary. There is no Docker and
no sandbox. The agent uses the host network. This path has no `--local-model`.

### What already works

- The GPU box serves the model. `infra/aws/ec2/setup-llm.sh` installs the driver and
  Ollama, and runs an inference-only proxy on port 11435.
- The proxy is reachable from the workbench box over the tailnet, at the hostname
  `agent-llm`. No allowlist change is needed, because the agent is not sandboxed on
  this box.
- `workbench llm up` / `status` / `down` deploy, check, and destroy the GPU box.
- The endpoint values are already in the environment. `setup-workbench.sh:32-35`
  writes them into `/etc/agent-workbench/workbench.env`:

  ```
  LOCAL_LLM_BASE_URL=http://agent-llm:11435/v1
  LOCAL_LLM_MODEL=qwen3.8:27b
  ```

  `infra/aws/ec2/agent-workbench-profile.sh:15-19` sources and exports that file, so
  every ssh login shell has the values. `start-herdr` inherits them.

### What is missing

Nothing acts on those values. `start-herdr` has no flag, and the `opencode` config on
the box has no local provider. The seeded config
(`setup-workbench.sh:222-224`, from `tools/agents/opencode.json`) pins
`"model": "openrouter/deepseek/deepseek-v4-pro"` and declares no `provider` block.

`opencode` cannot take a custom provider from environment variables alone. The
provider must be in a config file.

### How to inject without breaking the user's config

The seeded config is written once and never overwritten, on purpose, so the user can
change the model. Writing the provider into that file at launch time would clobber
their edits.

`opencode` supports layered config. Later layers win, and layers are **merged, not
replaced** — only conflicting keys are overridden:

```
~/.config/opencode/opencode.json   (global, the seeded file)
  -> $OPENCODE_CONFIG              (a file path)
  -> ./opencode.json               (project)
  -> $OPENCODE_CONFIG_CONTENT      (inline JSON)
  -> /etc/opencode/                (managed)
```

So `OPENCODE_CONFIG_CONTENT` can add the provider and override `.model` for one
session, and the user's permissions, MCP, and watcher blocks survive untouched.

Source: <https://opencode.ai/docs/config/>

## Step 0 — Verify on the box before you write code

The config layering above comes from the current `opencode` docs. The box pins
`OPENCODE_VERSION=1.18.11` (`setup-workbench.sh:12`). Confirm the behaviour before
building on it.

SSH to the workbench box and run these three checks.

1. **Does 1.18.11 honour `OPENCODE_CONFIG_CONTENT`?**

   ```shell
   OPENCODE_CONFIG_CONTENT='{"model":"local-llm/qwen3.8:27b"}' opencode
   ```

   Open `/models` and confirm the active model changed. If it did not, use
   `OPENCODE_CONFIG` with a temp file instead. Write that file under the session dir
   `herdr-session` already creates: `/tmp/agent-workbench/herdr-$WORKBENCH_SESSION`.

2. **Does the merge keep the user's keys?**

   With the same command, confirm the `permission` and `mcp` blocks from the global
   config are still in effect. If the layer replaces instead of merges, fall back to a
   jq merge of the full global config into a temp file.

3. **Does the variable reach a herdr pane?**

   ```shell
   FOO=bar start-herdr opencode ~/some-repo
   ```

   In the agent pane, run `printenv FOO`. `runtime/workbench-pane-shell:20` unsets
   `XDG_CONFIG_HOME` and `XDG_STATE_HOME` and touches nothing else, so this should
   pass. If it does not, `start-herdr` must write a file and pass only the path, or
   `workbench-pane-shell` must set the variable itself.

Record the result of each check in the pull request. The steps below assume all three
pass.

## Step 1 — Move the provider JSON into a shared function

`tools/agents/start_opencode.sh:133-148` already builds the provider block with `jq`.
Do not write a second copy.

In `tools/agents/local_llm.sh`, add a function that prints the JSON fragment to
stdout. It reads `LOCAL_LLM_BASE_URL`, `LOCAL_LLM_MODEL`, and
`LOCAL_LLM_REASONING_EFFORT`, and produces the same shape as today:

```json
{
  "model": "local-llm/<model>",
  "provider": {
    "local-llm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Local LLM",
      "options": { "baseURL": "<url>", "apiKey": "ollama" },
      "models": { "<model>": { "name": "<model>", "options": { "reasoningEffort": "<effort>" } } }
    }
  }
}
```

Then change `start_opencode.sh:133-148` to call the function and merge its output into
the template, so the Mac path and the cloud path stay identical.

Keep the existing comment at `start_opencode.sh:129-132` about model-level `options`
being dropped for custom providers. It still applies.

**Files:** `tools/agents/local_llm.sh`, `tools/agents/start_opencode.sh`

## Step 2 — Install the shared script on the box

`setup-workbench.sh:129-151` does not copy `local_llm.sh`. Add it:

```shell
install -m 755 "$REPO_DIR/tools/agents/local_llm.sh" /usr/local/lib/agent-workbench/local_llm.sh
```

`local_llm.sh` is sourced, not run, so a library path is the right home. Also install
`tools/agents/opencode.json` to `/etc/agent-workbench/opencode.json` if Step 0 check 2
failed and the fallback needs the template at runtime.

**Files:** `infra/aws/ec2/setup-workbench.sh`

## Step 3 — Add `--local-model` to the cloud `start-herdr`

In `infra/aws/ec2/start-herdr`:

1. Parse `--local-model` into a flag. Keep the existing positional arguments
   (`[agent] [workspace-dir]`) working as they do now.
2. Reject the flag for any agent other than `opencode`, with a clear message. The
   other agents are not wired yet.
3. When the flag is set:
   - Source `/usr/local/lib/agent-workbench/local_llm.sh` and call `resolve_local_llm`.
     That function already reads `workbench.env` (`local_llm.sh:51-56`) and already
     skips the Ollama start when the URL is not `host.docker.internal`
     (`local_llm.sh:61-64`). Reuse it as-is.
   - Build the JSON with the Step 1 function.
   - `export OPENCODE_CONFIG_CONTENT="$json"`.
   - Print the model and URL, as `start_opencode.sh:216` does.
4. Update the `--help` text at `start-herdr:4-8`.

Do not touch `runtime/herdr-session` or `runtime/workbench-pane-shell`. They pass the
environment through.

**Files:** `infra/aws/ec2/start-herdr`

## Step 4 — Stop `workbench.env` being truncated

`infra/aws/lib/workbench-ec2-stack.ts:68` writes the file with `printf ... > file`.
That truncates. `setup-workbench.sh:32-35` appends the two `LOCAL_LLM_*` lines
afterwards. If user-data re-runs without `setup-workbench.sh`, the endpoint config is
silently lost and `--local-model` points nowhere.

Fix by writing the two lines in the CDK `printf` alongside `AWS_REGION` and
`GITHUB_APP_TOKEN_FUNCTION_NAME`. Keep the idempotent `grep -q ... ||` appends in
`setup-workbench.sh` as the safety net for boxes already running.

**Files:** `infra/aws/lib/workbench-ec2-stack.ts`

## Step 5 — Test end to end

1. `workbench llm up`, and wait for the GPU box to report ready.
2. From the workbench box, confirm the endpoint answers:

   ```shell
   curl -s http://agent-llm:11435/v1/models
   ```

3. `start-herdr opencode ~/some-repo --local-model`.
4. In the agent pane, run `/models` and confirm `local-llm` is the active provider.
5. Send a prompt. Confirm a reply comes back.
6. Confirm the user's config survived: `/help` shows the Exa MCP server, and reading a
   `.env` file is still denied.
7. `workbench llm down`.

## Step 6 — Update the README

`README.md:245-248` says the GPU box is deploy and destroy only. Replace the first
bullet with the working `start-herdr --local-model` usage. Keep the second bullet, the
untested Mac path, until that work lands.

**Files:** `README.md`

## Follow-up work

Not in this plan. Listed in priority order.

1. **Drive the GPU box from a Mac over Tailscale.** This is the higher-value item. The
   goal is to move inference off the MacBook, because running Qwen locally makes it hot
   and loud. The blocker is unproven: the Docker sandbox must reach the Tailscale
   hostname `agent-llm` from inside its VM. Test
   `LOCAL_LLM_BASE_URL=http://agent-llm:11435/v1 start-opencode --local-model` first,
   then fix what breaks. Steps 1 and 4 of this plan make that work smaller.
2. **`--local-model` for the Mac `start-herdr`.** `tools/agents/start_herdr.sh:192`
   installs the plain template and has no flag. Once Step 1 lands, this is small.
3. **`pi` on the EC2 box.** More than an npm install. `runtime/workbench-pane-shell:23-50`
   accepts only `codex`, `claude`, `opencode`, and `cursor`, and passes the name to
   `herdr agent start --kind`. Herdr must know the kind.
