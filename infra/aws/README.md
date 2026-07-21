# AgentCore Stack CDK Deployment

This CDK stack deploys the Herdr and Hunk workbench to Amazon Bedrock AgentCore.

## Prerquisites

1. Follow the GitHub App setup in the main [README](../../README.md)
1. Install or update the AgentCore CLI before opening a session:

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

If the deploying identity will not open workbench sessions, attach the `AgentCoreShellCallerPolicyArn` stack output to the trusted IAM user or role that will.

## Manage AgentCore sessions

Use the lower-level command to select a repository, branch, or persistent session at launch:

```shell
workbench aws https://github.com/owner/repo.git --agent codex
```

`--keep NAME` preserves the checkout and agent home for later use:

```shell
workbench aws https://github.com/owner/repo.git \
  --ref main \
  --agent claude \
  --keep repo-claude
```

Reconnect, stop, or check active AgentCore runtime sessions:

```shell
workbench aws reconnect repo-claude
workbench aws stop repo-claude
workbench aws status
```

Named sessions preserve the checkout and agent home in AgentCore managed session storage. Complete each agent's normal login the first time it runs in a named session.

The AgentCore CLI reconnects the same shell automatically across the one-hour WebSocket cutoff and transient network interruptions. AgentCore shuts down idle compute after 15 minutes and caps each compute lifetime at eight hours. Persistent files remain available to the same named session.
