# Use the GPU box from the Cloud Workbench

## Status

The code is built. The only thing left is the GPU box, which needs a vCPU quota.

## Do now

Run these two commands. Both are safe without the quota.

```shell
git push
```

```shell
workbench ec2 update
```

This puts `--gpu-box` on the EC2 box. It takes a few minutes.

Before you run it, know that `workbench ec2 update` overwrites three files on the box:
`~/.codex/config.toml`, `~/.cursor/mcp.json`, and `~/.cursor/cli-config.json`. If you
edited any of them on the box, save a copy first. Agent logins and your OpenCode config
are not touched.

Then check it worked:

```shell
start-herdr opencode ~/some-repo --gpu-box
```

OpenCode opens with Local LLM / qwen3.8:27b selected. Sending a prompt fails, because
there is no GPU box yet. That is the expected result today.

Nothing else is worth doing until the quota lands.

## Do when the quota is approved

1. Deploy the GPU box.

   ```shell
   workbench llm up
   ```

   First run pulls the model, so give it time. Watch for `Done. Serving` in the boot
   log. `workbench llm status` shows the instance state, which is not the same as
   ready.

2. Test from the EC2 box.

   ```shell
   start-herdr opencode ~/some-repo --gpu-box
   ```

   Send a prompt. A reply proves the whole path.

3. Test from the Mac.

   ```shell
   start-opencode --gpu-box
   ```

   Send a prompt. This is the one that keeps the heat off your MacBook.

4. Shut the GPU box down when you finish.

   ```shell
   workbench llm down
   ```

