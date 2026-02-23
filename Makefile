.PHONY: init plan apply destroy ssh-key ssh logs vm-status test-health test-data test-block help

SHELL       := /bin/bash
TF_DIR      := terraform
VM_NAME     := vm-zero-trust-gateway

# Lazy eval — only runs when target is invoked
TUNNEL_URL      := $(shell cd $(TF_DIR) && terraform output -raw tunnel_url 2>/dev/null || echo "NOT_DEPLOYED")
VM_PRIVATE_IP   := $(shell cd $(TF_DIR) && terraform output -raw vm_private_ip    2>/dev/null || echo "NOT_DEPLOYED")
KV_URI          := $(shell cd $(TF_DIR) && terraform output -raw key_vault_uri     2>/dev/null || echo "NOT_DEPLOYED")
KV_NAME         := $(shell echo "$(KV_URI)" | sed 's|https://||;s|\.vault\.azure\.net.*||')
RG_NAME         := $(shell grep -E '^resource_group_name\s*=' $(TF_DIR)/terraform.tfvars 2>/dev/null \
                     | awk -F'"' '{print $$2}' || echo "rg-zero-trust-gateway")

# ── Terraform lifecycle ───────────────────────────────────────────────────────

help: ## Show available make targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

init: ## terraform init — download providers
	cd $(TF_DIR) && terraform init

plan: ## terraform plan — preview changes
	cd $(TF_DIR) && terraform plan

apply: ## terraform apply — provision all infrastructure
	cd $(TF_DIR) && terraform apply

destroy: ## terraform destroy — tear down all infrastructure
	cd $(TF_DIR) && terraform destroy

# ── VM access ────────────────────────────────────────────────────────────────

ssh-key: ## Retrieve SSH private key from Key Vault → ~/.ssh/zt-vm-demo.pem
	@echo "Fetching SSH-PRIVATE-KEY from Key Vault: $(KV_NAME)"
	@az keyvault secret show \
	  --vault-name "$(KV_NAME)" \
	  --name "SSH-PRIVATE-KEY" \
	  --query value -o tsv > ~/.ssh/zt-vm-demo.pem
	@chmod 600 ~/.ssh/zt-vm-demo.pem
	@echo "Key saved to ~/.ssh/zt-vm-demo.pem  (VM private IP: $(VM_PRIVATE_IP))"
	@echo "NOTE: SSH access requires deploy_bastion=true in terraform.tfvars"

ssh: ## SSH to VM via Azure Bastion (requires deploy_bastion=true + make ssh-key)
	@[ "$(VM_PRIVATE_IP)" != "NOT_DEPLOYED" ] || (echo "Error: run make apply first"; exit 1)
	az network bastion ssh \
	  --name "bastion-zero-trust-gateway" \
	  --resource-group "$(RG_NAME)" \
	  --target-resource-id "$$(az vm show -g "$(RG_NAME)" -n "$(VM_NAME)" --query id -o tsv)" \
	  --auth-type ssh-key \
	  --username azureuser \
	  --ssh-key ~/.ssh/zt-vm-demo.pem

# ── Observability ─────────────────────────────────────────────────────────────

logs: ## Tail journald logs for fastapi-gateway + cloudflared via az run-command
	@echo "Fetching last 60 log lines from $(VM_NAME)..."
	az vm run-command invoke \
	  --resource-group "$(RG_NAME)" \
	  --name "$(VM_NAME)" \
	  --command-id RunShellScript \
	  --scripts "journalctl -u fastapi-gateway -u cloudflared -n 60 --no-pager"

vm-status: ## Check systemctl status of both gateway services
	az vm run-command invoke \
	  --resource-group "$(RG_NAME)" \
	  --name "$(VM_NAME)" \
	  --command-id RunShellScript \
	  --scripts "systemctl status fastapi-gateway cloudflared --no-pager; echo; cat /var/log/bootstrap-cloudflared.log | tail -20"

# ── Testing ───────────────────────────────────────────────────────────────────

test-health: ## curl /health endpoint through the Cloudflare tunnel
	@echo "GET $(TUNNEL_URL)/health"
	@curl -sf "$(TUNNEL_URL)/health" | python3 -m json.tool

test-data: ## curl /data/metrics endpoint through the Cloudflare tunnel
	@echo "GET $(TUNNEL_URL)/data/metrics"
	@curl -sf "$(TUNNEL_URL)/data/metrics" | python3 -m json.tool

test-block: ## Attempt direct TCP to VM private IP (must time out — proves no public access)
	@echo "=== Attempting direct connection to VM private IP ==="
	@echo "This should TIME OUT — VM has no public IP and NSG denies all inbound"
	@echo
	@echo "Test 1: $(VM_PRIVATE_IP):8000 (FastAPI)"
	@nc -zv -w 5 "$(VM_PRIVATE_IP)" 8000 2>&1 && echo "UNEXPECTED: connection succeeded!" || echo "CORRECT: connection refused/timed out"
	@echo
	@echo "Test 2: $(VM_PRIVATE_IP):22 (SSH)"
	@nc -zv -w 5 "$(VM_PRIVATE_IP)" 22 2>&1 && echo "UNEXPECTED: connection succeeded!" || echo "CORRECT: no SSH from internet"
