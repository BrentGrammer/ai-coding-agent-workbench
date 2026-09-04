# Cloud one-time setup

## Laptop tools

Install the AWS CLI, Node.js, and the Session Manager plugin. On macOS:

```shell
brew install awscli node
brew install --cask session-manager-plugin
```

Configure AWS credentials and bootstrap CDK in the target account and region if that account has not been bootstrapped.

Set the developer list in `infra/aws/cdk.json` context, or pass it on every deploy. Names become stack suffixes and instance tags. `bin/workbench` selects a box with `WORKBENCH_DEV`, which defaults to the local username.

```shell
cd infra/aws
npm ci --ignore-scripts
npx cdk bootstrap
npm run changeset -- -c developers=alice
```

That prepares CloudFormation change sets and does not execute them. Review each `AwsNativeWorkbench*` stack in the console Change sets tab, then execute there if it looks right.

`npm run deploy` uses the same stack filter and applies immediately. If `developers` is unset, it creates one box named after the local username.

## Daily shell identity

Keep the Admin profile for CDK. Attach the EC2 stack output `DeveloperAccessPolicyArn` to the IAM user, role, or Identity Center permission set that will open shells:

```shell
aws cloudformation describe-stacks \
  --stack-name AwsNativeWorkbenchEc2Stack-alice \
  --query "Stacks[0].Outputs[?OutputKey=='DeveloperAccessPolicyArn'].OutputValue" \
  --output text
```

Then connect:

```shell
start-workbench
```

## Optional SSH

SSM needs no SSH configuration. Port 22 is reachable only from the Instance Connect Endpoint. To enable SSH on a box, include that developer's public key when you create the change set. The stack owns the key pair. `sshCidr` and `sshKeyName` are gone.

```shell
npm run changeset -- \
  -c developers=alice \
  -c sshPublicKey="$(cat ~/.ssh/id_ed25519.pub)"
```

For more than one developer, pass `sshPublicKey-<name>`:

```shell
npm run changeset -- \
  -c developers=alice,bob \
  -c sshPublicKey-alice="$(cat ~/.ssh/id_ed25519.pub)"
```

Then:

```shell
workbench ec2 ssh
```

OpenSSH automatically tries standard keys and keys loaded into `ssh-agent`. For a key stored elsewhere:

```shell
WORKBENCH_EC2_SSH_KEY=~/.ssh/workbench_ed25519 workbench ec2 ssh
```

A `.ppk` file is only needed by PuTTY. The macOS and Linux commands use OpenSSH keys.

## On the box

You log in as `ubuntu` and keep sudo. Agents do not.

`agy` and `start-pi` switch to the `agent` user. That user has no sudo, no remote login, and cannot reach the instance role. Its outbound traffic goes through a root-owned proxy allowlist, plus the GPU box on port `11435`.

Repos live in `/home/agent/workspace`, which is also `~/workspace` for `ubuntu`. Clone there with your Bitbucket HTTPS token, then start an agent:

```shell
git config --global credential.helper 'cache --timeout=28800'
git clone https://x-token-auth@bitbucket.org/WORKSPACE/REPOSITORY.git
cd ~/workspace/REPOSITORY
agy
start-pi --gpu-box
```

Do not run agents as `ubuntu`. After `workbench llm up` on the laptop, `start-pi --gpu-box` looks up the GPU private IP as `ubuntu` and passes it into the `agent` process.

## GPU quota

Before the first `workbench llm up`, request four vCPUs for both **All G and VT Spot Instance Requests** and **Running On-Demand G and VT instances** in the deployment region.
