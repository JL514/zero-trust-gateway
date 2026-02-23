output "database_name" {
  value = snowflake_database.demo.name
}

output "schema_name" {
  value = snowflake_schema.demo.name
}

output "table_name" {
  value = snowflake_table.metrics.name
}

output "gateway_role" {
  value = snowflake_role.gateway.name
}

output "network_policy_name" {
  value = snowflake_network_policy.cloudflare_egress.name
}
