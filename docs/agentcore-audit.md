# AgentCore Audit — 2026-08-02

Audit of the cloud (AWS Bedrock AgentCore) path on branch `feature/addskills`.

**Scope reviewed:** `start-agentcore.sh` → `bin/workbench` → `infra/aws/scripts/workbench.mjs` (976 lines), the CDK stack, the Dockerfile, `bootstrap-repo.sh`, the GitHub token chain, the runtime shell scripts, and the WIP branch diff. About 2,900 lines total for the cloud path.

## Main finding

The code is not badly written. The problem is the platform choice. AgentCore Runtime is built for HTTP request/response agents. This workbench uses its debug feature — the interactive command shell — as a remote dev box. A check of the aws-samples GitHub org shows **no AWS sample runs an interactive TUI over `agentcore exec --it`**. The two coding-agent samples avoid it:

- [sample-claude-code-web-agent-on-bedrock-agentcore](https://github.com/aws-samples/sample-claude-code-web-agent-on-bedrock-agentcore) — web UI + a backend that wraps the Claude SDK. Workspace synced to S3.
- [sample-autonomous-cloud-coding-agents](https://github.com/aws-samples/sample-autonomous-cloud-coding-agents) (ABCA) — headless. Submit a task, get a PR. No live shell at all.

Most of the complexity is scar tissue from fighting four platform rules that will not change:

| Platform rule | Workaround in this repo |
|---|---|
| ~1 hour WebSocket cutoff | reconnect countdown + terminal-reset machinery (~300 lines of `workbench.mjs`) |
| 15-minute idle reaper | fake `HealthyBusy` ping server (`infra/aws/runtime/agentcore-server.mjs`) |
| No durable storage — the volume dies with the session (8 h max) | full re-install of skills, plugins, Exa, and logins in `bootstrap-repo.sh` on every new session |
| `no-new-privileges`, no sudo | `ensure_writable_dir` / `clear_unwritable_files` / `install_agent_file` repair helpers |

Simplification has a ceiling while the workbench stays on AgentCore. The disconnects are the documented 1-hour cutoff plus the 8-hour `MaxLifetime`. They are platform behavior, not bugs in this repo.

## Defects that hurt stability now

1. **`infra/aws/runtime/workbench-profile.sh:22` deletes `node_modules`, `.venv`, and `venv` on every login shell.** A `--new-shell` reconnect or a second window wipes dependencies while the agent still runs in Herdr. This alone can explain "things randomly break." Move the cleanup to bootstrap, or drop it.
2. **`infra/aws/runtime/agentcore-server.mjs:6` freezes `time_of_last_update` at container start** and reports that stale time forever. If AgentCore reads it as staleness, this is a suspect for the sudden session ends. Return the current time on each ping.
3. **`infra/aws/runtime/Dockerfile:74-79` installs claude, codex, and opencode at `@latest`**, and line 88 pipes `cursor.com/install` to bash. Every deploy gets whatever shipped that day. The OpenCode breakage may be an upstream regression. Pin versions, as already done for Herdr, Hunk, gh, and the AWS CLI.
4. **`tools/agents/claude-settings.json:80` hardcodes `lambda.us-west-2.amazonaws.com`.** Wrong in any other region. The `gh` wrapper reaches the Lambda through the unix socket, so this entry is probably removable.
5. **The OpenCode config is installed as *managed* settings.** Verified in OpenCode's source and docs: `/etc/opencode/` on Linux is the managed-settings path, which overrides everything and the user cannot change it. So the image *enforces* `openrouter/deepseek-v4-pro` — a provider with no credentials in a fresh AgentCore session. See the blank-pane section.

## Delete list (no behavior change)

1. **Three overlapping "is it still billing?" tools:** `tools/scripts/check_agentcore_sessions.sh` (227 lines of CloudWatch forensics, referenced nowhere), `tools/scripts/probe_saved_sessions.mjs`, and `workbench aws status`. Keep one — fold the probe into `status`, delete the rest. About 250 lines.
2. **Codex telemetry is disabled in three places:** `tools/agents/codex-config.toml`, the exported `codex()` function in `bootstrap-repo.sh:268-280`, and the flags in `runtime/workbench-pane-shell:26-35`. The config file is installed to `~/.codex/config.toml` — keep only it.
3. **The in-container AWS CLI exists only to run `aws lambda invoke`** (`github-app-token-client.mjs`). Replace that call with `@aws-sdk/client-lambda` in the relay. That deletes `install-aws-cli.sh`, the GPG key file, and about 130 MB of image. Also collapse the two token paths (git → client directly, gh → socket → relay → client) into one path through the relay.
4. **`infra/aws/scripts/enable-mmdsv2.mjs` (138 lines):** check whether `AWS::BedrockAgentCore::Runtime` now accepts `MetadataConfiguration` in CloudFormation. If yes, the script becomes one property in the stack.
5. **`infra/aws/scripts/prune-workbench-images.mjs` (96 lines):** replace with `npx cdk gc` or an ECR lifecycle rule.
6. **Three wrappers deep to reach one script** (`bin/start-agentcore` → `start-agentcore.sh` → `bin/workbench` → node). One is enough.
7. **`steps-to-test-agentcore`** is a stray note file at the repo root — move it into `docs/` or delete it.

The CDK stack itself is fine. The GitHub App token Lambda is good design and carries over to any platform.

## OpenCode blank pane — three fast splits

Run these in order inside a session. Each answers one question in seconds:

1. `WORKBENCH_SKIP_HERDR=1`, then run `opencode 2>/tmp/oc.err` in the plain AgentCore shell. Blank there too → not Herdr.
2. `HOME=/tmp/oc-test opencode`. Works → the persistent home is damaged (the root-owned `opencode.db` theory). Still blank → it is the managed config or the binary.
3. Rebuild once with `opencode.json` moved from `/etc/opencode/` (managed, unoverridable) to a seed for `~/.config/opencode/opencode.json` (global). The deny rules stay. The forced OpenRouter model without a key goes away, and `/connect` and `/models` work again.

Best current theory: cause 3, with cause 2 as a contributor — a managed config pins a provider that has no credentials, in an environment where the file cannot be edited.

## Platform options

- **Option A: stay on AgentCore** and apply everything above. Simpler and more stable, but the 1-hour drops, the 8-hour cap, and the per-session re-login remain.
- **Option B: move the same workbench to a small EC2 instance** (SSM or mosh + Herdr, EBS home). That deletes the ping server, the reconnect state machine, the permission repair, and the per-session installs — logins and skills persist on disk. The CDK project, the container image, and the token Lambda carry over. An idle auto-stop rule covers billing. AgentCore is the wrong shape for a persistent interactive dev box. EC2 is the boring right shape.
- **Option C: adopt the AWS-sample shape** (web UI or headless task→PR). This changes the product, so it is listed only for completeness.

## Open items

1. Platform direction: Option A or Option B. `decision needed`
2. Apply the delete list and the five defect fixes on this branch, with no behavior change. `just say ok`
3. OpenCode: make the managed→global config change (split 3) for the next deploy. `decision needed`
