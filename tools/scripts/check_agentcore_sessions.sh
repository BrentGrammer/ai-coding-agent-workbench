#!/usr/bin/env bash
set -euo pipefail

REGION="us-west-2"
LOOKBACK_MINUTES=15

command -v aws >/dev/null 2>&1 || {
  echo "ERROR: AWS CLI is not installed or not available in PATH." >&2
  exit 1
}

command -v python3 >/dev/null 2>&1 || {
  echo "ERROR: python3 is required but was not found." >&2
  exit 1
}

echo "AWS account:"
aws sts get-caller-identity \
  --region "$REGION" \
  --query '{Account:Account,Arn:Arn}' \
  --output table

echo "Region: $REGION"

read -r START_TIME END_TIME < <(
  python3 - "$LOOKBACK_MINUTES" <<'PY'
from datetime import datetime, timedelta, timezone
import sys

minutes = int(sys.argv[1])
now = datetime.now(timezone.utc)
fmt = "%Y-%m-%dT%H:%M:%SZ"
print((now - timedelta(minutes=minutes)).strftime(fmt), now.strftime(fmt))
PY
)

echo "Active AgentCore sessions"
echo "Metric window: last ${LOOKBACK_MINUTES} minutes"

active_total=0

for SERVICE in \
  "AgentCore.Runtime" \
  "AgentCore.CodeInterpreter" \
  "AgentCore.Browser"
do
  VALUE="$(
    aws cloudwatch get-metric-statistics \
      --region "$REGION" \
      --namespace "AWS/Bedrock-AgentCore" \
      --metric-name "ActiveSessionCount" \
      --dimensions "Name=Service,Value=${SERVICE}" \
      --start-time "$START_TIME" \
      --end-time "$END_TIME" \
      --period 60 \
      --statistics Maximum \
      --query 'sort_by(Datapoints,&Timestamp)[-1].Maximum' \
      --output text 2>/dev/null || true
  )"

  if [[ -z "$VALUE" || "$VALUE" == "None" ]]; then
    DISPLAY="no metric data"
  else
    DISPLAY="$VALUE"
    # Values are normally returned as numbers such as 0.0 or 1.0.
    if awk -v value="$VALUE" 'BEGIN { exit !(value > 0) }'; then
      active_total=$((active_total + 1))
    fi
  fi

  printf "  %-30s %s\n" "$SERVICE" "$DISPLAY"
done


if (( active_total == 0 )); then
  echo "No AgentCore service reported an active session in the latest metric data."
else
  echo "At least one AgentCore service reported active sessions."
fi

echo "Deployed AgentCore runtimes"
if aws bedrock-agentcore-control list-agent-runtimes \
    --region "$REGION" \
    --query 'agentRuntimes[].{
      Name:agentRuntimeName,
      Status:status,
      Version:agentRuntimeVersion,
      ARN:agentRuntimeArn
    }' \
    --output table; then
  :
else
  echo "Could not list runtimes. Your AWS CLI may need updating, or your identity may lack AgentCore permissions." >&2
fi

echo "Note: a runtime with READY status is deployable, not necessarily actively running. Look at the number for AgentCore.Runtime to see running sessions."