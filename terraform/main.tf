provider "azurerm" {
  features {
    key_vault {
      # Allow Terraform destroy to purge soft-deleted Key Vaults in demo environments
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "snowflake" {
  account  = var.snowflake_account
  username = var.snowflake_admin_user
  password = var.snowflake_admin_password
}

# ── Step 1: Cloudflare tunnel (must be first — tunnel token goes into Key Vault) ──

module "cloudflare" {
  source = "./modules/cloudflare"

  account_id            = var.cloudflare_account_id
  zone_id               = var.cloudflare_zone_id
  tunnel_name           = "zero-trust-gateway-vm-tunnel"
  tunnel_hostname       = var.tunnel_hostname
  allowed_email         = var.allowed_email
  enable_gateway_egress = var.enable_gateway_egress
  enable_access_app     = var.enable_access_app
}

# ── Step 2: Azure infra — VM, Key Vault (PE), Managed Identity ─────────────────
# The tunnel token from step 1 is stored as a Key Vault secret here.
# The VM fetches it at boot via IMDS → Key Vault → cloudflared.

module "azure" {
  source = "./modules/azure"

  resource_group_name     = var.resource_group_name
  location                = var.location
  key_vault_name          = var.key_vault_name
  snowflake_account       = var.snowflake_account
  snowflake_user          = var.snowflake_svc_user
  snowflake_password      = var.snowflake_svc_password
  cloudflare_tunnel_token = module.cloudflare.tunnel_token
  deploy_bastion          = var.deploy_bastion
}

# ── Step 3: Snowflake objects — DB, schema, table, seed data, network policy ───
# Whitelists Cloudflare Gateway egress IP in Snowflake network policy.
# Falls back to demo-safe "allow all" ranges when enable_gateway_egress=false.

module "snowflake" {
  source = "./modules/snowflake"

  snowflake_svc_password = var.snowflake_svc_password
  cloudflare_egress_ips  = var.enable_gateway_egress ? [module.cloudflare.egress_ip] : []
}
