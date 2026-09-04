# Cloud one-time setup

## GitHub App

The workbench uses a GitHub App to mint one-hour, repository-scoped tokens. The EC2 instance never receives the private key. If the two parameters below already exist for the current workbench, reuse them without changing their values.

1. Create a GitHub App with repository **Contents** read and write permission.
2. Disable webhooks and install the app on the repositories the workbench may access.
3. Store its App ID and private key in AWS Systems Manager Parameter Store:

   ```shell
   aws ssm put-parameter --type String \
     --name /coding-agent-workbench/github/app-id \
     --value '<app-id>'

   aws ssm put-parameter --type SecureString \
     --name /coding-agent-workbench/github/private-key \
     --value file://path/to/private-key.pem
   ```

Delete the downloaded private-key file after storing it.

## Laptop tools

Install the AWS CLI, Node.js, and the Session Manager plugin. On macOS:

```shell
brew install awscli node
brew install --cask session-manager-plugin
```

Configure AWS credentials and bootstrap CDK in the target account and region.

## Optional SSH

SSM needs no SSH configuration. To enable SSH, deploy with a single client CIDR and either an existing EC2 key-pair name or public-key contents:

```shell
npx cdk deploy AwsNativeWorkbenchEc2Stack \
  -c sshCidr=203.0.113.4/32 \
  -c sshKeyName=agent-workbench
```

Leave `sshCidr` unset to keep port 22 closed.

With `sshKeyName`, keep the matching private key on the laptop. With `sshPublicKey`, AWS receives only the public key and the existing private key stays on the laptop:

```shell
npx cdk deploy AwsNativeWorkbenchEc2Stack \
  -c sshCidr=203.0.113.4/32 \
  -c sshPublicKey="$(cat ~/.ssh/id_ed25519.pub)"
```

OpenSSH automatically tries standard keys and keys loaded into `ssh-agent`. For a key stored elsewhere:

```shell
WORKBENCH_EC2_SSH_KEY=~/.ssh/agent-workbench workbench ec2 ssh
```

A `.ppk` file is only needed by PuTTY. The macOS and Linux commands use OpenSSH keys.

## GPU quota

Before the first `workbench llm up`, request four vCPUs for both **All G and VT Spot Instance Requests** and **Running On-Demand G and VT instances** in the deployment region.
