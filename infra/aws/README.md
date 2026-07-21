# AgentCore workbench

This stack runs the generic Herdr and Hunk workbench on Bedrock AgentCore. It does not use the Lambda microVM example.

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
npx cdk bootstrap
npm run deploy
```

Attach the `AgentCoreShellCallerPolicyArn` stack output to the trusted IAM user or role that opens workbench sessions.

## Launch

Temporary session:

```shell
./bin/workbench aws https://github.com/owner/repo.git --agent codex
```

Named persistent session:

```shell
./bin/workbench aws https://github.com/owner/repo.git --ref main --agent claude --keep repo-claude
./bin/workbench aws reconnect repo-claude
./bin/workbench aws stop repo-claude
./bin/workbench aws status
```

Named sessions keep the checkout and agent home in AgentCore managed session storage across idle compute shutdowns. The first interactive login for Claude, Codex, or OpenCode is retained within that named session.

`workbench aws` requires AgentCore CLI 0.24.1 or newer. The CLI automatically reconnects the same shell across AgentCore's one-hour WebSocket cutoff and transient network interruptions.

CloudFormation does not currently accept AgentCore's required `MetadataConfiguration` property. After CDK deploys the runtime, the deploy wrapper enables MMDSv2 through the AgentCore control API and fails if that update does not succeed.
