# AI Coding Agent Workbench

An AWS-only workbench for Antigravity CLI and Pi.

## Install local commands

```shell
./bin/install-commands
```

## Local Docker sandboxes

Requirements:

- Docker Desktop
- [Docker Sandboxes (`sbx`)](https://docs.docker.com/ai/sandboxes/get-started/)
- Credentials for the agent you use

From the repository the agent should edit:

```shell
start-antigravity
start-pi
```

Pass a project path when needed. Add `--clone` to expose only committed files:

```shell
start-pi --clone /path/to/project
```

Pi can use a local Ollama model:

```shell
start-pi --local-model
```

See [Local LLM](docs/local-llm.md).

## AWS workbench

Each developer gets a persistent EC2 dev box. A shared GPU box is optional.

Prerequisite: complete the [one-time setup](docs/cloud-onetime-setup.md) and deploy the [AWS stacks](infra/aws/README.md).

### Daily workflow

1. On a laptop, start the box and open a terminal on it. This boots the instance if it is stopped and drops you into a shell as `ubuntu`:

   ```shell
   start-workbench
   ```

2. First day only, on the box, clone a repo into the shared workspace with a Bitbucket access token. After that, `git pull` as usual:

   ```shell
   git config --global credential.helper 'cache --timeout=28800'
   clone-repo https://x-token-auth@bitbucket.org/WORKSPACE/REPO.git
   ```

3. On the box, go to the repo and start an agent. It runs as the locked-down `agent` user:

   ```shell
   cd ~/workspace/REPO
   # start antigravity:
   agy
   ```

4. Review what the agent changed, then commit and push. The agent cannot commit:

   ```shell
   git diff
   git add -A && git commit
   git push
   ```

5. Close the terminal when you are done. The box stops itself after 15 idle minutes. To stop it right away, from the laptop:

   ```shell
   workbench ec2 down
   ```

### Using the GPU box with Pi

Only when you want prompts to stay inside the VPC. On the laptop, then on the box:

```shell
workbench llm up          # laptop, takes a few minutes
start-pi --gpu-box        # box, inside your repo
```

The GPU box stops itself when idle and has a 12-hour hard limit. `workbench llm down` removes it now.

### Other commands

| From the laptop | What it does |
|---|---|
| `workbench ec2 status` | Is my box running |
| `workbench ec2 ssh` | Connect with plain SSH instead of SSM |
| `workbench ec2 update` | Push the latest setup scripts to the box |
| `workbench llm status` | Is the GPU box running |

`WORKBENCH_DEV=<name>` picks a different developer's box. It defaults to your local username.

## Reference

- [AWS-native access](docs/aws-native-access.md)
- [AWS deployment](infra/aws/README.md)
- [Cloud one-time setup](docs/cloud-onetime-setup.md)
- [Local LLM](docs/local-llm.md)
