# AWS-native access

This repository uses AWS-native networking only.

```text
laptop --(SSM or CIDR-locked SSH)--> dev box --(VPC, port 11435)--> GPU box
```

## Isolation from the existing deployment

This branch creates only `AwsNativeWorkbench*` CloudFormation stacks. It uses unique instance tags, hostnames, Parameter Store paths, IAM roles, Lambda functions, security groups, and an S3 model cache. Its CLI searches for and destroys only those new names.

The AWS account's CDK bootstrap resources and default VPC are reused without modifying existing workbench resources. The new stacks create their own security groups inside that VPC. For a separate stack-owned SSH key pair, use `sshPublicKey`; `sshKeyName` intentionally references an existing key pair.

## Dev box access

SSM Session Manager is the default. It requires no inbound port and starts an Ubuntu login shell:

```shell
start-workbench
```

Optional SSH opens port 22 only to the `sshCidr` supplied during deployment. It also requires exactly one of `sshKeyName` or `sshPublicKey`.

There is no bastion host, overlay network, or UDP-based shell.

## GPU box

The GPU box has no public ingress. Its security group accepts port `11435` only from the dev box security group. The dev box discovers the running GPU instance by its `aws-native-agent-workbench-gpu-llm` tag and uses its private IP.

GPU deployment and readiness checks run from the laptop. Readiness is checked through SSM against `127.0.0.1:11435` on the GPU instance.

`start-pi --gpu-box` runs on the dev box. It discovers the GPU private IP and configures Pi for that endpoint.

## Agents

The only installed agent CLIs are:

- Antigravity CLI (`agy`)
- Pi (`pi`)

## Implemented changes

- Removed the DigitalOcean Terraform, droplet lifecycle, cache, CLI provider, and documentation.
- Removed Tailscale, MagicDNS, mosh, and their Parameter Store and IAM setup.
- Made SSM the default dev-box connection and moved updates to SSM.
- Added optional port 22 ingress from one configured CIDR with an existing EC2 key pair or supplied OpenSSH public key.
- Limited GPU ingress to port `11435` from the dev box security group.
- Changed GPU readiness checks to run over SSM on the GPU instance.
- Added `start-pi --gpu-box` on the dev box, using tag-based private-IP discovery.
- Removed every agent launcher, configuration, and dev-box install except Antigravity CLI and Pi.
- Removed Herdr and its runtime files.
- Added new `AwsNativeWorkbench*` stack names and `aws-native-agent-workbench-*` instance tags so this deployment cannot update, stop, or destroy the existing workbench resources.
- The new token Lambda reuses the existing GitHub App parameters read-only. All deployable resources, IAM roles, security groups, GPU cache, and instances are owned only by the new stacks.

Existing resources from the removed cloud provider are not destroyed by this repository change. Delete them in that provider before switching branches if any are still running or billing.

Rebuild an existing dev box to remove agent binaries installed by the previous setup.
