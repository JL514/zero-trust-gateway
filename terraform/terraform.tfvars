# ── Azure ─────────────────────────────────────────────────────────────────────
resource_group_name = "rg-zero-trust-gateway2"
location            = "eastus"
key_vault_name      = "kv-ztgw2-demo"
deploy_bastion      = false

# ── Snowflake (admin — used by Terraform to provision objects) ─────────────────
snowflake_account        = "DFTVADZ-ZWC14995"
snowflake_admin_user     = "JL514"
snowflake_admin_password = "Moldi3sthobbes10%"

# ── Snowflake (service account created by Terraform for FastAPI runtime) ────────
# Password is a placeholder — rotate it in Key Vault after first deploy.
snowflake_svc_user     = "GATEWAY_SVC"
snowflake_svc_password = "RotateMe-GatewaySvc-2026!"

# ── Cloudflare ────────────────────────────────────────────────────────────────
cloudflare_api_token  = "A_J498Ij2b1_PmnkxMRTo3hX_3mrVnabeL0iGXQw"
cloudflare_account_id = "b145953419e001b84c19e3e8e8f913d1"
# No custom domain — tunnel URL is https://<tunnel-id>.cfargotunnel.com (shown after apply)
# To add a domain later: set zone_id + tunnel_hostname, set enable_access_app=true
cloudflare_zone_id    = "931d04323a31a7dcdaf2e082b1862112"
tunnel_hostname       = "ztgw.cloudtechsolution.net"
allowed_email         = "jasonl514@pm.me"
enable_gateway_egress = false
enable_access_app     = true
