output "security_contact_id" {
  description = "Resource ID of the Defender for Cloud security contact."
  value       = azapi_resource.security_contact.id
}

output "defender_plans_enabled" {
  description = "Paid Defender plans this configuration turned on (empty by default)."
  value       = { for k, v in azurerm_security_center_subscription_pricing.plan : k => v.subplan == null ? "Standard" : "Standard/${v.subplan}" }
}

output "sentinel_workspace_id" {
  description = "Resource ID of the Sentinel workspace (null unless deploy_sentinel = true)."
  value       = try(azurerm_log_analytics_workspace.security[0].id, null)
}

output "activity_log_diagnostic_setting_id" {
  description = "Resource ID of the subscription diagnostic setting feeding the workspace (null unless deployed)."
  value       = try(azurerm_monitor_diagnostic_setting.activity_to_sentinel[0].id, null)
}
