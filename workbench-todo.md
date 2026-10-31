# Workbench to-do

## 1. Git
- [ ] Commit the operator stack changes on `main`.
- [ ] Merge `main` into `optional-skills-tools`.
- [ ] Push both branches. The box pulls from the remote.

## 2. Limited AWS profile (do this while you still have admin)
- [ ] If admin is your `[default]` profile, rename it to `[profile admin]` in `~/.aws/config` and `[admin]` in `~/.aws/credentials`.
- [ ] Deploy the operator stack: `cd infra/aws && npx cdk deploy AgentWorkbenchOperatorStack --profile admin`
- [ ] IAM console, user `agent-workbench-operator`, Security credentials: assign an MFA device, then create an access key for the CLI.
- [ ] Save the key: `aws configure --profile agent-workbench-keys`
- [ ] Add the `[default]` role block to `~/.aws/config`. Copy it from `infra/aws/README.md`, "Limited operator profile", and fill in account ID, MFA device name, and region.
- [ ] Check it works: `workbench ec2 status` should ask for an MFA code, then show the box.

## 3. Update the box
- [ ] `workbench ec2 up`
- [ ] `workbench ec2 update optional-skills-tools`
- [ ] Remove the old Exa settings. From the repo root: `ssh ubuntu@agent-workbench 'bash -s' < remove-exa.sh`. It should end with "No Exa settings left."
- [ ] Check versions on the box: `claude --version` is 2.1.316, `codex --version` is 0.166.0, `opencode --version` is 2.2.5.

## 4. Lock down and clean up
- [ ] Remove the admin profile from `~/.aws/config` and `~/.aws/credentials`. From now on, do admin tasks (Tailscale key rotation, operator stack changes) in the AWS console.
- [ ] Delete `remove-exa.sh` and this file.
- [ ] When you finish an AWS session: `rm -rf ~/.aws/cli/cache`
