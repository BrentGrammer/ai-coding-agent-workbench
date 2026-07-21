#!/usr/bin/env bash
set -euo pipefail

export SBX_NO_TELEMETRY=1

if [ "$#" -ne 1 ]; then
    echo "❌ Error: Please provide a sandbox name."
    echo "Usage: $0 <sandbox-name>"
    echo ""
    echo "Active sandboxes:"
    sbx ls 2>/dev/null || echo "  (Could not list sandboxes. Make sure sbx is installed.)"
    exit 1
fi

SANDBOX_NAME="$1"

echo "🚀 Connecting to Bash terminal in sandbox: ${SANDBOX_NAME}..."
echo "Type 'exit' to leave the sandbox."
echo "--------------------------------------------------"

sbx exec -it "$SANDBOX_NAME" bash
