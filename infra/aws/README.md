# AgentCore workbench

This stack runs the generic Herdr and Hunk workbench on Bedrock AgentCore.

Install or update the AgentCore CLI before opening a session:

```shell
npm install -g @aws/agentcore@latest
```

## GitHub access

Create one GitHub App for the workbench with repository `Contents` read and write permission. Install it on your personal account and each organization whose repositories the workbench should use. Choose `All repositories` for automatic access to current and future repositories, or maintain a selected list in the app installation.

Store the app ID as a String parameter:

```text
/coding-agent-workbench/github/app-id
```

Generate a private key for the app and store the complete PEM value as a SecureString parameter:

```text
/coding-agent-workbench/github/private-key
```

The parameters are required before the first repository launch, but they do not need to exist before stack deployment.

The runtime does not store repository tokens. Its Git credential helper creates a repository-limited installation token whenever Git needs one. GitHub expires each token after one hour, but later Git operations automatically receive a new token.

## Deploy

> **IMPORTANT: This setup incurs AWS charges.**
>
> Review the [cost controls and billing caveat](../../README.md#cost-controls) before deployment.

```shell
cd infra/aws
npm install
```

If this AWS account and region have not been bootstrapped for CDK, run this once:

```shell
npx cdk bootstrap
```

Deploy the stack:

```shell
npm run deploy
```

Attach the `AgentCoreShellCallerPolicyArn` stack output to the trusted IAM user or role that opens workbench sessions.

## Launch

Install the launcher commands and configure `.env` as described in the [project README](../../README.md), then choose the primary agent:

```shell
start-agentcore claude
start-agentcore codex
start-agentcore opencode
```

For named sessions, repository overrides, and session management, use the lower-level `workbench` command:

```shell
workbench aws https://github.com/owner/repo.git --ref main --agent claude --keep repo-claude
workbench aws reconnect repo-claude
workbench aws stop repo-claude
workbench aws status
```

Named sessions keep the checkout and agent home in AgentCore managed session storage across idle compute shutdowns. The first interactive login for Claude, Codex, or OpenCode is retained within that named session.

`workbench aws` requires AgentCore CLI 0.24.1 or newer. The CLI automatically reconnects the same shell across AgentCore's one-hour WebSocket cutoff and transient network interruptions.
