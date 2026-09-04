# Local LLM

Pi can use an Ollama model on the local host:

```shell
start-pi --local-model
```

Requirements:

- macOS: Ollama, `python3`, `jq`, and `qwen3.8:27b-mlx`
- Linux: Ollama, `python3`, `jq`, and `qwen3.8:27b`

The launcher exposes only the inference proxy on port `11435`. Ollama's management API remains on loopback port `11434`.

Stop launcher-owned processes with:

```shell
stop-local-llm
```

## AWS GPU box

The optional AWS GPU box serves `qwen3.8:27b` through the same inference-only proxy:

```shell
aws-workbench llm up
aws-workbench llm status
aws-workbench llm down
```

The service is not exposed to the laptop or public internet. Only the AWS dev box security group can reach port `11435`. The dev box can find the running instance and private IP with:

```shell
aws ec2 describe-instances \
  --filters 'Name=tag:Name,Values=aws-native-agent-workbench-gpu-llm' \
            'Name=instance-state-name,Values=running' \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text
```

From the dev box, Pi performs that lookup and writes its local-model settings:

```shell
start-pi --gpu-box
```
