# AgentCore Stack CDK Deployment

This CDK stack deploys the Herdr and Hunk workbench to Amazon Bedrock AgentCore. 

[AWS CDK (Cloud Development Kit)](https://github.com/aws/aws-cdk) is AWS's open source Infrastructure as Code tool for deploying and managing AWS resources. Deploying this stack creates a CloudFormation Stack with the required resources for running the workbench on AWS Bedrock AgentCore.

> **IMPORTANT: This setup incurs AWS charges.**
>
> Review the [cost controls and billing caveat](./README.md#cost-controls) before deployment.

## Prerequisites

### Create the GitHub App

One GitHub App provides scalable repository access without maintaining a permanent token for each repository.

1. Open GitHub **Settings → Developer settings → GitHub Apps → New GitHub App**.
2. Give the app a unique name and use an appropriate GitHub page as its homepage URL.
3. Disable **Active** under Webhook because this workbench does not receive webhooks.
4. Under Repository permissions, set **Contents** to **Read and write**.
5. Leave callback URLs, user authorization, device flow, post-installation setup, and the IP allow list unset.
6. Create the app and note its **App ID**.
7. Generate and download a private key. Do not generate or store a client secret because this workbench does not use OAuth.
8. If macOS offers to import the PEM file into Keychain, cancel the import.
9. Choose **Install App** and install it on the personal account or organizations containing the target repositories.
10. Choose **All repositories** for current and future repositories, or maintain an explicit selected list.

The app generates repository-limited installation tokens when Git needs them. Tokens expire after one hour and refresh automatically on later Git operations.

## Store the GitHub App configuration

Create these parameters in AWS Systems Manager Parameter Store in the same region as the AgentCore runtime:

| Parameter                                    | Type           | Value                    |
| -------------------------------------------- | -------------- | ------------------------ |
| `/coding-agent-workbench/github/app-id`      | `String`       | GitHub App ID            |
| `/coding-agent-workbench/github/private-key` | `SecureString` | Complete PEM private key |

Do not commit the PEM key, put it in an environment file, or paste it into logs.

Only the token Lambda reads these parameters. The runtime role can only invoke that function, which returns a one-hour token scoped to one repository — the container never sees the private key.

Set `ALLOWED_REPOSITORIES` to restrict which repositories can receive tokens:

```shell
export ALLOWED_REPOSITORIES=owner/repo-one,owner/repo-two
npm run deploy
```

### Install or update the AgentCore CLI before opening a session:

```shell
npm install -g @aws/agentcore@latest
```

```shell
cd infra/aws
npm install
```

If this account and region have not been bootstrapped for CDK, run this once before deployment:

```shell
npx cdk bootstrap
```

## Deploy the stack:

```shell
npm run deploy
```

The deploy command:

- Builds and publishes the ARM64 runtime image.
- Deploys the AgentCore runtime.
- Deploys the Lambda function that mints GitHub App tokens.

If the deploying identity will not open workbench sessions, attach the `AgentCoreShellCallerPolicyArn` stack output to the trusted IAM user or role that will.

## Manage AgentCore sessions

Use the lower-level command to select a repository, branch, or persistent session at launch:

```shell
workbench aws https://github.com/owner/repo.git --agent codex
```

Every launch is recorded locally under a name, so you can always get back to it. Without `--keep NAME` the name is generated from the repository, the agent, and a short session id, and it is printed whenever the shell closes.

`--keep NAME` picks the name yourself:

```shell
workbench aws https://github.com/owner/repo.git \
  --ref main \
  --agent claude \
  --keep repo-claude
```

Reconnect, stop, or list sessions:

```shell
workbench aws reconnect repo-claude
workbench aws stop repo-claude
workbench aws status
```

### Dropped connections and finishing a session

AgentCore drops the shell WebSocket on its own — at the one-hour connection cutoff, on a transient network fault, and when the client cannot read output frames fast enough. The shell closing therefore means one of two things, and **AgentCore reports the same successful exit status for both**, so the launcher cannot tell them apart on its own. It asks you instead.

When the shell closes, workbench counts down for three seconds and then reattaches to the same session and shell id. Do nothing and a dropped connection repairs itself — AgentCore replays up to 256 KB of recent output, so you land back where you were.

Press any key during the countdown to choose instead:

```
The AgentCore session repo-claude-79967b5d is still running.

  [s] stop it now and end its billing (default)
  [r] reconnect to it
  [l] leave it running so you can reconnect later

>
```

So finishing a session is: `exit` the shell, press any key, press Enter. The session is stopped and its record removed. Nothing to remember later.

Two more layers keep a drop from costing you work:

- **Herdr keeps your panes.** `start-herdr` runs Herdr's background session server, so the coding agent survives even if the shell process itself dies. Reattaching runs `start-herdr` for you when a Herdr server is still up, so your panes come straight back. Set `WORKBENCH_SKIP_HERDR=1` if you want a plain shell.
- **Every launch is recoverable.** The session is saved locally before the shell opens, so `workbench aws reconnect NAME` always works, even after your terminal or laptop dies.

**When you have to stop a session yourself:** only when you chose `[l] leave it running`. That session keeps billing until you run `workbench aws stop NAME`. Everything else stops for you:

- Exit the shell and press Enter at the prompt, and it is stopped and its record removed.
- If your terminal or laptop dies, nothing on your machine is guaranteed to run, so nothing local can be counted on to stop the session. AgentCore has been seen to end dropped sessions on its own, but that is not documented behaviour. Check if you are unsure whether something is still billing.

Run `workbench aws status` for what is saved locally. Run `node tools/scripts/probe_saved_sessions.mjs` to check each saved session against AWS for real — it says whether each one is still alive and stops any that are.

## Debug AgentCore runtime logs

In the AWS console: CloudWatch → Log groups → open a group matching `/aws/bedrock-agentcore/runtimes/agent_workbench-*`.

With the AWS CLI:

```shell
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/bedrock-agentcore/runtimes/agent_workbench" \
  --query 'logGroups[*].logGroupName' \
  --output text

aws logs tail "LOG_GROUP_NAME" --since 2h --follow
```

Replace `LOG_GROUP_NAME` with a name from `describe-log-groups` (for example `/aws/bedrock-agentcore/runtimes/agent_workbench-<id>-DEFAULT`).

## Cost controls

This section is a convenience checklist, not authoritative billing guidance and could contain incorrect information. Verify current pricing, limits, and billable resources in the official AWS documentation and the AWS billing console before relying on it. 

Also recommended: create an AWS Budget in the Billing console with an alert threshold so you are notified if spend exceeds a chosen amount.

- No VPC, NAT gateway, load balancer, EFS, database, AgentCore Memory, Gateway, alarm, or dashboard is created.
- One Lambda function (GitHub token minting, 256 MB, 15 s timeout) runs only when Git requests a credential — a few short invocations per session. Its log group uses the default retention and never expires.
- AgentCore runtime billing is usage-based.
- The runtime's 15-minute idle timeout does not apply here, because `/ping` reports `HealthyBusy` for the whole session to stop AgentCore reaping an interactive shell mid-task. A dropped session has still been seen to end on its own, but do not count on that. Stop sessions yourself with `workbench aws stop NAME`.
- Runtime compute has an eight-hour maximum lifetime.
- Runtime CloudWatch logs retain one day.
- Deployment keeps one tracked workbench image and removes older tracked images.
- `workbench aws status` checks whether AgentCore reports active runtime sessions.
