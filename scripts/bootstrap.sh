#!/usr/bin/env bash
# bootstrap.sh — Pre-flight checks before deploying the Zero Trust Gateway
#
# Verifies: required CLI tools, .env variables, Azure login, Terraform init.
# Run this once before your first `make apply`.

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✓${NC} $1"; }
warn() { echo -e "${YELLOW}  ⚠${NC} $1"; }
fail() { echo -e "${RED}  ✗${NC} $1"; exit 1; }
info() { echo -e "${CYAN}  →${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "╔══════════════════════════════════════════════╗"
echo "║   Zero Trust Gateway — Bootstrap Check       ║"
echo "╚══════════════════════════════════════════════╝"
echo

# ── 1. Required CLI tools ─────────────────────────────────────────────────────
echo "── Checking required tools ───────────────────────"

if command -v terraform &>/dev/null; then
  TF_VER=$(terraform version -json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["terraform_version"])' 2>/dev/null || terraform version | head -1 | awk '{print $2}')
  ok "terraform $TF_VER"
else
  fail "terraform not found. Install: https://developer.hashicorp.com/terraform/downloads"
fi

if command -v az &>/dev/null; then
  AZ_VER=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
  ok "azure-cli $AZ_VER"
else
  fail "az CLI not found. Install: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
fi

if command -v python3 &>/dev/null; then
  ok "python3 $(python3 --version 2>&1 | awk '{print $2}')"
else
  fail "python3 not found"
fi

if command -v jq &>/dev/null; then
  ok "jq $(jq --version)"
else
  warn "jq not found (useful for debugging but not required for Terraform)"
fi

command -v ssh &>/dev/null && ok "ssh available" || warn "ssh not found (needed for make ssh)"
echo

# ── 2. Load .env and check required variables ─────────────────────────────────
echo "── Checking environment variables ────────────────"

ENV_FILE="$PROJECT_ROOT/.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  ok ".env loaded from $ENV_FILE"
else
  fail ".env not found. Run: cp $PROJECT_ROOT/.env.example $PROJECT_ROOT/.env && nano $PROJECT_ROOT/.env"
fi

REQUIRED_VARS=(
  "TF_VAR_cloudflare_api_token"
  "TF_VAR_cloudflare_account_id"
  "TF_VAR_allowed_email"
  "TF_VAR_key_vault_name"
  "TF_VAR_snowflake_account"
  "TF_VAR_snowflake_admin_user"
  "TF_VAR_snowflake_admin_password"
  "TF_VAR_snowflake_svc_password"
)

# Optional — only needed when you have a custom domain in Cloudflare
OPTIONAL_VARS=(
  "TF_VAR_cloudflare_zone_id"
  "TF_VAR_tunnel_hostname"
)

ALL_SET=true
for var in "${REQUIRED_VARS[@]}"; do
  if [ -n "${!var:-}" ]; then
    # Mask sensitive values in output
    case "$var" in
      *password*|*token*|*secret*)
        ok "$var = <set>" ;;
      *)
        ok "$var = ${!var}" ;;
    esac
  else
    warn "$var is NOT SET in .env"
    ALL_SET=false
  fi
done

[ "$ALL_SET" = true ] || fail "One or more required variables are missing from .env"

for var in "${OPTIONAL_VARS[@]}"; do
  if [ -n "${!var:-}" ]; then
    ok "$var = ${!var} (custom domain mode)"
  else
    warn "$var not set — tunnel will use <tunnel-id>.cfargotunnel.com (no custom domain)"
  fi
done
echo

# ── 3. Azure authentication ────────────────────────────────────────────────────
echo "── Checking Azure authentication ──────────────────"

ACCOUNT_JSON=$(az account show -o json 2>/dev/null || echo "{}")
if [ "$ACCOUNT_JSON" = "{}" ]; then
  fail "Not logged into Azure. Run: az login"
fi

ACCOUNT_NAME=$(echo "$ACCOUNT_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("name","?"))')
USER_NAME=$(echo "$ACCOUNT_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("user",{}).get("name","?"))')
SUB_ID=$(echo "$ACCOUNT_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("id","?"))')
ok "Logged in as: $USER_NAME"
ok "Subscription: $ACCOUNT_NAME ($SUB_ID)"
echo

# ── 4. Key Vault name uniqueness reminder ─────────────────────────────────────
echo "── Checking Key Vault name ────────────────────────"
KV_NAME="${TF_VAR_key_vault_name:-}"
if [[ "$KV_NAME" == *"UNIQUE"* ]] || [[ "$KV_NAME" == *"kv-ztgw-demo"* && ${#KV_NAME} -le 20 ]]; then
  warn "Key Vault name '$KV_NAME' looks like it still has a placeholder. Make it globally unique."
else
  ok "Key Vault name: $KV_NAME"
fi
echo

# ── 5. Terraform init ──────────────────────────────────────────────────────────
echo "── Initializing Terraform ─────────────────────────"
info "Running terraform init in $PROJECT_ROOT/terraform/..."
cd "$PROJECT_ROOT/terraform"
terraform init -upgrade -input=false
ok "Terraform initialized"
cd "$PROJECT_ROOT"
echo

# ── Summary ───────────────────────────────────────────────────────────────────
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Bootstrap complete!                                         ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Estimated deployment time:                                  ║"
echo "║    terraform apply:          ~3 min                          ║"
echo "║    VM cloud-init (packages): ~3-5 min after apply            ║"
echo "║    Total to working tunnel:  ~8-10 min                       ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Next steps:                                                 ║"
echo "║    make plan    # Review what will be created                ║"
echo "║    make apply   # Provision everything                       ║"
echo "║    make logs    # Check VM cloud-init progress               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
