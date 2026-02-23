output "vm_private_ip" {
  description = "Private IP of the Linux VM (no public IP assigned)"
  value       = azurerm_linux_virtual_machine.gateway.private_ip_address
}

output "key_vault_uri" {
  description = "Key Vault URI — accessible only via Private Endpoint from vm-subnet"
  value       = azurerm_key_vault.kv.vault_uri
}

output "managed_identity_client_id" {
  description = "Client ID of the User-Assigned Managed Identity"
  value       = azurerm_user_assigned_identity.gateway.client_id
}

output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace resource ID"
  value       = azurerm_log_analytics_workspace.law.id
}

output "ssh_public_key" {
  description = "Generated RSA-4096 public key (used as VM admin_ssh_key)"
  value       = tls_private_key.vm_ssh.public_key_openssh
}
