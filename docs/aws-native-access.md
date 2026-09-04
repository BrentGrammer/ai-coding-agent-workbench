# AWS-native access

This repository uses AWS-native networking only.

```text
laptop --(SSM or Instance Connect SSH)--> dev box --(VPC, port 11435)--> GPU box
```

## Isolation from the existing deployment

This branch creates only `AwsNativeWorkbench*` CloudFormation stacks. It uses unique instance tags, hostnames, IAM roles, security groups, and an S3 model cache. Its CLI searches for and destroys only those new names.

The AWS account's CDK bootstrap resources and default VPC are reused without modifying existing workbench resources. The new stacks create their own security groups inside that VPC. SSH uses a stack-owned key pair from `sshPublicKey` and an Instance Connect Endpoint. There is no public port 22.

## Dev box access

SSM Session Manager is the default. It requires no inbound port and starts an Ubuntu login shell. `WORKBENCH_DEV` selects the box and defaults to the local username:

```shell
start-workbench
```

Optional SSH uses an EC2 Instance Connect Endpoint. Port 22 is open only from that endpoint's security group. A developer who wants SSH supplies `sshPublicKey` for their box. The stack owns the key pair and AWS holds only the public key.

```shell
workbench ec2 ssh
```

There is no bastion host, overlay network, CIDR-locked port 22, or UDP-based shell.

## On the box

You log in as `ubuntu`. `agy` and `start-pi` run as `agent`: no sudo, no remote login, no IMDS, and egress only through the allowlist and the GPU box. Repos live in `/home/agent/workspace`, also linked as `~/workspace`.

```shell
cd ~/workspace/<repo>
agy
start-pi --gpu-box
```

## Bitbucket repositories

Use a Bitbucket repository access token over HTTPS for a private repository. Scope the token to that repository with Repository Read permission and add Repository Write only when the dev box must push branches.

Each developer runs this once on the box. Commits and the Bitbucket audit log use that person's identity, and there is no IAM or secrets surface for git:

```shell
git config --global credential.helper 'cache --timeout=28800'
clone-repo https://x-token-auth@bitbucket.org/WORKSPACE/REPOSITORY.git
```

`clone-repo` clones into `~/workspace` and removes group write from `.git`. The agent can read and edit the working tree but cannot change hooks, config, refs, or the index. The developer stages, commits, and pushes.

Later options, each a small separate change: a shared Secrets Manager token with a short credential helper, or SSH agent forwarding over SSH-through-SSM.

## GPU box

