# Cloud one-time setup

The deploy reads three secrets from AWS Systems Manager Parameter Store: a Tailscale auth key, and a GitHub App ID and private key. Create them before you deploy following Steps 1 and 2 below.

## 1. Tailscale access

1. Sign in to the Tailscale app on your local machine.
2. In the Tailscale admin console, open **Access controls**. Add a tag for the workbench, a grant that lets your devices reach the workbench, and an SSH rule for the tag:

   ```json
   "tagOwners": { "tag:workbench": ["autogroup:admin"] },
   "grants": [
     { "src": ["autogroup:member"], "dst": ["autogroup:self", "tag:workbench"], "ip": ["*"] }
   ],
   "ssh": [
     { "action": "accept", "src": ["autogroup:member"], "dst": ["tag:workbench"], "users": ["ubuntu", "root"] }
   ]
   ```

   The `ssh` rule is required. The default rule that Tailscale ships covers only your own untagged devices, and the workbench is tagged. If your policy file still has the default allow-all grant (`"src": ["*"], "dst": ["*"]`), remove it.

3. In **Settings → Keys**, create an auth key: **Reusable**, **Pre-approved**, tag `tag:workbench`, make sure it is not marked as ephemeral.

4. If tailnet lock is on, sign the key on a trusted machine (your laptop) and keep the signed key that this command prints:

   ```shell
   tailscale lock sign tskey-auth-...
   ```

5. Store the key that's printed in the terminal after the above command:

   ```shell
   aws ssm put-parameter --type SecureString \
     --name /coding-agent-workbench/tailscale/auth-key \
     --value 'tskey-auth-...'
   ```

An auth key expires after 90 days. That only matters when you rebuild the box after the key expires. Repeat steps 3 to 5 to refresh it.

## 2. GitHub App

One GitHub App gives repository access without a permanent token for each repository. The box never holds the private key. It can only call the token Lambda, which returns a one-hour token for one repository.

1. Open GitHub **Settings → Developer settings → GitHub Apps → New GitHub App**.
2. Give the app a unique name and use an appropriate GitHub page as its homepage URL.
3. Disable **Active** under Webhook, because this workbench does not receive webhooks.
4. Under Repository permissions, set **Contents** to **Read and write**.
5. Leave callback URLs, user authorization, device flow, post-installation setup, and the IP allow list unset.
6. Create the app and note its **App ID**.
7. Generate and download a private key. Do not generate a client secret, because this workbench does not use OAuth. If macOS offers to import the PEM file into Keychain, cancel the import.
8. Choose **Install App** and install it on the account or organization that holds your repositories. Choose **All repositories**, or keep an explicit selected list.
9. Store both values:

   ```shell
   aws ssm put-parameter --type String \
     --name /coding-agent-workbench/github/app-id \
     --value '<app-id>'

   aws ssm put-parameter --type SecureString \
     --name /coding-agent-workbench/github/private-key \
     --value file://path/to/private-key.pem
   ```

Do not commit the PEM key, put it in an environment file, or paste it into logs. Delete the downloaded file after you store it.

## 3. Deploy and connect

1. Deploy the stacks — see [infra/aws/README.md](../infra/aws/README.md).
2. Wait 3 to 5 minutes after the deploy. The box joins your tailnet by itself on first boot, using the auth key from Parameter Store.

   If SSH fails with `tailnet policy does not permit you to SSH to this node`, the box joined and your policy file is missing the `ssh` rule from step 1. Add it and retry. If the box never appears on the tailnet, get in with `workbench ec2 ssm` and run `sudo tailscale up --ssh`.
3. In a local terminal, from any directory, run `start-workbench` to connect. Then log in each agent once on the box: `claude`, `codex`, `opencode auth login`, `cursor-agent login`.

   A replaced instance has new SSH host keys, so `start-workbench` fails with `REMOTE HOST IDENTIFICATION HAS CHANGED`. Run `workbench ec2 trust-host`. It reads the key over SSM, which AWS authenticates and which does not use SSH, prints the fingerprint for you to compare, and refreshes `known_hosts`. Do not delete the entry by hand — that trusts whatever answers.
