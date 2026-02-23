variable "snowflake_svc_password" {
  description = "Password for the GATEWAY_SVC Snowflake user"
  type        = string
  sensitive   = true
}

variable "cloudflare_egress_ips" {
  description = <<-EOT
    Cloudflare Gateway egress IPs to whitelist in the Snowflake network policy.
    When empty (enable_gateway_egress=false), falls back to ["0.0.0.0/1","128.0.0.0/1"]
    which effectively allows all IPs — safe for demos, not for production.
  EOT
  type        = list(string)
  default     = []
}