If step 2 or 3 fails, the fix is in this plan. Read
[Known limits and traps](#known-limits-and-traps) first.

## Do not

Do not run `cdk deploy` for the EC2 stack. This work changed the instance user data, so
a deploy replaces the box: new SSH host key, empty disk, every agent logged out. That
change only matters for a future rebuild. `workbench ec2 update` is the safe way to
update the box and does not carry that risk.

## Known limits and traps

- **A prompt fails with no GPU box.** Expected until `workbench llm up` runs.
- **A rebuilt box breaks ssh.** Run `workbench ec2 trust-host`, then reconnect.
- **A rebuilt box leaves a dead tailnet node** holding the name while the live one
  becomes `agent-llm-1`. The stale address times out from everywhere. The launchers
  filter on `.Online`, so they pick the live one. Any hand-written command must too.
- **Pasted multi-line blocks arrive indented** in this terminal, which breaks heredocs
  and can put a newline inside a JSON string. Build test files with short single-line
  commands.
- **A repo where you already picked a model** may keep it. If `--gpu-box` seems to do
  nothing in a repo you use daily, that is the first thing to check.

## Flag names

The steps below were written against `--local-model`, which was the only flag at the
time. The user-facing flag is now `--gpu-box`, on the Mac and on the EC2 box, so one
name always means the GPU box. `--local-model` means the machine you are on, and the
EC2 launcher still accepts it as a synonym because that is what it always meant there.
Read `--local-model` in the steps below as `--gpu-box`.

## Goal

Let `opencode` on the EC2 t4g workbench box use the Qwen model on the GPU box.

Before this plan, `workbench llm up` deployed the GPU box and it served the model, but
nothing on the workbench box pointed an agent at it. This plan closes that gap.

## Scope

In scope:

- The native path on the EC2 box: `start-herdr` -> `herdr-session` -> `herdr` -> `opencode`.
- `opencode` only.

Out of scope, deferred (see [Follow-up work](#follow-up-work)):

- `pi` on the EC2 box.
- Driving the GPU box from a Mac over Tailscale.
- `--gpu-box` for the Mac `start-herdr`.

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
no sandbox. The agent uses the host network. This path is the one this plan wires up.

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

### What was missing

Nothing acted on those values. `start-herdr` had no flag, and the `opencode` config on
the box had no local provider. The seeded config
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

---

Everything below is the build record: what was changed, why, and what was tested. You
do not need it to use the feature.

## Step 0 — Verify on the box before you write code (done)

The config layering above comes from the current `opencode` docs. The box pins
`OPENCODE_VERSION=1.18.11` (`setup-workbench.sh:12`). Confirm the behaviour before
building on it.

SSH to the workbench box and run these checks.

1. **Does 1.18.11 honour `OPENCODE_CONFIG_CONTENT`?** DONE — yes.

   Test with the provider block, not with `model` alone. A `model` value naming an
   undeclared provider cannot resolve, so it proves nothing:

   ```shell
   OPENCODE_CONFIG_CONTENT='{"provider":{"local-llm":{"npm":"@ai-sdk/openai-compatible","name":"Local LLM","options":{"baseURL":"http://agent-llm:11435/v1","apiKey":"ollama"},"models":{"qwen3.8:27b":{"name":"qwen3.8:27b"}}}}}' opencode
   ```

   Open `/models`. The provider is listed, so the layer is read. The fallback of
   `OPENCODE_CONFIG` with a temp file under
   `/tmp/agent-workbench/herdr-$WORKBENCH_SESSION` is not needed.

2. **Does the merge keep the user's keys?** DONE — yes.

   Run `/mcp` in a session started with the layer. The Exa server is declared only in
   the global config, and the layer does not mention it, so its presence proves the
   merge. It is listed. The `permission` and `watcher` blocks survive with it, and the
   launcher can pass a fragment rather than a full merged copy.

   Do not test this by asking the agent to read a `.env` file. That needs the GPU box
   running and needs the model to make a tool call, so a failure would not say which
   part broke. `/mcp` needs no inference.

3. **Does `.model` in the layer select the model, or must the user pick it?**
   DONE — the layer selects it.

   Opencode remembers the last model chosen per project, so `config.model` could have
   been a default that a stored selection outranks. In a directory opencode had never
   opened, the layer from check 1 plus `"model":"local-llm/qwen3.8:27b"` opened with
   Qwen already active. So Step 3 does not need to set the model separately.

   Open question: a project with a stored selection may still override this. If a user
   reports `--local-model` having no effect in a repo they use daily, this is the first
   place to look.

4. **Does the variable reach a herdr pane?** DONE — yes.

   ```shell
   FOO=bar start-herdr opencode ~
   ```

   `printenv FOO` in the pane prints `bar`. `runtime/workbench-pane-shell:20` unsets
   `XDG_CONFIG_HOME` and `XDG_STATE_HOME` and touches nothing else. So `start-herdr`
   can export the config and does not need to write a file.

All four checks pass on opencode 1.18.11. The steps below are cleared to build.

One warning from doing them: a pasted multi-line block arrives indented in this
terminal, which breaks heredocs and can put a newline inside a JSON string. Build test
files with short single-line commands.

## Step 1 — Move the provider JSON into a shared function (done)

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

Emit it compact, with `jq -c`. The cloud path carries this value in an environment
variable, and a newline inside a JSON string breaks the parse.

Then change `start_opencode.sh:133-148` to call the function and merge its output into
the template, so the Mac path and the cloud path stay identical.

Keep the existing comment at `start_opencode.sh:129-132` about model-level `options`
being dropped for custom providers. It still applies.

**Files:** `tools/agents/local_llm.sh`, `tools/agents/start_opencode.sh`

## Step 2 — Install the shared script on the box (done)

`setup-workbench.sh:129-151` does not copy `local_llm.sh`. Add it:

```shell
install -m 755 "$REPO_DIR/tools/agents/local_llm.sh" /usr/local/lib/agent-workbench/local_llm.sh
```

`local_llm.sh` is sourced, not run, so a library path is the right home. Also install
`tools/agents/opencode.json` to `/etc/agent-workbench/opencode.json` if Step 0 check 2
failed and the fallback needs the template at runtime.

**Files:** `infra/aws/ec2/setup-workbench.sh`

## Step 3 — Add `--local-model` to the cloud `start-herdr` (done)

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

## Step 4 — Stop `workbench.env` being truncated (done)

`infra/aws/lib/workbench-ec2-stack.ts:68` writes the file with `printf ... > file`.
That truncates. `setup-workbench.sh:32-35` appends the two `LOCAL_LLM_*` lines
afterwards. If user-data re-runs without `setup-workbench.sh`, the endpoint config is
silently lost and `--local-model` points nowhere.

Fix by writing the two lines in the CDK `printf` alongside `AWS_REGION` and
`GITHUB_APP_TOKEN_FUNCTION_NAME`. Keep the idempotent `grep -q ... ||` appends in
`setup-workbench.sh` as the safety net for boxes already running.

**Files:** `infra/aws/lib/workbench-ec2-stack.ts`

## Step 4b — Key the session to the model (done)

`start-herdr` keys the herdr server to `WORKBENCH_SESSION`. An agent that is already
running keeps the environment it started with, so re-running for the same repo and
agent used to attach to the old server and `--local-model` did nothing. The pane shell
also found its marker directory already there (`workbench-pane-shell:22`) and gave a
plain shell instead of an agent.

Fixed by adding `-local-<hash>` to the default session name, where the hash covers
`LOCAL_LLM_BASE_URL` and `LOCAL_LLM_MODEL`. Local and normal sessions are now separate,
and changing the model builds a new session rather than attaching to one serving the
old one.

**Files:** `infra/aws/ec2/start-herdr`

## Step 5 — Test

Push to `main` and run `workbench ec2 update` first. `ec2 update` hard-resets the box
to `origin/main` (`bin/workbench:147-150`) and re-runs `setup-workbench.sh`, which is
what installs `local_llm.sh`. Confirm it landed before testing, so a stale file cannot
be mistaken for a bug:

```shell
grep -c local-model /usr/local/bin/start-herdr
ls -l /usr/local/lib/agent-workbench/local_llm.sh
```

### Without the GPU box — DONE, passes

This covers the wiring, which is all this plan changes.

1. `start-herdr opencode ~/some-repo --gpu-box`
2. The launcher prints `Model: qwen3.8:27b at http://agent-llm:11435/v1`.
3. `/models` shows Local LLM / qwen3.8:27b already selected.
4. `/mcp` still lists Exa, so the merge kept the user's config.
5. A prompt fails to connect. Expected with no GPU box.
6. `start-herdr cursor ~/some-repo --gpu-box` exits 1.

### With the GPU box

Needs the GPU vCPU quota, which is not granted yet.

1. `workbench llm up`, and wait for the GPU box to report ready. `llm status` shows the
   instance state, not readiness; `setup-llm.sh:177` logs when it is truly serving.
2. Confirm the endpoint answers: `curl -s http://agent-llm:11435/v1/models`
3. Repeat the wiring test. A prompt now returns a reply.
4. `workbench llm down`.

## Step 6 — Update the README (done)

`README.md:245-248` says the GPU box is deploy and destroy only. Replace the first
bullet with the working `start-herdr --local-model` usage. Keep the second bullet, the
untested Mac path, until that work lands.

**Files:** `README.md`

## Follow-up work

Not in this plan. Listed in priority order.

1. **Drive the GPU box from a Mac over Tailscale.** This is the higher-value item. The
   goal is to move inference off the MacBook, because running Qwen locally makes it hot
   and loud.

   Feasibility is now proven. The Docker sandbox routes to the tailnet but cannot
   resolve MagicDNS names. Measured against the workbench box, from inside
   `opencode-agent-workbench-...`:

   - `getent hosts agent-workbench` -> no result.
   - `curl http://<tailnet-ip>:8080/` against a `python3 -m http.server` on the box
     -> `http=200`, and the request appeared in the box's log.
   - Public DNS and egress work normally, so this is specific to MagicDNS.

   Built. `local_llm.sh` gained `host_from_url`, `tailnet_ip`, and
   `use_tailnet_address`. `resolve_local_llm` now swaps a tailnet hostname for its
   address whenever the endpoint is not the Mac's own Ollama, so
   `allow_local_llm_network` allowlists the address and the agent never needs
   MagicDNS. `tailnet_ip` filters on `.Online`, like `bin/workbench:22-24`, because a
   rebuilt box leaves a dead node holding the name and the stale address times out
   from everywhere. That trap cost time during this very test.

   Not yet run against a live GPU box. Needs the vCPU quota.
2. **`--local-model` for the Mac `start-herdr`.** `tools/agents/start_herdr.sh:192`
   installs the plain template and has no flag. Once Step 1 lands, this is small.
3. **`pi` on the EC2 box.** More than an npm install. `runtime/workbench-pane-shell:23-50`
   accepts only `codex`, `claude`, `opencode`, and `cursor`, and passes the name to
   `herdr agent start --kind`. Herdr must know the kind.

