output "vm_private_ip" {
  description = "Private IP address of the Linux VM — no public IP exists"
  value       = module.azure.vm_private_ip
}

output "key_vault_uri" {
  description = "Key Vault URI — reachable only from VM subnet via Private Endpoint"
  value       = module.azure.key_vault_uri
}

output "managed_identity_client_id" {
  description = "Client ID of the User-Assigned Managed Identity attached to the VM"
  value       = module.azure.managed_identity_client_id
}

output "tunnel_url" {
  description = "Gateway URL — custom domain if configured, otherwise the default cfargotunnel.com URL"
  value       = module.cloudflare.tunnel_url
}

output "tunnel_id" {
  description = "Cloudflare tunnel ID"
  value       = module.cloudflare.tunnel_id
}

output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace resource ID — use for Syslog queries in portal"
  value       = module.azure.log_analytics_workspace_id
}

output "ssh_instructions" {
  description = "How to retrieve the VM SSH key (Bastion required for actual SSH)"
  value       = "Run: make ssh-key  (fetches SSH-PRIVATE-KEY secret from Key Vault)"
}

output "test_urls" {
  description = "Quick-reference test URLs"
  value = {
    health           = "${module.cloudflare.tunnel_url}/health"
    health_snowflake = "${module.cloudflare.tunnel_url}/health/snowflake"
    metrics          = "${module.cloudflare.tunnel_url}/data/metrics"
    summary          = "${module.cloudflare.tunnel_url}/data/metrics/summary"
    prod_metrics     = "${module.cloudflare.tunnel_url}/data/metrics/prod"
  }
}
