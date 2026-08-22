# Cloud workbench

The AWS setup creates one persistent EC2 instance. It installs Herdr and four harnesses: Claude Code, Codex, Cursor, and OpenCode.

## Deploy

Do the [cloud one-time setup](cloud-onetime-setup.md) first: Tailscale access, the GitHub App, and the SSM parameters.

See [infra/aws/README.md](../infra/aws/README.md) for deployment instructions.

## Connect and run

Connect to the instance:

```shell
start-workbench
```

Then run a harness in a repository:

```shell
cd ~/workspace/project
start-herdr codex
```

The harnesses use their normal authentication and model defaults unless `--gpu-box` is selected for OpenCode. See [Local LLM](local-llm.md#from-the-ec2-workbench-box) for that path.

## Security

The cloud security design remains in place: no inbound security-group rules, Tailscale and SSM access, verified SSH host keys, short-lived repository-scoped GitHub tokens, IMDSv2 isolation, secret-read controls, and automatic idle shutdown.
