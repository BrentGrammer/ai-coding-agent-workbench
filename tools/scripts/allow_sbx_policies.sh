#!/usr/bin/env bash

# Policies to allow in docker sandbox when in locked down mode

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

if [ -z "${AWS_REGION:-}" ] && [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

export SBX_NO_TELEMETRY=1

# Allow docker for pulling templates with sbx
sbx policy allow network -g download.docker.com:443

# Allow ubuntu security updates for patches and package upgrades
sbx policy allow network -g debian.org:443
sbx policy allow network -g ports.ubuntu.com:80
sbx policy allow network -g ports.ubuntu.com:443
sbx policy allow network -g deb.debian.org:443
sbx policy allow network -g archive.ubuntu.com:443
sbx policy allow network -g security.ubuntu.com:443

# Allow dependency registries
sbx policy allow network -g registry.npmjs.org:443
sbx policy allow network -g nodejs.org:443
sbx policy allow network -g pypi.org:443
sbx policy allow network -g files.pythonhosted.org:443

# Providers

# OpenRouter
sbx policy allow network -g openrouter.ai:443

if [ -n "${AWS_REGION:-}" ]; then
  sbx policy allow network -g "bedrock-runtime.${AWS_REGION}.amazonaws.com:443"
fi

# Allow Github for tools:
sbx policy allow network -g github.com:443
sbx policy allow network -g api.github.com:443

### NON GLOBAL ALLOWS

# # Allow Google gemini
# sbx policy allow network -g generativelanguage.googleapis.com:443
# sbx policy allow network -g gemini-api-docs-mcp.dev:443
# sbx policy allow network -g ai.google.dev:443
# sbx policy allow network -g oauth2.googleapis.com:443
# sbx policy allow network -g accounts.google.com:443
# sbx policy allow network -g cloudcode-pa.googleapis.com:443
# sbx policy allow network -g play.googleapis.com:443
# sbx policy allow network -g www.googleapis.com:443

# # Allow OpenAI for codex Pro subscription
# sbx policy allow network -g chatgpt.com:443
# sbx policy allow network -g api.openai.com:443

# # For Exa mcp (per-agent instead: allow_exa_mcp_network in sandbox_bootstrap.sh)
# sbx policy allow network -g mcp.exa.ai:443

# # Needed for Serena mcp
# sbx policy allow network -g github.com:443
# sbx policy allow network -g api.github.com:443
# sbx policy allow network -g oraios-software.de:443
