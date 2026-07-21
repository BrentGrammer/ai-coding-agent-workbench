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

The AWS console is the simplest way to store the multiline private key. Do not commit it, put it in an environment file, or paste it into logs.

These parameters are required before the first repository launch, but not before stack deployment.

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

## Cost controls

This section is a convenience checklist, not authoritative billing guidance and could contain incorrect information. Verify current pricing, limits, and billable resources in the official AWS documentation and the AWS billing console before relying on it. 

Also recommended: create an AWS Budget in the Billing console with an alert threshold so you are notified if spend exceeds a chosen amount.

- No Lambda microVM, VPC, NAT gateway, load balancer, EFS, database, AgentCore Memory, Gateway, alarm, or dashboard is created.
- AgentCore runtime billing is usage-based.
- Idle runtime compute stops after 15 minutes.
- Runtime compute has an eight-hour maximum lifetime.
- CloudWatch logs retain one day.
- Deployment keeps one tracked workbench image and removes older tracked images.
- `workbench aws status` checks whether AgentCore reports active runtime sessions.