The GPU box has no public ingress. Its security group accepts port `11435` only from the dev box security groups. The dev box discovers the running GPU instance by its `aws-native-agent-workbench-gpu-llm` tag and uses its private IP.

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
- Phase 8: One `AwsNativeWorkbenchEc2Stack-<name>` per developer from `-c developers=alice,bob`. Each box has its own instance, security group, role, and `Name` tag `aws-native-agent-workbench-ec2-<name>`. The GPU box allows 11435 from every dev security group. `bin/workbench` selects a box with `WORKBENCH_DEV`, defaulting to the local username.
- Phase 9: Each EC2 stack ships a managed policy for that developer: `ssm:StartSession` only on their instance `Name` tag and the interactive/SSH/default session documents, `ssm:TerminateSession`/`ssm:ResumeSession` on their own sessions, start/stop of their instance, and the `ec2:Describe*` / `cloudformation:DescribeStacks` reads `bin/workbench` needs. Attach the policy ARN from `DeveloperAccessPolicyArn` to the developer's IAM identity. Account-level Session Manager runAs is not set, so the existing workbench is unchanged. `workbench ec2 ssm` still starts as `ubuntu`.
- Phase 11: Stack tests require one box per developer, distinct `Name` tags, no CIDR ingress, a minimal instance role, and GPU 11435 only from the dev security groups. Docs cover per-developer deploy, the developer IAM policy, and the `agent` user workflow.
- Phase 12: One `AwsNativeWorkbenchSharedStack` Instance Connect Endpoint. Dev box port 22 allows only that endpoint security group. `workbench ec2 ssh` and `workbench ec2 update --ssh` tunnel through the endpoint. `sshd` allows only `ubuntu`, with passwords and root login off.
- Limited GPU ingress to port `11435` from the dev box security groups.
- Changed GPU readiness checks to run over SSM on the GPU instance.
- Added `start-pi --gpu-box` on the dev box, using tag-based private-IP discovery.
- Removed every agent launcher, configuration, and dev-box install except Antigravity CLI and Pi.
- Removed Herdr and its runtime files.
- Added new `AwsNativeWorkbench*` stack names and `aws-native-agent-workbench-*` instance tags so this deployment cannot update, stop, or destroy the existing workbench resources.
- All deployable resources, IAM roles, security groups, GPU cache, and instances are owned only by the new stacks.
- The setup scripts, systemd units, and agent launchers the instances run ship as a zip in the CDK bootstrap bucket. User data and `workbench ec2 update` download that zip. The instances never clone this repository.
- Removed the GitHub App token chain from this branch. Work repos use a per-developer Bitbucket HTTPS token.
- Phase 7: Added `agent` user without sudo or remote login, sharing `/home/agent/workspace` via a setgid group. Blocked IMDS (`169.254.169.254`) and restricted egress via nftables and a root-owned tinyproxy egress filter with domain allowlist. `start-pi --gpu-box` resolves GPU IP as `ubuntu` and passes it to the `agent` process. Added an `agy` wrapper running inside the workspace as `agent`.
- Phase 10: Pinned and verified all installs (Node via SHA-256, AWS CLI via GPG, Ollama via SHA-256, Pi with `ignore-scripts = true`, Antigravity CLI via SHA-512). Dropped `curl | bash` and nodesource.

Existing DigitalOcean resources are not destroyed by this repository change. Delete them in DigitalOcean before switching branches if any are still running or billing.

Rebuild an existing dev box to remove agent binaries installed by the previous setup.

## Setup zip and updates

The instances only need the scripts they run. CDK zips those from the laptop checkout into the existing bootstrap bucket. Nothing new is created in the account.

Dev instance: `infra/aws/ec2/{setup-workbench.sh, agent-workbench-profile.sh, login-welcome, workbench-idle-stop, workbench-idle-stop.service, workbench-idle-stop.timer, tinyproxy.conf, agent-egress-allowlist.txt, nftables.conf}`, `bin/start-pi`, `tools/agents/start_pi.sh`, `tools/agents/local_llm.sh`.

GPU instance: `infra/aws/ec2/{setup-llm.sh, llm-idle-stop, llm-idle-stop.service, llm-idle-stop.timer}`, `tools/llm/ollama_inference_proxy.py`.

First boot installs unzip and the AWS CLI, downloads the zip with `aws s3 cp`, unpacks it to `/opt/agent-workbench`, and runs the setup script. The instance never clones this repository.

```shell
workbench ec2 update
```

That deploys `AwsNativeWorkbenchEc2Stack-<name>` (which uploads a new zip if the files changed), reads the zip's S3 URL from the stack outputs, and re-runs setup over SSM. `workbench ec2 update --ssh` does the on-box step through the Instance Connect Endpoint. The zip is whatever is checked out on the laptop. Redeploying with a new asset hash does not replace a running dev instance. The GPU instance is recreated on every `llm up`, so it always gets the current zip.

`start_pi.sh` allows `release-assets.githubusercontent.com` inside the laptop sandbox because Pi downloads from GitHub Releases. That is Pi tooling, not infra, and is not on the box code path.

If `AwsNativeWorkbenchTokenStack` was deployed from an earlier revision of this branch, destroy it. Do not destroy main's `AgentWorkbenchTokenStack` or the `/coding-agent-workbench/github/*` parameters.

## Security hardening

The boxes hold proprietary code and run an AI agent that reads it. Phases 7 through 12 are in the repo.

