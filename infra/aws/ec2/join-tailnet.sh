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

if ! tailscale up --ssh --hostname agent-workbench --auth-key "$tailscale_auth_key"; then
  echo "ERROR: Tailscale did not accept the stored auth key. Store a fresh one and run: workbench ec2 join-tailnet" >&2
  exit 1
fi
echo "Joined the tailnet."
