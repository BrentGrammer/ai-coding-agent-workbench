# Workbench AWS Stack

This CDK project deploys two stacks: `AgentWorkbenchTokenStack`, the Lambda function that mints short-lived GitHub App installation tokens, and `AgentWorkbenchEc2Stack`, the persistent EC2 workbench instance. The instance never holds the GitHub App private key — it can only invoke the token Lambda.

[AWS CDK (Cloud Development Kit)](https://github.com/aws/aws-cdk) is AWS's open source Infrastructure as Code tool for deploying and managing AWS resources.

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

Create these parameters in AWS Systems Manager Parameter Store in the region where the stack deploys:

| Parameter                                    | Type           | Value                    |
| -------------------------------------------- | -------------- | ------------------------ |
| `/coding-agent-workbench/github/app-id`      | `String`       | GitHub App ID            |
| `/coding-agent-workbench/github/private-key` | `SecureString` | Complete PEM private key |

Do not commit the PEM key, put it in an environment file, or paste it into logs.

Only the token Lambda reads these parameters. The workbench host can only invoke that function, which returns a one-hour token scoped to one repository — the host never sees the private key.

Set `ALLOWED_REPOSITORIES` to restrict which repositories can receive tokens:

```shell
export ALLOWED_REPOSITORIES=owner/repo-one,owner/repo-two
npm run deploy
```

## Deploy the stack

```shell
cd infra/aws
npm install
```

If this account and region have not been bootstrapped for CDK, run this once before deployment:

```shell
npx cdk bootstrap
```

Then deploy:

```shell
npm run deploy
```

The deploy command deploys both stacks: the token Lambda and the EC2 workbench instance.

## First connection to a new instance

The instance boots with no inbound ports. Connect once over SSM and join your tailnet:

```shell
bin/workbench ec2 ssm
sudo tailscale up --ssh
exit
```

Approve the login link in the browser. After that, daily use is `bin/workbench ec2 mosh` from the repo root, and `bin/workbench ec2 update` re-runs the setup script for updates.

## Cost controls

This section is a convenience checklist, not authoritative billing guidance and could contain incorrect information. Verify current pricing, limits, and billable resources in the official AWS documentation and the AWS billing console before relying on it.

Also recommended: create an AWS Budget in the Billing console with an alert threshold so you are notified if spend exceeds a chosen amount.

- No new VPC, NAT gateway, load balancer, EFS, database, or dashboard is created. The instance uses the default VPC.
- One Lambda function (GitHub token minting, 256 MB, 15 s timeout) runs only when Git requests a credential — a few short invocations per session. Its log group uses the default retention and never expires.
- One t4g.large instance bills only while running. Two mechanisms stop it when idle: an on-box timer (15 minutes with no client) and a CloudWatch alarm (CPU under 5% for 6 hours). A stopped instance bills only its 30 GB disk.
- The public IPv4 address bills hourly while the instance runs.
