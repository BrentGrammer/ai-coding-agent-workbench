# AWS-native access

This repository uses AWS-native networking only.

```text
laptop --(SSM or CIDR-locked SSH)--> dev box --(VPC, port 11435)--> GPU box
```

## Isolation from the existing deployment

This branch creates only `AwsNativeWorkbench*` CloudFormation stacks. It uses unique instance tags, hostnames, IAM roles, security groups, and an S3 model cache. Its CLI searches for and destroys only those new names.

The AWS account's CDK bootstrap resources and default VPC are reused without modifying existing workbench resources. The new stacks create their own security groups inside that VPC. For a separate stack-owned SSH key pair, use `sshPublicKey`; `sshKeyName` intentionally references an existing key pair.

## Dev box access

SSM Session Manager is the default. It requires no inbound port and starts an Ubuntu login shell:

```shell
start-workbench
```

Optional SSH opens port 22 only to the `sshCidr` supplied during deployment. It also requires exactly one of `sshKeyName` or `sshPublicKey`.

There is no bastion host, overlay network, or UDP-based shell.

## Bitbucket repositories

Use a Bitbucket repository access token over HTTPS for a private repository. Scope the token to that repository with Repository Read permission and add Repository Write only when the dev box must push branches.

Each developer runs this once on the box. Commits and the Bitbucket audit log use that person's identity, and there is no IAM or secrets surface for git:

```shell
git config --global credential.helper 'cache --timeout=28800'
git clone https://x-token-auth@bitbucket.org/WORKSPACE/REPOSITORY.git
```

Later options, each a small separate change: a shared Secrets Manager token with a short credential helper, or SSH agent forwarding over SSH-through-SSM.

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
- All deployable resources, IAM roles, security groups, GPU cache, and instances are owned only by the new stacks.
- The setup scripts, systemd units, and agent launchers the instances run ship as a zip in the CDK bootstrap bucket. User data and `workbench ec2 update` download that zip. The instances never clone this repository.
- Removed the GitHub App token chain from this branch. Work repos use a per-developer Bitbucket HTTPS token.

Existing DigitalOcean resources are not destroyed by this repository change. Delete them in DigitalOcean before switching branches if any are still running or billing.

Rebuild an existing dev box to remove agent binaries installed by the previous setup.

## Setup zip and updates

The instances only need the scripts they run. CDK zips those from the laptop checkout into the existing bootstrap bucket. Nothing new is created in the account.

Dev instance: `infra/aws/ec2/{setup-workbench.sh, agent-workbench-profile.sh, login-welcome, workbench-idle-stop, workbench-idle-stop.service, workbench-idle-stop.timer}`, `bin/start-pi`, `tools/agents/start_pi.sh`, `tools/agents/local_llm.sh`.

GPU instance: `infra/aws/ec2/{setup-llm.sh, llm-idle-stop, llm-idle-stop.service, llm-idle-stop.timer}`, `tools/llm/ollama_inference_proxy.py`.

First boot installs unzip and the AWS CLI, downloads the zip with `aws s3 cp`, unpacks it to `/opt/agent-workbench`, and runs the setup script. The instance never clones this repository.

```shell
workbench ec2 update
```

That deploys `AwsNativeWorkbenchEc2Stack` (which uploads a new zip if the files changed), reads the zip's S3 URL from the stack outputs, and runs one SSM command to replace `/opt/agent-workbench` and re-run `setup-workbench.sh`. The zip is whatever is checked out on the laptop. Redeploying with a new asset hash does not replace a running dev instance. The GPU instance is recreated on every `llm up`, so it always gets the current zip.

`start_pi.sh` allows `release-assets.githubusercontent.com` inside the laptop sandbox because Pi downloads from GitHub Releases. That is Pi tooling, not infra, and is not on the box code path.

If `AwsNativeWorkbenchTokenStack` was deployed from an earlier revision of this branch, destroy it. Do not destroy main's `AgentWorkbenchTokenStack` or the `/coding-agent-workbench/github/*` parameters.

## Plan: security hardening

The boxes hold proprietary code and run an AI agent that reads it. The AWS plumbing is already sound. The gaps are on the box itself and in who can open a shell.

### Already in place

