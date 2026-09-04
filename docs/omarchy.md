# Omarchy host setup

## Local sandboxes

Install Docker Sandboxes and enable KVM:

```shell
omarchy pkg aur add docker-sbx
sudo usermod -aG kvm "$USER"
```

Sign out and back in, then initialize the sandbox policy:

```shell
sbx login
sbx diagnose
sbx policy init deny-all
```

Install the repository commands and run an agent:

```shell
./bin/install-commands
start-antigravity
start-pi
```

## AWS connection

Install the AWS CLI and Session Manager plugin, authenticate, then use `start-workbench`. SSM is the default connection and needs no inbound port.
