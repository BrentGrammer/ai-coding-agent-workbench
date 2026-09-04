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

## Bitbucket repositories

Use a Bitbucket repository access token over HTTPS for a private repository. Scope the token to that repository with Repository Read permission and add Repository Write only when the dev box must push branches.

Store the token in AWS Secrets Manager or Parameter Store, not in the repository or an environment file. Supply it through a Git credential helper and clone with:

```shell
git clone https://x-token-auth@bitbucket.org/WORKSPACE/REPOSITORY.git
```

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

Existing DigitalOcean resources are not destroyed by this repository change. Delete them in DigitalOcean before switching branches if any are still running or billing.

Rebuild an existing dev box to remove agent binaries installed by the previous setup.

## Plan: remove the GitHub dependency

The box is meant for work repositories and must not depend on github.com. Today it still does in two ways.

### Current dependencies

| Dependency | Where |
|---|---|
| Boot-time `git clone --branch main` of the public repo | `workbench-ec2-stack.ts`, `workbench-llm-stack.ts` user data |
| `workbench ec2 update` runs `git fetch` and `reset --hard` on the box | `bin/workbench` |
| GitHub App token chain: token stack, Lambda, relay service, credential helper, `lambda:InvokeFunction` on the instance role, `GITHUB_APP_TOKEN_FUNCTION_NAME` in `workbench.env` | `lib/workbench-token-stack.ts`, `lambda/github-app-token/`, `infra/aws/runtime/`, `ec2/github-token-relay*`, `setup-workbench.sh` |
| `DEFAULT_REPO_URL` and `repoUrl` context | both stacks, README |

The `main` clone is also a correctness bug. Until this branch merges, a fresh box runs main's setup script, which installs Tailscale and every agent CLI, then fails on a parameter the new instance role cannot read.

Not in scope: `start_pi.sh` allows `release-assets.githubusercontent.com` inside the laptop sandbox because Pi downloads from GitHub Releases. That is Pi tooling, not infra, and is not on the box code path.

### Files the boxes need

Dev box: `infra/aws/ec2/{setup-workbench.sh, agent-workbench-profile.sh, login-welcome, workbench-idle-stop, workbench-idle-stop.service, workbench-idle-stop.timer}`, `bin/start-pi`, `tools/agents/start_pi.sh`, `tools/agents/local_llm.sh`.

GPU box: `infra/aws/ec2/{setup-llm.sh, llm-idle-stop, llm-idle-stop.service, llm-idle-stop.timer}`, `tools/llm/ollama_inference_proxy.py`.

On the box, `start_pi.sh` exits before it reaches `local_workspace.sh` and `sandbox_bootstrap.sh`, so those stay laptop-only.

### Phase 1: ship box files as a CDK asset

1. In both stacks, create an `aws-s3-assets.Asset` from the repo root with an `exclude` list so only the files above are zipped. The asset uploads to the existing CDK bootstrap bucket. Nothing new is created in the account.
2. Replace `apt-get install git` and `git clone` in user data with `userData.addS3DownloadCommand`, then `unzip -o` into `/opt/agent-workbench`, `chown -R root:root`, and run the setup script. User data installs `unzip` and the AWS CLI before the download.
3. `asset.grantRead(role)` on each instance role. Remove `githubTokenFunction.grantInvoke(role)`.
4. `AwsNativeWorkbenchEc2Stack` outputs `BoxFilesS3Url` so the update path can find the current bundle.
5. Remove `DEFAULT_REPO_URL`, the `repoUrl` context read, and the `githubTokenFunction` stack prop.

Redeploying with a new asset hash is harmless to a running dev box. `ec2.Instance` does not replace on user-data change by default, and cloud-init runs user data once. The GPU box is recreated on every `llm up`, so it always gets the current bundle.

### Phase 2: replace `workbench ec2 update`

1. `npx cdk deploy AwsNativeWorkbenchEc2Stack --require-approval never` uploads the new bundle.
2. Read `BoxFilesS3Url` from `aws cloudformation describe-stacks`.
3. One SSM interactive command: `aws s3 cp` the bundle, `rm -rf /opt/agent-workbench`, `unzip` it back, `chown -R root:root`, run `setup-workbench.sh`.
4. Drop the branch argument and its validation. The bundle is whatever is checked out on the laptop, which matches how `cdk deploy` already behaves.

### Phase 3: remove the GitHub App chain

Delete `lib/workbench-token-stack.ts`, `lambda/github-app-token/`, `infra/aws/runtime/`, `ec2/github-token-relay-service.mjs`, and `ec2/github-token-relay.service`.

Edit:

- `app.ts` goes to three stacks.
- `setup-workbench.sh` drops the relay and credential-helper installs, the relay service, the `git config --global credential.*` lines, and the token-function warning. `git` stays in the apt list for work repos.
- `workbench.env` becomes `AWS_REGION`, `LOCAL_LLM_MODEL`, `WORKBENCH_INSTANCE=true`.
- `package.json` `deploy`, `diff`, and `synth` scripts drop the token stack.

None of this touches main's `AgentWorkbenchTokenStack` or the `/coding-agent-workbench/github/*` parameters.

### Phase 4: git auth for work repositories

Start with manual auth and no AWS resources. Each developer runs once on the box:

```shell
git config --global credential.helper 'cache --timeout=28800'
git clone https://x-token-auth@bitbucket.org/WORKSPACE/REPO.git
```

Each person's commits and Bitbucket audit log use their own identity, and there is no new IAM or secrets surface. `login-welcome` gets a two-line hint for this.

Later options, each a small separate change:

- Shared token: an `aws-native-agent-workbench/bitbucket-token` Secrets Manager secret, a short credential helper that calls `get-secret-value`, and `secret.grantRead(role)`.
- SSH agent forwarding over SSH-through-SSM (`ProxyCommand aws ssm start-session --document-name AWS-StartSSHSession`). Needs the optional SSH ingress path, so not the default.

### Phase 5: tests

- `test/workbench-ec2-stack.test.ts`: remove the fake token Lambda. Assert no `AWS::Lambda::Function`, user data has `aws s3 cp` and no `git clone`, and the instance role grants `s3:GetObject` only on the asset bucket. Keep the SSH context validation asserts.
- `test/workbench-llm-stack.test.ts`: assert no `git clone` in user data and `s3:GetObject` for the asset. Existing spot and on-demand asserts stay.
- Add a `test` script to `package.json` that runs both.

### Phase 6: docs and CLI text

- `docs/cloud-onetime-setup.md`: remove the GitHub App parameter steps. Setup becomes bootstrap CDK if needed, `npm run deploy`, `start-workbench`.
- This document: describe the asset bootstrap and the new update flow once implemented.
- `infra/aws/README.md`: three stacks, no `repoUrl`.
- `bin/workbench` usage text and `login-welcome`.

### Order and safety

Do phases 1 and 3 together since they touch the same lines, then 2, 5, 6. Before any deploy, run `npm run synth` and `npx cdk diff`. The diff must show only `AwsNativeWorkbench*` stacks and no mention of `AgentWorkbench*`. Destroy `AwsNativeWorkbenchTokenStack` only if it was ever deployed.

After this, the remaining external installs are Pi from npm and Antigravity CLI from `antigravity.google`. Neither is github.com.
