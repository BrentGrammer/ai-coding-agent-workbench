# Workbench AWS Stack

This CDK project deploys two stacks: `AgentWorkbenchTokenStack`, the Lambda function that mints short-lived GitHub App installation tokens, and `AgentWorkbenchEc2Stack`, the persistent EC2 workbench instance. The instance never holds the GitHub App private key — it can only invoke the token Lambda.

[AWS CDK (Cloud Development Kit)](https://github.com/aws/aws-cdk) is AWS's open source Infrastructure as Code tool for deploying and managing AWS resources.

> **IMPORTANT: This setup incurs AWS charges.**
>
> Review the [cost controls and billing caveat](./README.md#cost-controls) before deployment.

## Prerequisites

Create the GitHub App and the Tailscale auth key first, and store all three parameters below in AWS Systems Manager Parameter Store, in the region where the stack deploys. The steps are in [Cloud one-time setup](../../docs/cloud-onetime-setup.md). Before `workbench llm up`, also raise the [G-family GPU quotas](../../docs/cloud-onetime-setup.md#5-gpu-quotas-local-llm-only).

| Parameter                                    | Type           | Value                            |
| -------------------------------------------- | -------------- | -------------------------------- |
| `/coding-agent-workbench/github/app-id`      | `String`       | GitHub App ID                    |
| `/coding-agent-workbench/github/private-key` | `SecureString` | Complete PEM private key         |
| `/coding-agent-workbench/tailscale/auth-key` | `SecureString` | Signed Tailscale auth key        |

Only the token Lambda reads these parameters. The workbench host can only invoke that function, which returns a one-hour token scoped to one repository — the host never sees the private key. Tokens expire after one hour and refresh automatically on later Git operations.

Set `ALLOWED_REPOSITORIES` to restrict which repositories can receive tokens:

```shell
export ALLOWED_REPOSITORIES=owner/repo-one,owner/repo-two
npm run deploy
```

## Deploy the stack

```shell
cd infra/aws
npm ci --ignore-scripts
```

If this account and region have not been bootstrapped for CDK, run this once before deployment:

```shell
npx cdk bootstrap
```

Then deploy:

```shell
npm run deploy
```

Forked repositories: pass `repoUrl` so the instance clones your fork instead of the upstream repo:

```shell
npx cdk deploy --all -c repoUrl=https://github.com/<you>/ai-coding-agent-workbench.git
```

The deploy command deploys both stacks: the token Lambda and the EC2 workbench instance.

## Tailscale auto-join

The instance boots with no inbound ports. On first boot it reads a Tailscale auth key from Parameter Store and joins the tailnet by itself. `bin/workbench ec2 update` re-runs the setup script for updates.

The tailnet policy and the auth key are one-time setup. The steps are in [Cloud one-time setup](../../docs/cloud-onetime-setup.md).

At each rebuild (destroy + deploy): make a fresh Tailscale auth key (non-reusable, tagged `tag:workbench`, 1-day expiry), store it in the SSM parameter, then deploy right away so first boot uses it. Revoke the old key in Tailscale afterward.

## Rebuild from scratch

The instance and its disk are disposable.

1. Destroy the instance stack. The token stack can stay.

   ```shell
   cd infra/aws
   npx cdk destroy AgentWorkbenchEc2Stack
   ```

2. Deploy. This recreates the instance stack.

   ```shell
   npm run deploy
   ```

3. Wait 3 to 5 minutes after the deploy finishes so first boot can join the tailnet.

4. Connect with `start-workbench`. Then log in each agent once on the new box: `claude`, `codex`, `opencode auth login`, `cursor-agent login`.

## Maintenance

- Monthly: bump the tool version pins in `ec2/setup-workbench.sh`, then run `workbench ec2 update`.
- Quarterly: destroy and deploy to get a fresh, fully patched AMI.
- Renew the Tailscale auth key if an expiration is set.

## Cost controls

This section is a convenience checklist, not authoritative billing guidance and could contain incorrect information. Verify current pricing, limits, and billable resources in the official AWS documentation and the AWS billing console before relying on it.

Also recommended: create an AWS Budget in the Billing console with an alert threshold so you are notified if spend exceeds a chosen amount.

- No new VPC, NAT gateway, load balancer, EFS, database, or dashboard is created. The instance uses the default VPC.
- One Lambda function (GitHub token minting, 256 MB, 15 s timeout) runs only when Git requests a credential — a few short invocations per session. Its log group keeps logs for one week.
- One t4g.large instance bills only while running. Two mechanisms stop it when idle: an on-box timer (15 minutes with no client) and a CloudWatch alarm (CPU under 5% for 6 hours). A stopped instance bills only its 30 GB disk.
- The public IPv4 address bills hourly while the instance runs.
- The GPU box bills only while it exists. `workbench llm down` stops the cost.
- AWS scores Spot capacity from 1 to 10. `workbench llm up` uses On-Demand when the score is under 7, because Spot would likely fail. Check the score first:

```shell
aws ec2 get-spot-placement-scores --instance-types g6e.xlarge \
  --target-capacity 1 --target-capacity-unit-type units \
  --region-names us-west-2 --query 'SpotPlacementScores[0].Score' --output text
```

## GPU box configuration

The GPU box defaults to `g6e.xlarge` (L40S, 48 GB VRAM) with a 131,072-token Ollama context. `workbench llm up` passes both to the stack as CDK context, so set the env vars there:

```shell
WORKBENCH_LLM_INSTANCE_TYPE=g6.xlarge WORKBENCH_LLM_CONTEXT_LENGTH=32768 workbench llm up
```

For a direct `cdk deploy`, pass `-c llmInstanceType=... -c llmContextLength=...` instead.

## GPU box checks

`workbench llm status` gives the instance ID and state.

Is it serving?

```shell
curl -s http://agent-llm:11435/v1/models
```

`data: null` means Ollama is up but the model is not loaded yet. A first-ever boot pulls 17 GB from the registry (~30 min) and uploads it to the S3 cache. Later boots restore from the cache (~5 min).

Read the setup log. A rebuilt box has new host keys, so trust it first:

```shell
workbench llm trust-host
ssh ubuntu@agent-llm 'sudo cat /var/log/cloud-init-output.log'
```

Wait for `== Done. Serving qwen3.8:27b`.

If ssh or curl hangs, a dead node still holds the name and the live box joined as `agent-llm-1`:

```shell
tailscale status | grep agent-llm
```

Use the online node's address. Tailscale reaps the dead one in about 30 minutes.

Cache contents:

```shell
aws s3 ls s3://$(aws cloudformation describe-stacks \
  --stack-name AgentWorkbenchLlmCacheStack \
  --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
  --output text)/qwen3.8:27b/ --summarize --human-readable | tail -3
```

The `_COMPLETE` key is written last. Without it the next boot pulls from the registry again.
