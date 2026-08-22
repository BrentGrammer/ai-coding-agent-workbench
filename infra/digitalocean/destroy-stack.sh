#!/usr/bin/env bash

# Destroys any GPU droplet.
# Creates a temporary Spaces key.
# Empties the Spaces cache bucket.
# Destroys the Terraform stack.
# Deletes the temporary Spaces key.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TF_DIR="$SCRIPT_DIR/terraform"
DROPLET_TAG="agent-workbench-gpu-llm"
SPACES_KEYS_URL="https://api.digitalocean.com/v2/spaces/keys"
AUTO_YES=0
TEMP_ACCESS_KEY=""

usage() {
  cat <<'EOF'
Usage: destroy-stack.sh [--yes]

Destroys any GPU droplet, the Spaces cache bucket, and the rest of the
Terraform stack (Spaces key, firewall, tag, SSH key).

Uses the token from `doctl auth init`. Creates a temporary Spaces key
and deletes it when finished.
EOF
  exit 1
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: $1 is not installed." >&2
    exit 1
  fi
}

# doctl prompts when it thinks a terminal is attached. Command substitution
# hides that prompt, so turn interactive mode off for every doctl call.
doctl_ni() {
  doctl --interactive=false "$@"
}

parse_spaces_key() {
  python3 -c '
import json, sys
data = json.load(sys.stdin)
if isinstance(data, list):
    data = data[0]
if isinstance(data, dict) and isinstance(data.get("key"), dict):
    data = data["key"]
access = data.get("access_key") or data.get("AccessKey")
secret = data.get("secret_key") or data.get("SecretKey")
if not access or not secret:
    sys.exit("could not parse Spaces key JSON")
print(access)
print(secret)
'
}

spaces_key_payload() {
  KEY_NAME="$1" python3 -c '
import json, os
print(json.dumps({
    "name": os.environ["KEY_NAME"],
    "grants": [{"bucket": "", "permission": "fullaccess"}],
}))
'
}

create_temp_spaces_key() {
  local name="$1"
  local body http_code payload key_pair
  body="$(mktemp)"
  payload="$(spaces_key_payload "$name")"
  http_code="$(curl -sS -o "$body" -w "%{http_code}" \
    -X POST \
    -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$SPACES_KEYS_URL")"
  if [ "$http_code" != "201" ] && [ "$http_code" != "200" ]; then
    echo "ERROR: Could not create a Spaces key (HTTP ${http_code})." >&2
    cat "$body" >&2
    echo >&2
    rm -f "$body"
    return 1
  fi
  if ! key_pair="$(parse_spaces_key < "$body")"; then
    echo "ERROR: Could not parse the Spaces key response." >&2
    cat "$body" >&2
    echo >&2
    rm -f "$body"
    return 1
  fi
  rm -f "$body"
  printf '%s\n' "$key_pair"
}

delete_temp_key() {
  if [ -n "$TEMP_ACCESS_KEY" ]; then
    curl -sS -o /dev/null \
      -X DELETE \
      -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" \
      "${SPACES_KEYS_URL}/${TEMP_ACCESS_KEY}" || true
    TEMP_ACCESS_KEY=""
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y) AUTO_YES=1 ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
  shift
done

need_cmd doctl
need_cmd terraform
need_cmd aws
need_cmd python3
need_cmd curl

if [ ! -f "$TF_DIR/terraform.tfstate" ]; then
  echo "ERROR: No Terraform state at $TF_DIR/terraform.tfstate." >&2
  echo "Nothing to destroy with Terraform. Check the DigitalOcean control panel." >&2
  exit 1
fi

DIGITALOCEAN_TOKEN="${DIGITALOCEAN_TOKEN:-$(doctl_ni auth token)}"
if [ -z "$DIGITALOCEAN_TOKEN" ]; then
  echo "ERROR: No DigitalOcean token. Run: doctl auth init" >&2
  exit 1
fi
export DIGITALOCEAN_TOKEN

BUCKET="$(terraform -chdir="$TF_DIR" output -raw cache_bucket 2>/dev/null || true)"
REGION="$(terraform -chdir="$TF_DIR" output -raw spaces_region 2>/dev/null || true)"
BUCKET="${BUCKET:-agent-workbench-llm-cache}"
REGION="${REGION:-nyc3}"

if [ "$AUTO_YES" -ne 1 ]; then
  if [ ! -t 0 ]; then
    echo "ERROR: Pass --yes to destroy without a prompt." >&2
    exit 1
  fi
  echo "This deletes:"
  echo "  - any GPU droplet tagged $DROPLET_TAG"
  echo "  - Spaces bucket $BUCKET (stops the \$5/month Spaces charge)"
  echo "  - the Spaces key, firewall, tag, and SSH key in Terraform"
  printf "Type yes to continue: "
  read -r answer
  if [ "$answer" != "yes" ]; then
    echo "Aborted."
    exit 1
  fi
fi

trap delete_temp_key EXIT

echo "== Destroying GPU droplets"
ids="$(doctl_ni compute droplet list --tag-name "$DROPLET_TAG" --format ID --no-header)"
if [ -z "$ids" ]; then
  echo "No GPU droplet is running."
else
  for id in $ids; do
    doctl_ni compute droplet delete --force "$id"
    echo "Destroyed droplet $id."
  done
fi

echo "== Creating a temporary Spaces key"
key_pair="$(create_temp_spaces_key "agent-workbench-teardown-$$")"
SPACES_ACCESS_KEY_ID="${key_pair%%$'\n'*}"
SPACES_SECRET_ACCESS_KEY="${key_pair#*$'\n'}"
if [ -z "$SPACES_ACCESS_KEY_ID" ] || [ -z "$SPACES_SECRET_ACCESS_KEY" ]; then
  echo "ERROR: Spaces key response was empty." >&2
  exit 1
fi
TEMP_ACCESS_KEY="$SPACES_ACCESS_KEY_ID"
export SPACES_ACCESS_KEY_ID SPACES_SECRET_ACCESS_KEY
export AWS_ACCESS_KEY_ID="$SPACES_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$SPACES_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION=us-east-1
echo "Created a temporary Spaces key."

echo "== Emptying $BUCKET"
aws s3 rm "s3://${BUCKET}" --recursive \
  --endpoint-url "https://${REGION}.digitaloceanspaces.com" || true

echo "== Destroying Terraform stack"
terraform -chdir="$TF_DIR" destroy -auto-approve

delete_temp_key
trap - EXIT

echo "DigitalOcean stack is gone. Spaces will not bill for this bucket."