- No inbound ports from the internet. SSM by default. Today's optional SSH is CIDR-locked; Phase 12 replaces it with an EC2 Instance Connect Endpoint. GPU box accepts 11435 only from the dev box security group.
- Minimal instance role: `AmazonSSMManagedInstanceCore`, `ec2:DescribeInstances`, and `s3:GetObject` on that setup zip.
- IMDSv2 with hop limit 1. Encrypted EBS, deleted on termination.
- Inference-only proxy on the GPU box. Telemetry disabled for agy and Pi. Unattended security upgrades. Idle stop, a 6-hour CloudWatch backstop, and a 12-hour fuse on the GPU box.
- Pi with `--gpu-box` keeps prompts inside the VPC. Antigravity uses Gemini under a zero-data-retention enterprise agreement.

### Decisions

- Stay in the default VPC public subnet with no ingress rules. A NAT gateway is about $33 a month plus $0.045 per GB and is not justified for two boxes that are stopped most of the day. Egress is enforced on the host instead. `fck-nat` on a `t4g.nano` (about $3 a month) is the upgrade path if network-level enforcement is later required.
- No SSM session content logging. CloudTrail already records `ssm:StartSession` with the caller and instance at no cost, which is the audit that matters.
- One dev box per developer. The GPU box stays shared.

### Phase 7: agent user with IMDS block and egress allowlist

Two Linux users, all configured by `setup-workbench.sh` as root:

- `ubuntu`: the developer. Logs in via SSM and keeps sudo.
- `agent`: no sudo, no remote login. `start-pi` and `agy` run as `agent` via `sudo -u agent -i`. Repos live in `/home/agent/workspace`, shared with `ubuntu` through a setgid group.

Root-owned nftables rules:

- `meta skuid agent ip daddr 169.254.169.254 reject`. The agent can never reach the instance role.
- Drop all outbound from uid `agent` except to a local proxy on `127.0.0.1` and to the GPU box on 11435.

A root-owned local proxy (tinyproxy or squid) with a domain allowlist: `generativelanguage.googleapis.com`, `registry.npmjs.org`, `pypi.org`, `bitbucket.org`, the apt mirrors, and whatever the projects need. `HTTPS_PROXY` and `HTTP_PROXY` are set in the agent user's environment. The allowlist lives in `infra/aws/ec2/` and ships in the asset bundle so it is versioned with the repo.

Root owns `/opt/agent-workbench`, the systemd units, the proxy config, and the nftables rules. The agent cannot change any of it.

`start-pi --gpu-box` changes so the GPU IP lookup, which is an AWS call, runs as `ubuntu` and the result is passed to the `agent` process.

Blast radius of a prompt-injected agent becomes its own workspace plus the allowlisted hosts.

### Phase 8: one box per developer

- CDK reads a `developers` context list, for example `-c developers=alice,bob`, and creates `AwsNativeWorkbenchEc2Stack-<name>` for each. Every box gets its own instance, security group, role, and `Name` tag `aws-native-agent-workbench-ec2-<name>`.
- The GPU box security group allows 11435 from every dev security group.
- `bin/workbench` picks a box by `WORKBENCH_DEV=<name>`, defaulting to the local username. `local_llm.sh` and the idle scripts are unaffected.
- Cost per extra box is the `t4g.large` hourly rate while running and about $2.40 a month for the 30 GB disk while stopped.

### Phase 9: scoped shell access

One IAM policy per developer:

- `ssm:StartSession` only on their instance via `aws:ResourceTag/Name`, and only with the `AWS-StartInteractiveCommand`, `AWS-StartSSHSession`, and default shell documents.
- `ssm:TerminateSession` and `ssm:ResumeSession` on their own sessions only.
- The `ec2:DescribeInstances` and `cloudformation:DescribeStacks` reads that `bin/workbench` needs.

Nobody else in the account can open a shell on a dev box. Session preferences set `runAsEnabled` with `runAsDefaultUser=ubuntu` so sessions never start as root.

### Phase 10: pinned and verified installs

Every binary uses a fixed version and a recorded checksum or signature, and fails closed. No `curl | bash`.

