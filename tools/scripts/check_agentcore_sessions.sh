#!/usr/bin/env bash
set -euo pipefail

REGION="us-west-2"
METRIC_LOOKBACK_MINUTES=15
# A live session publishes ActiveSessionCount every minute and writes container
# logs, so anything older than this is left over from a session that already ended.
FRESH_SIGNAL_MAX_AGE_MINUTES=5
# CloudWatch lags by a minute or two, so a session stopped moments ago still has
# signals this recent. Only a newer signal than this proves something is running.
LIVE_SIGNAL_MAX_AGE_MINUTES=2
# Comparing this run against the previous one turns the ambiguous middle window
# into a definite answer, once enough time has passed for a new datapoint.
PREVIOUS_RUN_FILE="$HOME/.local/state/agent-workbench/agentcore-runtime-metric"
PREVIOUS_RUN_MIN_GAP_SECONDS=150

show_details=""

if [ "$#" -gt 0 ]; then
  if [ "$1" = "--details" ] && [ "$#" -eq 1 ]; then
    show_details="yes"
  else
    echo "Usage: $0 [--details]" >&2
    exit 1
  fi
fi

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

is_live() {
  awk -v age="$1" -v limit="$LIVE_SIGNAL_MAX_AGE_MINUTES" 'BEGIN { exit !(age <= limit) }'
}

is_positive() {
  awk -v value="$1" 'BEGIN { exit !(value > 0) }'
}

freshest_signal_age=""

remember_freshest_signal() {
  if [ -z "$freshest_signal_age" ] ||
    awk -v candidate="$1" -v best="$freshest_signal_age" 'BEGIN { exit !(candidate < best) }'; then
    freshest_signal_age="$1"
  fi
}

detail_lines=()

add_detail() {
  detail_lines+=("$1")
}

read_previous_metric_timestamp() {
  [ -f "$PREVIOUS_RUN_FILE" ] || return 1
  read -r previous_timestamp previous_observed_at <"$PREVIOUS_RUN_FILE" || return 1
  [ -n "${previous_timestamp:-}" ] && [ -n "${previous_observed_at:-}" ]
}

write_previous_metric_timestamp() {
  mkdir -p "$(dirname "$PREVIOUS_RUN_FILE")"
  printf '%s %s\n' "$1" "$(date +%s)" >"$PREVIOUS_RUN_FILE"
}

metric_stopped_advancing() {
  read_previous_metric_timestamp || return 1
  [ "$previous_timestamp" = "$1" ] || return 1
  (($(date +%s) - previous_observed_at >= PREVIOUS_RUN_MIN_GAP_SECONDS))
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

runtime_metric_timestamp=""

for service in \
  "AgentCore.Runtime" \
  "AgentCore.CodeInterpreter" \
  "AgentCore.Browser"
do
  read -r datapoint_timestamp datapoint_value <<<"$(read_latest_metric_datapoint "$service")"

  if [ "$service" = "AgentCore.Runtime" ]; then
    runtime_metric_timestamp="${datapoint_timestamp:-}"
  fi

  if [[ -z "${datapoint_timestamp:-}" || "$datapoint_timestamp" == "None" ]]; then
    add_detail "$(printf '  %-26s no data in the last %s min' "$service" "$METRIC_LOOKBACK_MINUTES")"
    continue
  fi

  datapoint_age="$(minutes_since_iso_timestamp "$datapoint_timestamp")"

  if is_positive "$datapoint_value" && is_fresh "$datapoint_age"; then
    remember_freshest_signal "$datapoint_age"
  fi

  add_detail "$(printf '  %-26s %s session(s), %s min old' \
    "$service" "$datapoint_value" "$datapoint_age")"
done

while read -r runtime_arn; do
  [ -n "$runtime_arn" ] || continue

  runtime_id="${runtime_arn##*/}"
  read -r stream_name stream_last_event <<<"$(read_newest_log_stream "$runtime_id")"

  if [[ -z "${stream_name:-}" || "$stream_name" == "None" ]]; then
    add_detail "$(printf '  %-26s no log streams' "$runtime_id")"
    continue
  fi

  if [[ -z "${stream_last_event:-}" || "$stream_last_event" == "None" ]]; then
    add_detail "$(printf '  %-26s newest log stream has no events' "$runtime_id")"
    continue
  fi

  stream_age="$(minutes_since_epoch_millis "$stream_last_event")"

  if is_fresh "$stream_age"; then
    remember_freshest_signal "$stream_age"
  fi

  add_detail "$(printf '  %-26s last log %s min old' "$runtime_id" "$stream_age")"
done < <(list_runtime_arns)

print_stop_instructions() {
  echo "  Stop:  ./bin/workbench aws stop NAME"
  echo "  Names: ./bin/workbench aws status"
}

if [ -n "$show_details" ] && ((${#detail_lines[@]} > 0)); then
  echo "Signals (region $REGION)"
  printf '%s\n' "${detail_lines[@]}"
  echo
fi

if [ -z "$freshest_signal_age" ]; then
  echo "NO SESSION RUNNING. Nothing has billed in the last ${FRESH_SIGNAL_MAX_AGE_MINUTES} minutes."
elif metric_stopped_advancing "$runtime_metric_timestamp"; then
  echo "NO SESSION RUNNING. The metric has not advanced since the last run, so what is"
  echo "left is the tail of a session that already ended."
else
  if is_live "$freshest_signal_age"; then
    echo "SESSION RUNNING. Newest signal ${freshest_signal_age} min old."
  else
    echo "MAYBE RUNNING. Newest signal ${freshest_signal_age} min old, which CloudWatch lag"
    echo "cannot separate from a session that just ended. Run again in 3 minutes to be sure."
  fi

  print_stop_instructions
fi

if [ -n "$runtime_metric_timestamp" ] && [ "$runtime_metric_timestamp" != "None" ]; then
  write_previous_metric_timestamp "$runtime_metric_timestamp"
fi