4. Set the git identity once on the box: `git config --global user.name` / `user.email`.
5. Clone your repositories on the box, using the HTTPS URL:

   ```shell
   mkdir -p ~/workspace
   git clone https://github.com/<owner>/<repo>.git ~/workspace/<repo>
   ```

   No credential prompt appears — the box mints a short-lived GitHub token for each Git operation via the AWS Lambda setup in CDK. This only works for HTTPS URLs, not `git@github.com:...` SSH ones.
## 4. Recommended hardening

Do these in order:

1. Confirm MFA on the account behind your Tailscale login (GitHub or Google). The tailnet is only as strong as that account.
2. Enable [tailnet lock](https://tailscale.com/kb/1226/tailnet-lock) so a compromised Tailscale control server cannot add a rogue device. Print each device's key with `tailscale lock` (on the Mac the CLI lives at `/Applications/Tailscale.app/Contents/MacOS/Tailscale`). Then, on the box, pass both `tlpub:` keys to one command: `sudo tailscale lock init tlpub:BOX-KEY tlpub:MAC-KEY`. Store the printed disablement secrets somewhere durable outside both devices — an SSM SecureString parameter works well. They are the only recovery if both devices are lost.
3. Keep the tailnet single-user: no invites, no shared nodes. Tailscale SSH means tailnet membership is shell access to the box.
4. Adding a future device needs a signature from a trusted one: `tailscale lock sign <nodekey>`.

## 5. GPU quotas (local LLM only)

The optional GPU box (`workbench llm up`) tries Spot capacity first and falls back to On-Demand capacity when Spot is unavailable. AWS has separate G-family vCPU quotas for Spot and On-Demand instances. New accounts often have a limit of 0. Request 4 vCPUs for both quotas in your region before the first `workbench llm up`.

Use the AWS CLI, or open the AWS console in region `us-west-2` and go to **Service Quotas → Amazon EC2 → search for the quota name → Request quota increase**. Request 4 vCPUs for both **All G and VT Spot Instance Requests** and **Running On-Demand G and VT instances**. AWS reviews each request. Wait for approval before `workbench llm up`.

## 6. GPU AMI

The GPU box runs the AWS Deep Learning Base OSS AMI, which ships the NVIDIA driver and CUDA. `setup-llm.sh` installs no driver and never reboots, so a wrong AMI fails the deploy. Confirm the parameter name exists in your region once, before the first `workbench llm up`:

```shell
aws ssm get-parameters-by-path \
  --path /aws/service/deeplearning \
  --recursive \
  --query 'Parameters[?contains(Name, `base-oss`)].Name'
```

If the name differs from `DEFAULT_GPU_AMI_PARAMETER` in `infra/aws/lib/workbench-llm-stack.ts`, pass the right one instead of editing the file:

```shell
npx cdk deploy AgentWorkbenchLlmStack -c llmAmiParameter=<path>
```

Use the **Base OSS** variant. The full Deep Learning AMI adds PyTorch, TensorFlow, and Conda that this box never uses, and needs a much larger disk.

## 7. GPU auth key

The GPU box uses its own key, at `/coding-agent-workbench/tailscale/llm-auth-key`. Do not reuse the workbench key from [step 1](#1-tailscale-access).

In **Settings → Keys**, create an auth key: **Reusable**, **Ephemeral**, **Pre-approved**, tag `tag:workbench`.

Ephemeral is the opposite of the workbench key, on purpose. That box stops and starts, so its node must survive being offline. This box terminates when it goes idle and gets rebuilt, so without ephemeral a dead node piles up on the tailnet every time.

If tailnet lock is on, sign the key and store the longer string the command prints:

```shell
tailscale lock sign tskey-auth-...
```

```shell
aws ssm put-parameter --type SecureString --overwrite \
  --name /coding-agent-workbench/tailscale/llm-auth-key \
  --value 'SIGNED-KEY'
```

Then revoke the old key. Signing covers the key, not each box, so every rebuild joins on its own until the key expires at 90 days.
