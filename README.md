# AI Coding Agent Workbench

An AWS-only workbench for Antigravity CLI and Pi. Both agents can also run in local Docker sandboxes on macOS or Omarchy.

## Install local commands

```shell
./bin/install-commands
```

## Local Docker sandboxes

Requirements:

- Docker Desktop on macOS, or Docker Engine on [Omarchy](docs/omarchy.md)
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

The AWS deployment creates a persistent EC2 dev box and an optional GPU box. SSM Session Manager is the default connection. CIDR-locked SSH is optional. No third-party network or cloud provider is used.

Complete the [one-time setup](docs/cloud-onetime-setup.md), deploy the [AWS stacks](infra/aws/README.md), then connect:

```shell
start-workbench
```

On the dev box, clone repositories under `~/workspace` and run either installed CLI:

```shell
agy
pi
```

The GPU box is reachable only from the dev box over the VPC on port `11435`. After `workbench llm up` on the laptop, run `start-pi --gpu-box` on the dev box.

## Reference

- [AWS-native access](docs/aws-native-access.md)
- [AWS deployment](infra/aws/README.md)
- [Cloud one-time setup](docs/cloud-onetime-setup.md)
- [Local LLM](docs/local-llm.md)