- No inbound ports from the internet. SSM by default. SSH is through an EC2 Instance Connect Endpoint; port 22 allows only that endpoint security group. GPU box accepts 11435 only from the dev box security groups.
- Minimal instance role: `AmazonSSMManagedInstanceCore`, `ec2:DescribeInstances`, and `s3:GetObject` on that setup zip's key only. An explicit deny on `ssm:GetParameter*` overrides the Parameter Store read that `AmazonSSMManagedInstanceCore` would otherwise grant, so the box cannot read the existing workbench's secrets.
- IMDSv2 with hop limit 1. Encrypted EBS, deleted on termination.
- Inference-only proxy on the GPU box. Telemetry disabled for agy and Pi. Unattended security upgrades. Idle stop, a 6-hour CloudWatch backstop, and a 12-hour fuse on the GPU box.
- Pi with `--gpu-box` keeps prompts inside the VPC. Antigravity uses Gemini under a zero-data-retention enterprise agreement.

Decisions that still hold:

- Stay in the default VPC public subnet with no internet CIDR ingress. A NAT gateway is about $33 a month plus $0.045 per GB and is not justified for two boxes that are stopped most of the day. Egress is enforced on the host instead. `fck-nat` on a `t4g.nano` (about $3 a month) is the upgrade path if network-level enforcement is later required.
- No SSM session content logging. CloudTrail already records `ssm:StartSession` with the caller and instance at no cost, which is the audit that matters.
- One dev box per developer. The GPU box stays shared.

### Phase 7: agent user with IMDS block and egress allowlist

Two Linux users, all configured by `setup-workbench.sh` as root:

- `ubuntu`: the developer. Logs in via SSM and keeps sudo.
- `agent`: no sudo, no remote login. `start-pi` and `agy` run as `agent` via `sudo -u agent -i`. Repos live in `/home/agent/workspace`, shared with `ubuntu` through a setgid group.

Root-owned nftables rules:

- `meta skuid agent ip daddr 169.254.169.254 reject`. The agent can never reach the instance role.
- Drop all outbound from uid `agent` except to a local proxy on `127.0.0.1` and to port 11435 inside the VPC CIDR, which setup reads from instance metadata.

A root-owned local proxy (tinyproxy) with a domain allowlist: `generativelanguage.googleapis.com`, `registry.npmjs.org`, `pypi.org`, `bitbucket.org`, the apt mirrors, and whatever the projects need. Entries are anchored regular expressions (`^pypi\.org$`), because tinyproxy matches an unanchored pattern anywhere in the hostname. `HTTPS_PROXY` and `HTTP_PROXY` are set in the agent user's environment. The allowlist lives in `infra/aws/ec2/` and ships in the asset bundle so it is versioned with the repo.

Root owns `/opt/agent-workbench`, the systemd units, the proxy config, and the nftables rules. The agent cannot change any of it.

The shared workspace is the one place both users write, and `ubuntu` has sudo. Anything the agent plants there that `ubuntu` later executes runs with full privileges. Three controls keep git from being that path:

- `clone-repo` strips group write from `.git`, so the agent cannot plant hooks or set `core.pager`, `core.fsmonitor`, `diff.external`, or an alias in the repo config. Setup also applies this to existing clones on every `workbench ec2 update`.
- `ubuntu`'s global `core.hooksPath` points at a root-owned empty directory, so hooks never run for the developer.
- `ubuntu` has `ignore-scripts = true`, so `npm install` in the workspace does not run lifecycle scripts.

`start-pi --gpu-box` looks up the GPU IP as `ubuntu` and passes it to the `agent` process.

Blast radius of a prompt-injected agent is its own workspace plus the allowlisted hosts.

### Phase 8: one box per developer

