#!/usr/bin/env bash
# bootstrap-cloudflared.sh
#
# Runs at first boot via cloud-init runcmd.
# Fetches the Cloudflare tunnel token from Azure Key Vault using the VM's
# Managed Identity (IMDS endpoint) and writes it to /etc/cloudflared/env.
#
# Flow:
#   1. Source /etc/environment (contains KEY_VAULT_URL injected by Terraform)
#   2. Retry IMDS until Managed Identity is available (up to 5 minutes)
#   3. Exchange IMDS response for a Key Vault access token
#   4. Fetch CLOUDFLARE-TUNNEL-TOKEN secret value
#   5. Write TUNNEL_TOKEN=<value> to /etc/cloudflared/env (mode 600)
#   6. Start cloudflared service

set -euo pipefail

LOGFILE="/var/log/bootstrap-cloudflared.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "[$(date -Iseconds)] bootstrap-cloudflared.sh starting..."

# ── 1. Load environment ────────────────────────────────────────────────────────
# shellcheck disable=SC1091
. /etc/environment

if [ -z "${KEY_VAULT_URL:-}" ]; then
  echo "ERROR: KEY_VAULT_URL not set in /etc/environment. Cannot fetch tunnel token."
  exit 1
fi

# Ensure trailing slash for URL construction
KEY_VAULT_URL="${KEY_VAULT_URL%/}/"

IMDS_TOKEN_URL="http://169.254.169.254/metadata/identity/oauth2/token"
IMDS_RESOURCE="https://vault.azure.net"

# ── 2. Wait for Managed Identity (IMDS) to be available ───────────────────────
echo "Waiting for Managed Identity via IMDS (max 5 minutes)..."

MAX_ATTEMPTS=30
for i in $(seq 1 $MAX_ATTEMPTS); do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Metadata: true" \
    --connect-timeout 5 \
    --max-time 10 \
    "${IMDS_TOKEN_URL}?api-version=2018-02-01&resource=${IMDS_RESOURCE}" \
    2>/dev/null || echo "000")

  if [ "$HTTP_CODE" = "200" ]; then
    echo "Managed Identity available after $i attempt(s)."
    break
  fi

  if [ "$i" = "$MAX_ATTEMPTS" ]; then
    echo "ERROR: Managed Identity not available after $MAX_ATTEMPTS attempts (5 min). HTTP: $HTTP_CODE"
    exit 1
  fi

  echo "Attempt $i/$MAX_ATTEMPTS: IMDS returned HTTP $HTTP_CODE. Retrying in 10s..."
  sleep 10
done

# ── 3. Get Key Vault access token from IMDS ────────────────────────────────────
echo "Fetching Key Vault access token from IMDS..."

TOKEN_RESPONSE=$(curl -sf \
  -H "Metadata: true" \
  --connect-timeout 10 \
  --max-time 30 \
  "${IMDS_TOKEN_URL}?api-version=2018-02-01&resource=${IMDS_RESOURCE}")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
  echo "ERROR: Failed to extract access_token from IMDS response:"
  echo "$TOKEN_RESPONSE"
  exit 1
fi

echo "Access token obtained (length: ${#ACCESS_TOKEN} chars)."

# ── 4. Fetch tunnel token from Key Vault ──────────────────────────────────────
KV_SECRET_URL="${KEY_VAULT_URL}secrets/CLOUDFLARE-TUNNEL-TOKEN?api-version=7.0"
echo "Fetching CLOUDFLARE-TUNNEL-TOKEN from: ${KEY_VAULT_URL}secrets/CLOUDFLARE-TUNNEL-TOKEN"

SECRET_RESPONSE=$(curl -sf \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  --connect-timeout 10 \
  --max-time 30 \
  "$KV_SECRET_URL")

TUNNEL_TOKEN=$(echo "$SECRET_RESPONSE" | jq -r '.value')

if [ -z "$TUNNEL_TOKEN" ] || [ "$TUNNEL_TOKEN" = "null" ]; then
  echo "ERROR: Failed to extract tunnel token from Key Vault response:"
  # Don't log the full response — it may contain the token
  echo "Secret name exists: $(echo "$SECRET_RESPONSE" | jq -r '.id // "NOT FOUND"')"
  exit 1
fi

echo "Tunnel token fetched successfully."

# ── 5. Write token to cloudflared env file ────────────────────────────────────
mkdir -p /etc/cloudflared
printf 'TUNNEL_TOKEN=%s\n' "$TUNNEL_TOKEN" > /etc/cloudflared/env
chmod 600 /etc/cloudflared/env

# Set ownership if cloudflared user exists (created by apt package install)
if id cloudflared &>/dev/null; then
  chown cloudflared:cloudflared /etc/cloudflared/env
fi

echo "[$(date -Iseconds)] Bootstrap complete. /etc/cloudflared/env written."
