# AWS workbench stack

The CDK app deploys:

- `AwsNativeWorkbenchTokenStack` for short-lived GitHub App tokens
- `AwsNativeWorkbenchEc2Stack` for the persistent dev box
- `AwsNativeWorkbenchLlmCacheStack` for model storage
- `AwsNativeWorkbenchLlmStack` for the optional GPU box

These names, EC2 tags, S3 cache, Lambda, IAM roles, and security groups are separate from the existing workbench deployment. Commands in this branch select only the AWS-native resources. The new Lambda reuses the existing GitHub App parameters read-only.

The stacks reuse only account-level CDK bootstrap resources and the default VPC. They do not import or modify the existing workbench instances, roles, security groups, Lambda, or cache. Use `sshPublicKey` if the new stack should own its SSH key pair too.

## Prerequisites

Complete [Cloud one-time setup](../../docs/cloud-onetime-setup.md). The only Parameter Store values are the GitHub App ID and private key.

## Deploy

```shell
cd infra/aws
npm ci --ignore-scripts
npx cdk bootstrap
npm run deploy
```

SSM is the default access path:

```shell
start-workbench
```

Optional SSH requires deployment context:

```shell
npx cdk deploy AwsNativeWorkbenchEc2Stack \
  -c sshCidr=203.0.113.4/32 \
  -c sshKeyName=agent-workbench
```

Use `sshPublicKey` instead of `sshKeyName` to create a key pair from public-key contents. Setting both fails synthesis.

The matching private key remains on the laptop. Set `WORKBENCH_EC2_SSH_KEY` when it is not available through `ssh-agent` or a default OpenSSH key path.

## Agents

The dev box installs only Antigravity CLI and Pi. Run `agy` or `pi` after connecting.

## GPU box

```shell
workbench llm up
workbench llm status
workbench llm down
```

The GPU security group accepts inference traffic on port `11435` only from the dev box security group. Readiness checks use SSM and the GPU instance loopback interface.

The default is a `g6e.xlarge` with a 131,072-token context. Override it when deploying:

```shell
WORKBENCH_LLM_INSTANCE_TYPE=g6.xlarge \
WORKBENCH_LLM_CONTEXT_LENGTH=32768 \
workbench llm up
```

The instance terminates after it is idle, while the S3 model cache remains.