- CDK reads a `developers` context list, for example `-c developers=alice,bob`, and creates `AwsNativeWorkbenchEc2Stack-<name>` for each. Every box gets its own instance, security group, role, and `Name` tag `aws-native-agent-workbench-ec2-<name>`.
- The GPU box security group allows 11435 from every dev security group.
- `bin/workbench` picks a box by `WORKBENCH_DEV=<name>`, defaulting to the local username. `local_llm.sh` and the idle scripts are unaffected.
- Cost per extra box is the `t4g.large` hourly rate while running and about $2.40 a month for the 30 GB disk while stopped.

### Phase 9: scoped shell access

One IAM managed policy per developer, output as `DeveloperAccessPolicyArn`. Attach it to the identity that opens shells if that identity is not already Admin. An Admin user already has these permissions.

- `ssm:StartSession` only on their instance via `ssm:resourceTag/Name`, and only with the `AWS-StartInteractiveCommand`, `AWS-StartSSHSession`, and `SSM-SessionManagerRunShell` documents.
- `ssm:TerminateSession` and `ssm:ResumeSession` on their own sessions only.
- `ec2:StartInstances` and `ec2:StopInstances` on their instance tag, so `start-workbench` works.
- The `ec2:DescribeInstances`, `ec2:DescribeInstanceStatus`, `ec2:DescribeInstanceConnectEndpoints`, and `cloudformation:DescribeStacks` reads that `bin/workbench` needs.

Account-level Session Manager `runAsEnabled` is unset, because that preference is regional and would change the existing workbench. Instances are tagged `SSMSessionRunAs=ubuntu`. `workbench ec2 ssm` starts as `ubuntu` with `AWS-StartInteractiveCommand`.

### Phase 10: pinned and verified installs

Every binary uses a fixed version and a recorded checksum or signature, and fails closed.

| Tool | Method |
|---|---|
| Node | Official tarball from `nodejs.org/dist/v24.x.y/` verified against `SHASUMS256.txt`. |
| AWS CLI | Zip plus the published `.sig`, verified with AWS's GPG public key pinned in the script. |
| Ollama | Versioned tarball with a recorded sha256. |
| Pi | Pinned version with `--ignore-scripts`. The `agent` user also has `ignore-scripts = true` so project installs skip lifecycle scripts. |
| Antigravity CLI | Versioned tarball with a recorded sha512. |

Versions and hashes sit at the top of each setup script and are bumped deliberately, then rolled out with `workbench ec2 update`.

### Phase 11: security tests and docs

- `test/workbench-ec2-stack.test.ts`: one stack per developer, distinct `Name` tags, no CIDR ingress, instance role limited to SSM core, `ec2:DescribeInstances`, a read of the box zip key only, and a deny on Parameter Store reads.
- `test/workbench-llm-stack.test.ts`: port 11435 from each dev security group and no other ingress.
- This document and `docs/cloud-onetime-setup.md` cover the per-developer deploy, the IAM policy, and the `agent` user workflow.

### Phase 12: SSH through an EC2 Instance Connect Endpoint

Two connection paths, both with no inbound port from the internet. A developer picks one.

- SSM Session Manager. Needs the Session Manager plugin on the laptop.
- Plain `ssh` with their own keypair through an EC2 Instance Connect Endpoint. Needs only the AWS CLI, which `bin/workbench` already requires.

Infrastructure:

- One `AWS::EC2::InstanceConnectEndpoint` in the default VPC with its own security group, created once in `AwsNativeWorkbenchSharedStack` and used by every dev box. There is no hourly charge for the endpoint.
- Each dev box security group allows port 22 only from the endpoint security group.
- A developer who wants SSH supplies `sshPublicKey` for their box. The stack owns the key pair and AWS holds only the public key. Destroying the stack removes it.

Laptop SSH. `workbench ec2 ssh` resolves the instance ID by tag and opens a tunnel to the shared endpoint. Optional `~/.ssh/config` for the same path:

```text
Host i-*
  User ubuntu
  IdentityFile ~/.ssh/workbench_ed25519
  ProxyCommand aws ec2-instance-connect open-tunnel --instance-id %h --remote-port 22
```

