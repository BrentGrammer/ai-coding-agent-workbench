# AWS-native access (no Tailscale)

Plan for this branch. Replaces the Tailscale path with AWS-native networking. Nothing here is built yet.

Related: [issue #33](https://github.com/BrentGrammer/ai-coding-agent-workbench/issues/33).

## Goal

Laptop connects to the **dev box**. From there, run agents on the dev box, and optionally the GPU box for Qwen 3.8 27B. Tailscale is removed from this branch entirely. No extra bastion host.

```
laptop --(SSM or CIDR-locked SSH)--> dev box --(VPC, port 11435)--> GPU box
```

## How you connect

Two ways in, both to the dev box. Default is SSM. SSH is opt-in.

### 1. SSM Session Manager (default)

No inbound ports. IAM is the lock. Sessions go to CloudTrail.

```
start-workbench
# same as: workbench ec2 up && workbench ec2 ssm
```

Needs the Session Manager plugin on the laptop (`brew install --cask session-manager-plugin`). Mosh does not work over SSM (no UDP), so this is an SSM shell, not mosh.

Session Manager starts as `ssm-user`. Setup should land that session in ubuntu's home, where the agents live.

### 2. SSH from your IP (optional, no bastion)

A dedicated bastion is extra machinery for the same hop. Open port 22 on the **dev box** to one CIDR instead.

Deploy with both:

- `sshCidr` — e.g. `203.0.113.4/32`
- `sshKeyName` (an EC2 key pair) or `sshPublicKey` (contents of `~/.ssh/id_ed25519.pub`)

Then `workbench ec2 ssh` uses the public IP. Home IPs change; SSM does not care. If `sshCidr` is unset, port 22 stays closed.

## GPU box

Unchanged except the network path: zero inbound from the internet, inference proxy on 11435, model cache, idle stop, teardown.

The workbench security group may reach the GPU security group on **11435 only**. Agents on the dev box call the GPU box by **private IP** (looked up from the `agent-workbench-gpu-llm` tag), not MagicDNS.

`--gpu-box` runs **on the workbench**, over the VPC. From a laptop it should fail with a short message to connect first.

`workbench llm up` still deploys from the laptop. Readiness wait should probe the GPU box over SSM (`curl` to `127.0.0.1:11435` on the instance), not from the laptop's network.

## What to remove

Tailscale everywhere: install and `tailscale up` on both boxes, Parameter Store auth keys, IAM `ssm:GetParameter` for those keys, MagicDNS / `tailscale status` discovery, `sync-host`, mosh as the default connect, tailnet checks in idle-stop, and the Tailscale sections in docs.

Idle-stop keeps counting SSM sessions (and real SSH on 22) as in use.

## DigitalOcean GPU

This branch does not use Tailscale, so the DO path cannot join a tailnet either. Open SSH on the droplet firewall (key is already registered). Keep 11435 off the public internet. The AWS workbench cannot reach a DO GPU over VPC; `--gpu-box` from the workbench is the AWS GPU box.

## Stack changes (sketch)

**Workbench CDK**

- Drop Tailscale key IAM.
- Allow `ec2:DescribeInstances` so the box can find the GPU private IP.
- Export the workbench security group id.
- If `sshCidr` is set, ingress TCP 22 from that CIDR, and install the SSH key. Synth should fail if CIDR is set without a key.

**GPU CDK**

- Drop Tailscale key IAM.
- Ingress TCP 11435 from the imported workbench security group.

**CLI**

- `start-workbench` → SSM.
- `workbench ec2 ssm` / `workbench ec2 ssh`.
- Drop `mosh` and `sync-host`.
- `workbench ec2 update` via SSM, not Tailscale SSH.
- `wait_llm_ready` via SSM on the GPU instance.

**Launchers**

- Replace Tailscale IP lookup with the GPU instance private IP when running on the workbench.
