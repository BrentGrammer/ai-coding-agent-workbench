# Omarchy Host Setup

Run the local Docker Sandbox workflow and connect to the AWS workbench from Omarchy.

Docker does not officially test or support Arch Linux. This project is tested on Omarchy with `docker-sbx` 0.39.0 from the AUR. The package wraps Docker's official archive and preserves the complete runtime layout that `sbx` needs. Review its third-party build recipe before installing it.

## Local sandbox prerequisites

Omarchy needs Docker Engine, KVM, and Docker Sandboxes:

```shell
omarchy pkg aur add docker-sbx
sudo usermod -aG kvm "$USER"
```

Sign out and back in after changing group membership. Confirm that Docker and KVM are available:

```shell
docker info
ls -l /dev/kvm
```

Initialize Docker Sandboxes:

```shell
sbx login
sbx diagnose
sbx policy init deny-all
```

`sbx diagnose` should pass all checks, including KVM, storage, daemon health, and authentication. The workbench launcher starts Docker Engine through systemd if it is stopped. Host Docker and the isolated Docker Engine inside each sandbox are separate.

Install the workbench commands from the repository:

```shell
./bin/install-commands
```

Open a new terminal, change to a project, and start a harness:

```shell
cd /path/to/project
start-codex
```

The launcher creates or reuses a persistent sandbox for that project. Do not use `agent` as the Omarchy username because `/home/agent` is the sandbox user's home.

## Local models

Linux uses `qwen3.8:27b` instead of the macOS MLX model. See [Local LLM](local-llm.md) for Ollama prerequisites and launcher commands.

The inference proxy stays on host loopback and is reached from the sandbox through `host.docker.internal`. Allowlist only the inference proxy on `localhost:11435`. Never allowlist Ollama's management API on port `11434`.

## AWS workbench connection

Install the host connection tools:

```shell
omarchy pkg add mosh aws-cli-v2 tailscale
sudo systemctl enable --now tailscaled
sudo tailscale up
```

If Tailnet Lock reports that the machine is locked out, approve it from an existing trusted signing device. An untrusted machine cannot sign itself.

Authenticate AWS and verify both connections:

```shell
aws login
aws sts get-caller-identity
tailscale ping agent-workbench
```

Then start or connect to the EC2 workbench:

```shell
start-workbench
```

## Terminal

Use a terminal with OSC 52 clipboard support for Herdr, such as Alacritty or Ghostty. The workbench keeps `TERM=xterm-256color` for Mosh compatibility.
