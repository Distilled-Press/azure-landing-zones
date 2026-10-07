output "resource_group_name" {
  description = "Name of the management resource group."
  value       = module.resource_group.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the central Log Analytics workspace. Chapter 6's policy_default_values key: log_analytics_workspace_id."
  value       = module.log_analytics.resource_id
}

output "vm_insights_data_collection_rule_id" {
  description = "Resource ID of the VM insights data collection rule. Chapter 6 key: ama_vm_insights_data_collection_rule_id."
  value       = module.dcr_vm_insights.resource_id
}

output "ama_user_assigned_identity" {
  description = "The Azure Monitor Agent identity. Chapter 6 keys: ama_user_assigned_managed_identity_id and ama_user_assigned_managed_identity_name."
  value = {
    id   = module.ama_identity.resource_id
    name = module.ama_identity.resource_name
  }
}

output "action_group_id" {
  description = "Resource ID of the platform action group."
  value       = azurerm_monitor_action_group.platform.id
}

output "action_group_email_receivers_to_verify" {
  description = "Email addresses that must complete the one-time passcode verification within 30 minutes of this apply (addresses already verified in the tenant are not asked again)."
  value       = var.action_group_email_addresses
}

output "service_health_alert_id" {
  description = "Resource ID of the Service Health alert, or null when disabled."
  value       = one(azurerm_monitor_activity_log_alert.service_health[*].id)
}

output "amba" {
  description = "AMBA-ALZ deployment summary, or null when deploy_amba = false."
  value = var.deploy_amba ? {
    management_group_id            = var.amba_management_group_id
    enforcement_mode               = var.amba_enforcement_mode
    identity_id                    = module.amba_identity[0].user_assigned_managed_identity_resource_id
    policy_definitions             = length(module.amba_policy[0].policy_definition_resource_ids)
    policy_set_definitions         = length(module.amba_policy[0].policy_set_definition_resource_ids)
    policy_assignment_resource_ids = module.amba_policy[0].policy_assignment_resource_ids
  } : null
}
