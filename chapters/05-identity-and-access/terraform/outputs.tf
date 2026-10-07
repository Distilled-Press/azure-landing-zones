output "application_owner_role_definition_id" {
  description = "Resource ID of the custom Landing Zone Application Owner role (chapter 7 assigns it at subscription scope)."
  value       = azurerm_role_definition.application_owner.role_definition_resource_id
}

output "network_management_role_definition_id" {
  description = "Resource ID of the custom Network Management role."
  value       = azurerm_role_definition.network_management.role_definition_resource_id
}

output "role_assignment_ids" {
  description = "IDs of the active role assignments this module created."
  value = merge(
    { for ra in azurerm_role_assignment.platform_team_owner : "platform_team_owner" => ra.id },
    {
      workload_team_contributor = azurerm_role_assignment.workload_team_contributor.id
      security_ops_reader       = azurerm_role_assignment.security_ops_reader.id
    },
    { for ra in azurerm_role_assignment.network_ops : "network_ops" => ra.id },
  )
}

output "pim_eligible_assignment_ids" {
  description = "IDs of the PIM-eligible assignments (empty when PIM is off)."
  value = concat(
    azurerm_pim_eligible_role_assignment.platform_team_owner[*].id,
    azurerm_pim_eligible_role_assignment.platform_team_landing_zones_contributor[*].id,
  )
}