The per-developer policy includes `ec2-instance-connect:OpenTunnel` on the endpoint, port 22, and that instance's private IP, plus `ec2:DescribeInstanceConnectEndpoints`.

Box setup:

- `sshd`: `PasswordAuthentication no`, `PermitRootLogin no`, `AllowUsers ubuntu`.
- `workbench ec2 update --ssh` re-runs setup through the endpoint.
- `workbench-idle-stop` counts an established port 22 connection as in use.
- The SSM agent stays installed on every box. The laptop-side `workbench llm up` readiness check uses it.

Tests require exactly one port 22 rule on the dev box, sourced from the endpoint security group, and no CIDR ingress.

### Remaining risk

Egress control is host-enforced rather than network-enforced. It depends on `agent` having no sudo and on the nftables rules being root-owned. If the security team wants network-level enforcement, add `fck-nat` with the same allowlist in front of both boxes.

The developer is the trust boundary for code in the workspace. Git hooks, repo config, and npm scripts are neutralised, but `make`, `npm run <script>`, `./scripts/*.sh`, or `source`-ing anything the agent wrote still runs as `ubuntu` with sudo. Read it first, exactly as you would with a pull request from a stranger. Removing `ubuntu`'s passwordless sudo would shrink that blast radius further and is a small follow-up if the team wants it.

DNS from the agent goes to `systemd-resolved` on loopback and out to the VPC resolver, so DNS tunnelling remains as a slow exfiltration channel.

## Deploy safety

Before any deploy, run `npm run synth` and `npx cdk diff`. The diff must show only `AwsNativeWorkbench*` stacks and no mention of `AgentWorkbench*`. Prefer `npm run changeset` and review in the CloudFormation console before executing. Destroy `AwsNativeWorkbenchTokenStack` only if it was ever deployed.

The remaining external installs are Node, AWS CLI, Ollama, Pi, and Antigravity CLI, all pinned and verified. None is github.com.


# Using Docker Sandbox

Would sbx be more isolated?

 Yes, meaningfully. sbx runs the agent in a microVM with its own kernel and its own Docker daemon, and routes all outbound TCP through a host proxy that enforces the network policy. A compromised agent has to escape a hypervisor rather
 than a uid. It also gives the agent a real Docker daemon, which the current setup can't offer safely.

 Does it need x86?

 Your instinct is right about the CLI: sbx supports arm64 Linux natively (version 0.33+, and it publishes  linux-arm64   .deb  packages). Your Mac runs it because Apple Silicon exposes virtualization to the guest.

 The real requirement is KVM, not x86. And on AWS that's where the arch constraint comes from:

   • Graviton (t4g, m7g, c7g, etc.) do not expose KVM. Only  .metal  Graviton instances do, and the cheapest of those is  c6g.metal  at about $2.18/hr.
   • As of Feb 2026, AWS supports nested virtualization on virtual instances, but only on Intel families: c8i, m8i, r8i, and their  -flex  variants, plus c7i, m7i and flex. Enabled with  --cpu-options NestedVirtualization=enabled  (also a
   launch-template property, so CDK can set it).

 So whoever said "x86" was right for AWS specifically, just for the wrong reason.

 Cheapest viable instance

 ┌──────────────────────────┬─────────────┬────────────────────────────────────┬─────────────────────────────────────────────────────────────────────────────────────────────────────┐
 │ Instance                 │ vCPU / RAM  │ On-demand (us-east-1)              │ Notes                                                                                               │
 ├──────────────────────────┼─────────────┼────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────┤
 │ t4g.large (current)      │ 2 / 8 GB    │ $0.067/hr                          │ No KVM. Dead end for sbx.                                                                           │
 ├──────────────────────────┼─────────────┼────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────┤
 │ m8i-flex.large           │ 2 / 8 GB    │ $0.10/hr                           │ Cheapest with nested virt. Tight: host + microVM + Docker in 8 GB.                                  │
 ├──────────────────────────┼─────────────┼────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────┤
 │ m8i-flex.xlarge          │ 4 / 16 GB   │ ~$0.20/hr                          │ My recommendation. Room for agy, a sandbox VM, and containers inside it.                            │
 ├──────────────────────────┼─────────────┼────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────┤
 │ c6g.metal                │ 64 / 128 GB │ $2.18/hr                           │ Only ARM option. Not worth it.                                                                      │
 └──────────────────────────┴─────────────┴────────────────────────────────────┴─────────────────────────────────────────────────────────────────────────────────────────────────────┘

 The  -flex  instances are 5% cheaper than plain m8i but can throttle under sustained load. For interactive dev that's fine. Since your idle-stop already keeps the box off most of the day, the roughly 3x hourly bump over t4g is a few
 dollars a month in practice.

 What switching would involve

   • Instance type to Intel, AMI parameter to  amd64 , set  NestedVirtualization=enabled  via the launch template (CDK  CfnLaunchTemplate   cpuOptions , you already have one for IMDS).
   • Install  docker-sbx  from Docker's apt repo, add  ubuntu  to the  kvm  group.
   • sbx wants Ubuntu 24.04+, which you have.
   • Then most of the Phase 7 machinery ( agent  user, nftables, tinyproxy, the agy wrapper) becomes redundant; the sandbox network policy replaces it, and you'd reuse  sandbox_bootstrap.sh  and the laptop-side  start_*.sh  flow that
   already exists in this repo. Prefer deleting that code over maintaining both.
   • One thing to verify on a real instance before committing: sbx docs say "your user in the  kvm  group" and the Arm guide says bare metal. The Intel nested-virt path is only months old, so run  kvm-ok  and  sbx run shell  on an m8i-flex
   before rewriting the stack.


