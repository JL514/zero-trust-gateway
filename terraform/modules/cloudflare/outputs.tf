output "tunnel_id" {
  description = "Cloudflare tunnel UUID"
  value       = cloudflare_tunnel.gateway.id
}

output "tunnel_token" {
  description = "Cloudflare tunnel token — used by cloudflared daemon. Stored in Key Vault."
  value       = cloudflare_tunnel.gateway.tunnel_token
  sensitive   = true
}

output "tunnel_url" {
  description = "URL to reach the gateway. Custom domain if configured, otherwise the default cfargotunnel.com URL."
  value       = var.tunnel_hostname != "" ? "https://${var.tunnel_hostname}" : "https://${cloudflare_tunnel.gateway.id}.cfargotunnel.com"
}

output "egress_ip" {
  description = "Cloudflare Gateway egress IP/CIDR (meaningful only when enable_gateway_egress=true)"
  value       = var.enable_gateway_egress ? tolist(cloudflare_teams_location.demo[0].networks)[0].network : "0.0.0.0/0"
}
