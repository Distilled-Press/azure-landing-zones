output "subscription_id" {
  description = "ID of the vended (created or existing) subscription."
  value       = module.sub_vending.subscription_id
}

output "virtual_network_resource_ids" {
  description = "Resource ID of the spoke virtual network."
  value       = module.sub_vending.virtual_network_resource_ids
}

output "budget_resource_ids" {
  description = "Resource ID of the subscription budget."
  value       = module.sub_vending.budget_resource_id
}

output "resource_group_resource_ids" {
  description = "Resource IDs of the resource groups created in the subscription."
  value       = module.sub_vending.resource_group_resource_ids
}
