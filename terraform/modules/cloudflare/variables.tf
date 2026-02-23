variable "account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "zone_id" {
  description = "Cloudflare DNS zone ID. Leave empty when no custom domain is configured."
  type        = string
  default     = ""
}

variable "tunnel_name" {
  description = "Display name for the Cloudflare tunnel"
  type        = string
  default     = "zero-trust-gateway-vm-tunnel"
}

variable "tunnel_hostname" {
  description = "Custom FQDN for the tunnel (e.g. gateway.yourdomain.com). Leave empty to use the default <tunnel-id>.cfargotunnel.com URL."
  type        = string
  default     = ""
}

variable "allowed_email" {
  description = "Email address allowed through the Cloudflare Access policy"
  type        = string
}

variable "enable_gateway_egress" {
  description = "Create Gateway location and egress rule for static IP assignment"
  type        = bool
  default     = false
}

variable "enable_access_app" {
  description = "Create Cloudflare Access Application and policy. Requires the tunnel_hostname domain to be a zone in the Cloudflare account."
  type        = bool
  default     = true
}
