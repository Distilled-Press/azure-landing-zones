output "management_group_resource_ids" {
  description = "Management group ID => resource ID, for the hierarchy this module created."
  value       = module.alz.management_group_resource_ids
}

output "policy_assignment_resource_ids" {
  description = "Policy assignment => resource ID (keys are <management group>/<assignment name>)."
  value       = module.alz.policy_assignment_resource_ids
}

output "policy_assignment_enforcement" {
  description = "Enforcement mode chosen for this deployment and the assignments it was overridden on."
  value = {
    mode       = var.policy_assignment_enforcement_mode
    overridden = { for mg_id, v in local.enforcement_overrides : mg_id => sort(keys(v.policy_assignments)) }
  }
}

output "custom_policy_definition_count" {
  description = "Number of custom policy and policy set definitions deployed from the ALZ library."
  value = {
    policy_definitions     = length(module.alz.policy_definition_resource_ids)
    policy_set_definitions = length(module.alz.policy_set_definition_resource_ids)
    role_definitions       = length(module.alz.role_definition_resource_ids)
  }
}
