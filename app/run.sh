#!/usr/bin/env bash
# run.sh — Local development runner
# Activates the venv, sources .env, and starts uvicorn with hot-reload.
#
# Usage:
#   cd app/
#   bash run.sh
#
# Prerequisites:
#   1. Create venv:  python3.11 -m venv .venv && .venv/bin/pip install -e ".[dev]"
#   2. Copy ../.env.example to ../.env and fill in values
#   3. `az login` so DefaultAzureCredential can authenticate to Key Vault
#      NOTE: Key Vault has public_network_access_enabled=false, so local access
#            requires VPN or temporarily enabling public access for dev.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
VENV="$SCRIPT_DIR/.venv"

if [ ! -d "$VENV" ]; then
  echo "No venv found at $VENV"
  echo "Run: python3.11 -m venv $VENV && $VENV/bin/pip install -e '.[dev]'"
  exit 1
fi

if [ -f "$ENV_FILE" ]; then
  echo "Sourcing $ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
else
  echo "WARNING: $ENV_FILE not found. KEY_VAULT_URL must be set manually."
fi

# Convert TF_VAR_* to app env vars expected by the FastAPI app
export KEY_VAULT_URL="${TF_VAR_key_vault_url:-${KEY_VAULT_URL:-}}"
export AZURE_CLIENT_ID="${TF_VAR_azure_client_id:-${AZURE_CLIENT_ID:-}}"

echo "Starting FastAPI gateway (reload mode)..."
echo "  Key Vault: ${KEY_VAULT_URL:-NOT SET}"
echo

# shellcheck disable=SC1090
source "$VENV/bin/activate"
cd "$SCRIPT_DIR"
exec uvicorn main:app --host 127.0.0.1 --port 8000 --reload
