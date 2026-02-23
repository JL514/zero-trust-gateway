# ── Tunnel Secret ─────────────────────────────────────────────────────────────
# Cloudflare requires a 32-byte base64-encoded secret for the tunnel.

resource "random_id" "tunnel_secret" {
  byte_length = 32
}

# ── Cloudflare Tunnel ─────────────────────────────────────────────────────────
# Creates a named tunnel. The tunnel_token output is a signed credential used
# by cloudflared to authenticate outbound connections to Cloudflare's edge.
# The token is stored in Azure Key Vault and fetched by the VM at boot.

resource "cloudflare_tunnel" "gateway" {
  account_id = var.account_id
  name       = var.tunnel_name
  secret     = random_id.tunnel_secret.b64_std
}

# ── Tunnel Config: Route traffic to the FastAPI app ──────────────────────────
# Rule 1: Tunnel hostname → localhost:8000 (FastAPI/uvicorn)
# Rule 2: Catch-all → 404 (security: reject unexpected hostnames)

resource "cloudflare_tunnel_config" "gateway" {
  account_id = var.account_id
  tunnel_id  = cloudflare_tunnel.gateway.id

  config {
    # When a custom hostname is provided, pin the rule to that domain.
    # Without a domain the tunnel uses its default <id>.cfargotunnel.com URL,
    # so we skip the hostname-specific rule and let the catch-all handle it.
    dynamic "ingress_rule" {
      for_each = var.tunnel_hostname != "" ? [1] : []
      content {
        hostname = var.tunnel_hostname
        service  = "http://localhost:8000"
      }
    }

    ingress_rule {
      # With a custom hostname: catch-all returns 404 (rejects unknown domains).
      # Without a custom hostname: catch-all routes all traffic to FastAPI.
      service = var.tunnel_hostname != "" ? "http_status:404" : "http://localhost:8000"
    }
  }
}

# ── Cloudflare Access Application ────────────────────────────────────────────
# Puts an identity gate in front of the tunnel hostname.
# Any request to tunnel_hostname must first authenticate with Cloudflare Access.

resource "cloudflare_access_application" "gateway" {
  count            = var.enable_access_app ? 1 : 0
  account_id       = var.account_id
  name             = "Zero Trust VM Gateway"
  domain           = var.tunnel_hostname
  type             = "self_hosted"
  session_duration = "24h"
}

# ── Cloudflare Access Policy: Allow whitelisted email ────────────────────────

resource "cloudflare_access_policy" "allow_demo" {
  count          = var.enable_access_app ? 1 : 0
  application_id = cloudflare_access_application.gateway[0].id
  account_id     = var.account_id
  name           = "Allow Demo User"
  precedence     = 1
  decision       = "allow"

  include {
    email = [var.allowed_email]
  }
}

# ── Cloudflare Gateway: Egress location (optional) ────────────────────────────
# Only created when enable_gateway_egress=true (requires Cloudflare Gateway plan).
# This enables a dedicated static egress IP for whitelisting in Snowflake's network policy.

resource "cloudflare_teams_location" "demo" {
  count      = var.enable_gateway_egress ? 1 : 0
  account_id = var.account_id
  name       = "Zero Trust VM Demo Location"

  networks {
    network = "0.0.0.0/0"
  }
}

# ── Cloudflare Gateway: Egress rule for Snowflake traffic ────────────────────
# Routes *.snowflakecomputing.com requests through the dedicated egress IP.

resource "cloudflare_teams_rule" "snowflake_egress" {
  count       = var.enable_gateway_egress ? 1 : 0
  account_id  = var.account_id
  name        = "Snowflake Static Egress"
  description = "Route Snowflake traffic through dedicated static IP for network policy whitelisting"
  precedence  = 10
  action      = "egress"
  filters     = ["http"]
  traffic     = "any(http.request.domains[*] matches \".*\\.snowflakecomputing\\.com\")"

  rule_settings {
    egress {
      ipv4          = tolist(cloudflare_teams_location.demo[0].networks)[0].network
      ipv4_fallback = tolist(cloudflare_teams_location.demo[0].networks)[0].network
      ipv6          = ""
    }
  }
}