| Tool | Method |
|---|---|
| Node | Official tarball from `nodejs.org/dist/v24.x.y/` verified against `SHASUMS256.txt`. Reuse `install_node_lts` from `sandbox_bootstrap.sh`. Drops nodesource. |
| AWS CLI | Keep the zip, verify the published `.sig` with AWS's GPG public key pinned in the script. |
| Ollama | `https://ollama.com/download/ollama-linux-amd64.tgz?version=0.x.y` with a recorded sha256. Drops the install script. |
| Pi | Already pinned with `--ignore-scripts`. Add `npm config set ignore-scripts true` for the `agent` user so project installs skip lifecycle scripts too. |
| Antigravity CLI | Inspect what `antigravity.google/cli/install.sh` downloads and pin that artifact with its sha256. If there is no versioned artifact, vendor the script with a recorded hash and fail if it changes. |

Versions and hashes sit at the top of each setup script and are bumped deliberately, then rolled out with `workbench ec2 update`.

### Phase 11: security tests and docs

- `test/workbench-ec2-stack.test.ts`: assert one stack per developer, distinct `Name` tags, no ingress rule with a CIDR source, and the instance role has no actions beyond SSM core, `ec2:DescribeInstances`, and the asset read.
- `test/workbench-llm-stack.test.ts`: assert 11435 ingress from each dev security group and nothing else.
- Update this document and `docs/cloud-onetime-setup.md` with the per-developer deploy, the IAM policy, and the `agent` user workflow.

### Phase 12: SSH through an EC2 Instance Connect Endpoint

Two connection paths, both with no inbound port from the internet. A developer picks one.

- SSM Session Manager. Needs the Session Manager plugin on the laptop.
- Plain `ssh` with their own keypair through an EC2 Instance Connect Endpoint. Needs only the AWS CLI, which `bin/workbench` already requires.

The CIDR-locked public port 22 option is removed. `sshCidr` and `sshKeyName` go away.

Infrastructure:

- One `AWS::EC2::InstanceConnectEndpoint` in the default VPC with its own security group, created once in a shared stack and used by every dev box. There is no hourly charge for the endpoint.
- Each dev box security group allows port 22 only from the endpoint security group.
- A developer who wants SSH supplies `sshPublicKey` for their box. The stack owns the key pair and AWS holds only the public key. Destroying the stack removes it.

Laptop `~/.ssh/config`:

```text
Host workbench
  User ubuntu
  IdentityFile ~/.ssh/workbench_ed25519
  ProxyCommand aws ec2-instance-connect open-tunnel --instance-id %h
```

`bin/workbench ec2 ssh` resolves the instance ID by tag and runs `ssh` with that ProxyCommand.

IAM, added to the per-developer policy from Phase 9: `ec2-instance-connect:OpenTunnel` on the endpoint, conditioned on their instance via `ec2-instance-connect:privateIpAddress` or the instance tag, and `ec2:DescribeInstanceConnectEndpoints`.

Box changes in `setup-workbench.sh`:

- `sshd` hardening: `PasswordAuthentication no`, `PermitRootLogin no`, `AllowUsers ubuntu`.
- `workbench ec2 update` gains an SSH path so an SSH-only developer can update their own box: `ssh workbench sudo <download and re-run setup>`.
- `workbench-idle-stop` already counts an established port 22 connection as in use, so no change.
- The SSM agent stays installed on every box. The laptop-side `workbench llm up` readiness check uses it, and it never requires anything on the developer's laptop.

Tests: assert the dev box security group has exactly one port 22 rule and its source is the endpoint security group, and that no rule has a CIDR source.

### Remaining risk

Egress control is host-enforced rather than network-enforced. It depends on `agent` having no sudo and on the nftables rules being root-owned. If the security team wants network-level enforcement, add `fck-nat` with the same allowlist in front of both boxes.

## Order and safety

Do phases 7 and 10 together since both live in `setup-workbench.sh`, then 8, 9, and 12 together since the IAM policy depends on the per-developer tags and the endpoint, then 11. Before any deploy, run `npm run synth` and `npx cdk diff`. The diff must show only `AwsNativeWorkbench*` stacks and no mention of `AgentWorkbench*`. Destroy `AwsNativeWorkbenchTokenStack` only if it was ever deployed.

After this, the remaining external installs are Node, AWS CLI, Ollama, Pi, and Antigravity CLI, all pinned and verified. None is github.com.
