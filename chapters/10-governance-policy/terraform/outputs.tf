output "management_group_id" {
  description = "Resource ID of the test management group."
  value       = azurerm_management_group.test.id
}

output "policy_definition_id" {
  description = "Resource ID of the custom policy definition."
  value       = azurerm_policy_definition.require_rg_tag.id
}

output "policy_set_definition_id" {
  description = "Resource ID of the custom initiative."
  value       = azurerm_management_group_policy_set_definition.guardrails.id
}

output "guardrails_assignment_id" {
  description = "Resource ID of the initiative assignment."
  value       = azurerm_management_group_policy_assignment.guardrails.id
}

output "inherit_tag_assignment_id" {
  description = "Resource ID of the Modify assignment."
  value       = azurerm_management_group_policy_assignment.inherit_tag.id
}

output "inherit_tag_principal_id" {
  description = "Object ID of the Modify assignment's system-assigned managed identity."
  value       = azurerm_management_group_policy_assignment.inherit_tag.identity[0].principal_id
}

output "exemption_expires_on" {
  description = "When the allowed-locations waiver stops applying."
  value       = azurerm_management_group_policy_exemption.location_waiver.expires_on
}

output "remediation_command" {
  description = "Azure CLI command to start a remediation task for the Modify assignment by hand."
  value       = "az policy remediation create --name ${var.prefix}-inherit-tag-remediation --management-group ${azurerm_management_group.test.name} --policy-assignment ${azurerm_management_group_policy_assignment.inherit_tag.id}"
}
