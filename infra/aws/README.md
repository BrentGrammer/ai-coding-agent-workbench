# AWS workbench stack

The CDK app deploys:

- `AwsNativeWorkbenchSharedStack` for the Instance Connect Endpoint
- `AwsNativeWorkbenchEc2Stack-<name>` for each developer in `-c developers=`
- `AwsNativeWorkbenchLlmCacheStack` for model storage
- `AwsNativeWorkbenchLlmStack` for the optional GPU box

These names, EC2 tags, S3 cache, IAM roles, and security groups are separate from the existing workbench deployment. Commands in this branch select only the AWS-native resources.

The stacks reuse only account-level CDK bootstrap resources and the default VPC. They do not import or modify the existing workbench instances, roles, security groups, Lambda, or cache.

The setup scripts, systemd units, and agent launchers the instances run ship as a zip in the CDK bootstrap bucket. First boot and `workbench ec2 update` download that zip. The instances never clone this repository.

## Prerequisites

Complete [Cloud one-time setup](../../docs/cloud-onetime-setup.md).

## Deploy

```shell
cd infra/aws
npm ci --ignore-scripts
npx cdk bootstrap
npx cdk deploy "/AwsNativeWorkbench(SharedStack|Ec2Stack.*)/" -c developers=alice
```

`npm run changeset` prepares CloudFormation change sets for those stacks without executing them. Review them in the console, then execute there if they look right.

`WORKBENCH_DEV` selects the box and defaults to the local username. SSM is the default access path:

```shell
start-workbench
```

Each EC2 stack outputs `DeveloperAccessPolicyArn`. Attach that policy to the identity that opens shells on that box.

Optional SSH uses the Instance Connect Endpoint. Pass `sshPublicKey` for a single developer, or `sshPublicKey-<name>` when deploying more than one. There is no public port 22.

```shell
npx cdk deploy "/AwsNativeWorkbench(SharedStack|Ec2Stack.*)/" \
  -c developers=alice \
  -c sshPublicKey="$(cat ~/.ssh/id_ed25519.pub)"
```

```shell
workbench ec2 ssh
```

The matching private key remains on the laptop. Set `WORKBENCH_EC2_SSH_KEY` when it is not available through `ssh-agent` or a default OpenSSH key path.

## Agents

The dev box installs only Antigravity CLI and Pi. After connecting as `ubuntu`, run `agy` or `start-pi`. Those commands run as the `agent` user.

## GPU box

```shell
workbench llm up
workbench llm status
workbench llm down
```

The GPU security group accepts inference traffic on port `11435` only from the dev box security groups. Readiness checks use SSM and the GPU instance loopback interface.

The default is a `g6e.xlarge` with a 131,072-token context. Override it when deploying:

```shell
WORKBENCH_LLM_INSTANCE_TYPE=g6.xlarge \
WORKBENCH_LLM_CONTEXT_LENGTH=32768 \
workbench llm up
```

The instance terminates after it is idle, while the S3 model cache remains.
