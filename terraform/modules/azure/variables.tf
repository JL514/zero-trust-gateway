variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "key_vault_name" {
  description = "Globally unique Key Vault name (3-24 alphanumeric + hyphens)"
  type        = string
}

variable "snowflake_account" {
  type = string
}

variable "snowflake_user" {
  type = string
}

variable "snowflake_password" {
  type      = string
  sensitive = true
}

variable "cloudflare_tunnel_token" {
  description = "Cloudflare tunnel token (from cloudflare module). Stored as Key Vault secret."
  type        = string
  sensitive   = true
}

variable "deploy_bastion" {
  description = "Deploy Azure Bastion host. Set false to keep demo cost near zero."
  type        = bool
  default     = false
}

variable "vm_size" {
  description = "Azure VM size. Standard_B1s is free-tier eligible for new subscriptions."
  type        = string
  default     = "Standard_B1s"
}

variable "admin_username" {
  type    = string
  default = "azureuser"
}

variable "tags" {
  type = map(string)
  default = {
    project     = "zero-trust-gateway"
    environment = "demo"
    managed_by  = "terraform"
  }
}
