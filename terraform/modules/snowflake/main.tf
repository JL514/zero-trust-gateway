# ── Database ──────────────────────────────────────────────────────────────────

resource "snowflake_database" "demo" {
  name    = "DEMO_DB"
  comment = "Zero Trust Gateway demo database"
}

# ── Schema ────────────────────────────────────────────────────────────────────

resource "snowflake_schema" "demo" {
  database = snowflake_database.demo.name
  name     = "DEMO_SCHEMA"
  comment  = "Demo schema for infrastructure metrics"
}

# ── Table: INFRASTRUCTURE_METRICS ─────────────────────────────────────────────

resource "snowflake_table" "metrics" {
  database = snowflake_database.demo.name
  schema   = snowflake_schema.demo.name
  name     = "INFRASTRUCTURE_METRICS"
  comment  = "Monthly infrastructure cost, incident, and reliability metrics by environment"

  column {
    name = "DATE"
    type = "DATE"
  }

  column {
    name = "ENVIRONMENT"
    type = "VARCHAR(50)"
  }

  column {
    name = "RESOURCE_TYPE"
    type = "VARCHAR(100)"
  }

  column {
    name = "COST_USD"
    type = "FLOAT"
  }

  column {
    name = "INCIDENT_COUNT"
    type = "NUMBER(10,0)"
  }

  column {
    name = "MTTR_MINUTES"
    type = "FLOAT"
  }

  column {
    name    = "VM_UPTIME_PCT"
    type    = "FLOAT"
    comment = "VM availability percentage (100.0 = no downtime)"
  }
}

# NOTE: Seed data (INSERT rows) is intentionally not managed by Terraform.
# Run the INSERT statement in scripts/seed_data.sql after 'make apply'.

# ── Role ──────────────────────────────────────────────────────────────────────

resource "snowflake_role" "gateway" {
  name    = "GATEWAY_ROLE"
  comment = "Minimal read-only role for the Zero Trust Gateway service account"
}

# ── Service Account User ──────────────────────────────────────────────────────

resource "snowflake_user" "gateway_svc" {
  name                 = "GATEWAY_SVC"
  password             = var.snowflake_svc_password
  default_role         = snowflake_role.gateway.name
  default_warehouse    = "COMPUTE_WH"
  must_change_password = false
  comment              = "Zero Trust Gateway service account - read-only via GATEWAY_ROLE"
}

# ── Privileges ────────────────────────────────────────────────────────────────

resource "snowflake_grant_privileges_to_role" "db_usage" {
  role_name  = snowflake_role.gateway.name
  privileges = ["USAGE"]

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.demo.name
  }
}

resource "snowflake_grant_privileges_to_role" "schema_usage" {
  role_name  = snowflake_role.gateway.name
  privileges = ["USAGE"]

  on_schema {
    schema_name = "\"${snowflake_database.demo.name}\".\"${snowflake_schema.demo.name}\""
  }
}

resource "snowflake_grant_privileges_to_role" "table_select" {
  role_name  = snowflake_role.gateway.name
  privileges = ["SELECT"]

  on_schema_object {
    object_type = "TABLE"
    object_name = "\"${snowflake_database.demo.name}\".\"${snowflake_schema.demo.name}\".\"${snowflake_table.metrics.name}\""
  }
}

resource "snowflake_role_grants" "gateway_svc" {
  role_name = snowflake_role.gateway.name
  users     = [snowflake_user.gateway_svc.name]
}

# ── Network Policy ────────────────────────────────────────────────────────────

resource "snowflake_network_policy" "cloudflare_egress" {
  name = "CLOUDFLARE_EGRESS_POLICY"
  allowed_ip_list = (
    length(var.cloudflare_egress_ips) > 0
    ? var.cloudflare_egress_ips
    : ["0.0.0.0/1", "128.0.0.0/1"]
  )
  comment = "Restrict GATEWAY_SVC to Cloudflare Gateway egress IPs. Use real IPs in production."
}

resource "snowflake_network_policy_attachment" "gateway_svc" {
  network_policy_name = snowflake_network_policy.cloudflare_egress.name
  set_for_account     = false
  users               = [snowflake_user.gateway_svc.name]
  depends_on          = [snowflake_user.gateway_svc]
}
