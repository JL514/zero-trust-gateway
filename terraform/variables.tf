# ── Azure ─────────────────────────────────────────────────────────────────────

variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
  default     = "rg-zero-trust-gateway"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus"
}

variable "key_vault_name" {
  description = "Globally unique Key Vault name (3-24 alphanumeric + hyphens)"
  type        = string
}

variable "deploy_bastion" {
  description = "Deploy Azure Bastion for SSH access to the VM. Adds ~$5/day cost. Default false for demo."
  type        = bool
  default     = false
}

# ── Snowflake (admin account used by Terraform to provision objects) ───────────

variable "snowflake_account" {
  description = "Snowflake account identifier (e.g. xy12345.us-east-1)"
  type        = string
}

variable "snowflake_admin_user" {
  description = "Snowflake admin username for Terraform provisioning (needs SYSADMIN + SECURITYADMIN)"
  type        = string
}

variable "snowflake_admin_password" {
  description = "Snowflake admin password"
  type        = string
  sensitive   = true
}

# ── Snowflake (service account created by Terraform, used by FastAPI at runtime) ─

variable "snowflake_svc_user" {
  description = "Username for the Snowflake gateway service account (created by Terraform)"
  type        = string
  default     = "GATEWAY_SVC"
}

variable "snowflake_svc_password" {
  description = "Password for the Snowflake gateway service account"
  type        = string
  sensitive   = true
}

# ── Cloudflare ────────────────────────────────────────────────────────────────

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zero Trust:Edit, DNS:Edit permissions"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID (found in dashboard URL or account settings)"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare DNS zone ID. Leave empty when no custom domain is configured."
  type        = string
  default     = ""
}

variable "tunnel_hostname" {
  description = "Custom FQDN for the gateway (e.g. gateway.yourdomain.com). Leave empty to use the default <tunnel-id>.cfargotunnel.com URL."
  type        = string
  default     = ""
}

variable "allowed_email" {
  description = "Email address allowed through Cloudflare Access (demo: your own email)"
  type        = string
}

variable "enable_gateway_egress" {
  description = "Enable Cloudflare Gateway egress policy for static IP → Snowflake network policy. Requires Gateway plan."
  type        = bool
  default     = false
}

variable "enable_access_app" {
  description = "Create Cloudflare Access Application and policy. Set true only after adding the domain as a zone in the Cloudflare account."
  type        = bool
  default     = false
}