## Remaining Hardening

 - storage.googleapis.com  is a public write target. Anyone can create a GCS bucket, so allowlisting the whole domain is a legitimate exfil route. It's needed for the agy download during setup, which runs through the proxy as  agent .
 Consider downloading agy as root and removing this domain from the runtime allowlist, or accept and document it.

 Smaller items

   •  AWS_CLI_GPG_KEY_ID  and  AWS_CLI_GPG_FINGERPRINT  are defined but never used in both setup scripts.  gpg --verify  accepts any key in root's keyring. On a fresh box that's only the pinned key, so fine today, but the fingerprint check
   is what makes it pinning. Use  gpgv --keyring <tempfile>  or check  VALIDSIG  from  --status-fd .
   •  ssm:TerminateSession  on  session/${aws:userid}-*  (workbench-ec2-stack.ts:204): session IDs are prefixed by IAM username or role-session-name, not  aws:userid . Verify this actually works for your identity type (especially SSO/
   assumed roles) before handing the policy out. AWS's own example uses  ${aws:username} .
   • IMDS block is IPv4 only. Fine today since IMDS IPv6 is off by default, but add  ip6 daddr fd00:ec2::254 reject  so it stays true if someone enables it.
   • DNS from  agent  goes to  systemd-resolved  on loopback, then out. DNS tunneling remains as a low-bandwidth exfil channel. Worth a line in "Remaining risk".
   •  nft -f  with  flush ruleset  wipes any other tables on the box. Nothing else exists now, just be aware if Docker/ufw ever gets added.
   • The  agy  wrapper (setup-workbench.sh:300) single-quotes  $target_dir  inside a  bash -c  string, so a directory name containing  '  breaks it. Self-inflicted by ubuntu only, so low, but  --chdir  or passing the path as an argument is
   cleaner.
   •  agy install || true  runs unverified post-install steps as  agent  through the proxy with errors swallowed. Not a security hole given the sandboxing, but you don't know what it did.
   • The inference proxy reads the whole request body into memory with no size limit. Only reachable from dev boxes, so DoS-only.
   • Both stacks use  associatePublicIpAddress: true  with all-outbound SGs. This is the documented, deliberate no-NAT decision, just noting the SG isn't where egress is enforced.
