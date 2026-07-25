#!/usr/bin/env bash
set -euo pipefail

REGION="us-west-2"
METRIC_LOOKBACK_MINUTES=15
# A live session publishes ActiveSessionCount every minute and writes container
# logs, so anything older than this is left over from a session that already ended.
FRESH_SIGNAL_MAX_AGE_MINUTES=5

command -v aws >/dev/null 2>&1 || {
  echo "ERROR: AWS CLI is not installed or not available in PATH." >&2
  exit 1
}

command -v python3 >/dev/null 2>&1 || {
  echo "ERROR: python3 is required but was not found." >&2
  exit 1
}

minutes_since_iso_timestamp() {
  python3 - "$1" <<'PY'
from datetime import datetime, timezone
import sys

moment = datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00"))
print(f"{(datetime.now(timezone.utc) - moment).total_seconds() / 60:.1f}")
PY
}

minutes_since_epoch_millis() {
  python3 - "$1" <<'PY'
import sys
import time

print(f"{(time.time() * 1000 - float(sys.argv[1])) / 60000:.1f}")
PY
}

is_fresh() {
  awk -v age="$1" -v limit="$FRESH_SIGNAL_MAX_AGE_MINUTES" 'BEGIN { exit !(age <= limit) }'
}

is_positive() {
  awk -v value="$1" 'BEGIN { exit !(value > 0) }'
}

read_latest_metric_datapoint() {
  aws cloudwatch get-metric-statistics \
    --region "$REGION" \
    --namespace "AWS/Bedrock-AgentCore" \
    --metric-name "ActiveSessionCount" \
    --dimensions "Name=Service,Value=$1" \
    --start-time "$START_TIME" \
    --end-time "$END_TIME" \
    --period 60 \
    --statistics Maximum \
    --query 'sort_by(Datapoints,&Timestamp)[-1].[Timestamp,Maximum]' \
    --output text 2>/dev/null || true
}

read_newest_log_stream() {
  aws logs describe-log-streams \
    --region "$REGION" \
    --log-group-name "/aws/bedrock-agentcore/runtimes/$1-DEFAULT" \
    --order-by LastEventTime \
    --descending \
    --limit 1 \
    --query 'logStreams[0].[logStreamName,lastEventTimestamp]' \
    --output text 2>/dev/null | head -n 1 || true
}

list_runtime_arns() {
  aws bedrock-agentcore-control list-agent-runtimes \
    --region "$REGION" \
    --query 'agentRuntimes[].agentRuntimeArn' \
    --output text 2>/dev/null | tr '\t' '\n' || true
}

echo "AWS account:"
aws sts get-caller-identity \
  --region "$REGION" \
  --query '{Account:Account,Arn:Arn}' \
  --output table

echo "Region: $REGION"

read -r START_TIME END_TIME < <(
  python3 - "$METRIC_LOOKBACK_MINUTES" <<'PY'
from datetime import datetime, timedelta, timezone
import sys

minutes = int(sys.argv[1])
now = datetime.now(timezone.utc)
fmt = "%Y-%m-%dT%H:%M:%SZ"
print((now - timedelta(minutes=minutes)).strftime(fmt), now.strftime(fmt))
PY
)

echo
echo "Session metrics (a datapoint older than ${FRESH_SIGNAL_MAX_AGE_MINUTES} minutes is stale, not active)"

fresh_metric_services=0

for service in \
  "AgentCore.Runtime" \
  "AgentCore.CodeInterpreter" \
  "AgentCore.Browser"
do
  read -r datapoint_timestamp datapoint_value <<<"$(read_latest_metric_datapoint "$service")"

  if [[ -z "${datapoint_timestamp:-}" || "$datapoint_timestamp" == "None" ]]; then
    printf "  %-28s no metric data in the last %s minutes\n" \
      "$service" "$METRIC_LOOKBACK_MINUTES"
    continue
  fi

  datapoint_age="$(minutes_since_iso_timestamp "$datapoint_timestamp")"

  if is_positive "$datapoint_value" && is_fresh "$datapoint_age"; then
    printf "  %-28s %s session(s), reported %s minutes ago (ACTIVE)\n" \
      "$service" "$datapoint_value" "$datapoint_age"
    fresh_metric_services=$((fresh_metric_services + 1))
  elif is_positive "$datapoint_value"; then
    printf "  %-28s %s session(s), but reported %s minutes ago (STALE, session already ended)\n" \
      "$service" "$datapoint_value" "$datapoint_age"
  else
    printf "  %-28s %s session(s), reported %s minutes ago\n" \
      "$service" "$datapoint_value" "$datapoint_age"
  fi
done

echo
echo "Runtime log activity (the newest log stream names the most recent session)"

fresh_log_runtimes=0
stop_commands=()

while read -r runtime_arn; do
  [ -n "$runtime_arn" ] || continue

  runtime_id="${runtime_arn##*/}"
  read -r stream_name stream_last_event <<<"$(read_newest_log_stream "$runtime_id")"

  if [[ -z "${stream_name:-}" || "$stream_name" == "None" ]]; then
    printf "  %-28s no log streams\n" "$runtime_id"
    continue
  fi

  session_id="${stream_name##*]}"

  if [[ -z "${stream_last_event:-}" || "$stream_last_event" == "None" ]]; then
    printf "  %-28s %s (no events)\n" "$runtime_id" "$session_id"
    continue
  fi

  stream_age="$(minutes_since_epoch_millis "$stream_last_event")"

  if is_fresh "$stream_age"; then
    printf "  %-28s %s last logged %s minutes ago (ACTIVE)\n" \
      "$runtime_id" "$session_id" "$stream_age"
    fresh_log_runtimes=$((fresh_log_runtimes + 1))
    stop_commands+=(
      "aws bedrock-agentcore stop-runtime-session --region $REGION --agent-runtime-arn $runtime_arn --runtime-session-id $session_id"
    )
  else
    printf "  %-28s %s last logged %s minutes ago (idle or ended)\n" \
      "$runtime_id" "$session_id" "$stream_age"
  fi
done < <(list_runtime_arns)

echo
echo "Verdict"

if (( fresh_metric_services == 0 && fresh_log_runtimes == 0 )); then
  echo "  Nothing is running. No session metric and no log event in the last ${FRESH_SIGNAL_MAX_AGE_MINUTES} minutes."
  echo "  You are not being billed for a session."
elif (( fresh_metric_services > 0 && fresh_log_runtimes == 0 )); then
  echo "  A session is probably running but is quiet, so no recent logs identify it."
  echo "  An idle session still bills. Re-run in a few minutes to see whether the metric goes stale."
else
  echo "  A session is running. Stop it with:"
  for stop_command in "${stop_commands[@]}"; do
    echo
    echo "    $stop_command"
  done
fi

echo
echo "Deployed AgentCore runtimes (READY means deployable, not running)"
aws bedrock-agentcore-control list-agent-runtimes \
  --region "$REGION" \
  --query 'agentRuntimes[].{
    Name:agentRuntimeName,
    Status:status,
    Version:agentRuntimeVersion,
    ARN:agentRuntimeArn
  }' \
  --output table \
  || echo "Could not list runtimes. Your AWS CLI may need updating, or your identity may lack AgentCore permissions." >&2
