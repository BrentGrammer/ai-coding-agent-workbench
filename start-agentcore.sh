#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
AGENT="${1:-}"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: Create $ENV_FILE before running this script." >&2
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

GITHUB_REPOSITORY_URL="${GITHUB_REPOSITORY_URL:-}"
AWS_REGION="${AWS_REGION:-}"
GITHUB_APP_ID_PARAMETER_NAME="${GITHUB_APP_ID_PARAMETER_NAME:-}"
GITHUB_APP_PRIVATE_KEY_PARAMETER_NAME="${GITHUB_APP_PRIVATE_KEY_PARAMETER_NAME:-}"

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 codex|claude|opencode" >&2
  exit 1
fi

case "$AGENT" in
  codex|claude|opencode)
    ;;
  *)
    echo "ERROR: Unsupported agent: $AGENT" >&2
    exit 1
    ;;
esac

if [ -z "$GITHUB_REPOSITORY_URL" ]; then
  echo "ERROR: Set GITHUB_REPOSITORY_URL in $ENV_FILE." >&2
  exit 1
fi

for REQUIRED_VARIABLE in \
  AWS_REGION \
  GITHUB_APP_ID_PARAMETER_NAME \
  GITHUB_APP_PRIVATE_KEY_PARAMETER_NAME
do
  if [ -z "${!REQUIRED_VARIABLE}" ]; then
    echo "ERROR: Set $REQUIRED_VARIABLE in $ENV_FILE." >&2
    exit 1
  fi
done

exec "$SCRIPT_DIR/bin/workbench" aws "$GITHUB_REPOSITORY_URL" --agent "$AGENT"
