#!/usr/bin/env bash
# deploy.sh — Full deployment: terraform apply → wait for cloud-init → health check
#
# Usage: ./scripts/deploy.sh
# Prerequisite: ./scripts/bootstrap.sh has been run successfully.

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✓${NC} $1"; }
warn() { echo -e "${YELLOW}  ⚠${NC} $1"; }
fail() { echo -e "${RED}  ✗${NC} $1"; exit 1; }
info() { echo -e "${CYAN}  →${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$PROJECT_ROOT/terraform"
VM_NAME="vm-zero-trust-gateway"

# Load .env
if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a; source "$PROJECT_ROOT/.env"; set +a
else
  fail ".env not found. Run ./scripts/bootstrap.sh first."
fi

echo "╔══════════════════════════════════════════════╗"
echo "║   Zero Trust Gateway — Deployment Script     ║"
echo "╚══════════════════════════════════════════════╝"
echo

# ── Step 1: Terraform apply ────────────────────────────────────────────────────
echo "── Step 1/4: Terraform apply ─────────────────────"
info "This creates: Azure VM, Key Vault (PE), Cloudflare tunnel, Snowflake objects"
info "Expected duration: ~3 minutes"
echo

cd "$TF_DIR"
terraform apply -auto-approve
ok "Terraform apply complete"

# Extract outputs
VM_PRIVATE_IP=$(terraform output -raw vm_private_ip 2>/dev/null || echo "unknown")
TUNNEL_URL=$(terraform output -raw tunnel_url 2>/dev/null || echo "unknown")
RG_NAME=$(grep -E '^resource_group_name\s*=' "$TF_DIR/terraform.tfvars" 2>/dev/null \
  | awk -F'"' '{print $2}' || echo "rg-zero-trust-gateway")
cd "$PROJECT_ROOT"

echo
info "VM Private IP:  $VM_PRIVATE_IP  (no public IP)"
info "Tunnel URL:     $TUNNEL_URL"
echo

# ── Step 2: Wait for cloud-init to complete ────────────────────────────────────
echo "── Step 2/4: Waiting for cloud-init on VM ─────────"
info "cloud-init installs packages, Python venv, fetches tunnel token from Key Vault"
info "This typically takes 3-5 minutes after terraform apply."
info "Polling every 30s (max 15 minutes)..."
echo

READY=false
for i in $(seq 1 30); do
  printf "  Attempt %d/30... " "$i"

  # Run a command on the VM via az CLI (no SSH required)
  STATUS_OUTPUT=$(az vm run-command invoke \
    --resource-group "$RG_NAME" \
    --name "$VM_NAME" \
    --command-id RunShellScript \
    --scripts "systemctl is-active fastapi-gateway cloudflared 2>&1 || true" \
    --query 'value[0].message' -o tsv 2>/dev/null || echo "error")

  if echo "$STATUS_OUTPUT" | grep -q "^active" && ! echo "$STATUS_OUTPUT" | grep -q "^inactive"; then
    echo "READY"
    ok "Both fastapi-gateway and cloudflared are active"
    READY=true
    break
  fi

  echo "not ready (output: $(echo "$STATUS_OUTPUT" | tr '\n' ' ' | cut -c1-60))"
  sleep 30
done

if [ "$READY" = false ]; then
  warn "Services may still be starting. Check manually:"
  warn "  make vm-status   # check systemctl status"
  warn "  make logs        # view cloud-init output"
fi
echo

# ── Step 3: Health check ───────────────────────────────────────────────────────
echo "── Step 3/4: Testing health endpoint ─────────────"
info "NOTE: Cloudflare Access requires browser authentication."
info "If this fails with 403, open $TUNNEL_URL in your browser first."
echo

HEALTH_OK=false
for i in $(seq 1 5); do
  printf "  Attempt %d/5... " "$i"
  HEALTH=$(curl -sf --max-time 15 "$TUNNEL_URL/health" 2>/dev/null || echo "")
  if [ -n "$HEALTH" ]; then
    echo "OK"
    ok "Health check passed:"
    echo "$HEALTH" | python3 -m json.tool | sed 's/^/    /'
    HEALTH_OK=true
    break
  fi
  echo "no response (Cloudflare Access may require browser login)"
  sleep 15
done

[ "$HEALTH_OK" = true ] || warn "Health check didn't respond — authenticate via browser and retry: make test-health"
echo

# ── Step 4: Summary ────────────────────────────────────────────────────────────
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║                    DEPLOYMENT COMPLETE                               ║"
echo "╠══════════════════════════════════════════════════════════════════════╣"
printf "║  Tunnel:      %-55s ║\n" "$TUNNEL_URL"
printf "║  VM IP:       %-52s ║\n" "$VM_PRIVATE_IP (private only)"
echo "╠══════════════════════════════════════════════════════════════════════╣"
echo "║  Quick test commands:                                                ║"
echo "║    make test-health    →  GET /health (VM hostname + timestamp)      ║"
echo "║    make test-data      →  GET /data/metrics (Snowflake rows)         ║"
echo "║    make test-block     →  Prove VM is unreachable directly           ║"
echo "║    make logs           →  Tail journald (fastapi-gateway, cloudflare)║"
echo "║    make vm-status      →  systemctl status of both services          ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
