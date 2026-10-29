#!/usr/bin/env bash
# Joins the tailnet with the auth key stored in Parameter Store. Runs on first
# boot from setup-workbench.sh, and later from `workbench ec2 join-tailnet`.
set -euo pipefail

if tailscale status >/dev/null 2>&1; then
  echo "Already on the tailnet."
  exit 0
fi

[ -f /etc/agent-workbench/workbench.env ] && . /etc/agent-workbench/workbench.env
tailscale_auth_key="$(aws ssm get-parameter \
  --region "${AWS_REGION:-}" \
  --name /coding-agent-workbench/tailscale/auth-key \
  --with-decryption \
  --query Parameter.Value \
  --output text 2>/dev/null || true)"
if [ -z "$tailscale_auth_key" ]; then
  echo "ERROR: No auth key at /coding-agent-workbench/tailscale/auth-key." >&2
  exit 1
fi

if ! up_output="$(tailscale up --ssh --hostname agent-workbench --auth-key "$tailscale_auth_key" 2>&1)"; then
  echo "$up_output" >&2
  echo "ERROR: Tailscale did not accept the stored auth key. Store a fresh one and run: workbench ec2 join-tailnet" >&2
  exit 1
fi

if grep -qi 'locked out' <<<"$up_output"; then
  node_key="$(tailscale status --json | python3 -c 'import json, sys; print(json.load(sys.stdin)["Self"]["PublicKey"])')"
  echo "Locked out by tailnet lock. On your laptop, run:"
  echo "  tailscale lock sign $node_key"
  exit 0
fi
echo "Joined the tailnet."
