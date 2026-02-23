#!/usr/bin/env bash
# destroy.sh — Tear down all Zero Trust Gateway infrastructure
#
# WARNING: This destroys ALL resources including the Azure VM, Key Vault (and all
# secrets), VNet, Log Analytics Workspace, Cloudflare tunnel, and Snowflake
# database/schema/table. This action cannot be undone.

set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$PROJECT_ROOT/terraform"

echo -e "${RED}╔══════════════════════════════════════════════╗${NC}"
echo -e "${RED}║   Zero Trust Gateway — DESTROY SCRIPT        ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════╝${NC}"
echo

echo -e "${YELLOW}The following resources will be permanently destroyed:${NC}"
echo "  • Azure VM (vm-zero-trust-gateway) + OS disk"
echo "  • Azure Key Vault + all secrets (SNOWFLAKE-*, SSH-PRIVATE-KEY, CLOUDFLARE-*)"
echo "  • Azure Virtual Network + all subnets + NSG"
echo "  • Azure Private Endpoint (Key Vault) + Private DNS Zone"
echo "  • Azure User-Assigned Managed Identity"
echo "  • Azure Log Analytics Workspace + collected logs"
echo "  • Cloudflare Tunnel + Access Application + Access Policy"
echo "  • Snowflake: DEMO_DB, DEMO_SCHEMA, INFRASTRUCTURE_METRICS"
echo "  • Snowflake: GATEWAY_SVC user, GATEWAY_ROLE, CLOUDFLARE_EGRESS_POLICY"
echo

if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a; source "$PROJECT_ROOT/.env"; set +a
fi

echo -e "${YELLOW}This action cannot be undone. Type 'destroy' to confirm:${NC}"
read -r CONFIRM

if [ "$CONFIRM" != "destroy" ]; then
  echo "Destruction cancelled. (You typed: '$CONFIRM', expected: 'destroy')"
  exit 0
fi

echo
echo "Running terraform destroy..."
echo

cd "$TF_DIR"
terraform destroy -auto-approve

echo
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  All infrastructure destroyed successfully.  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo
echo "Terraform state files remain in terraform/ for reference."
echo "Key Vault secrets are soft-deleted (7-day retention) but the vault is purged"
echo "because purge_soft_delete_on_destroy=true."
