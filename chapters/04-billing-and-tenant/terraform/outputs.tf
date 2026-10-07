output "subscription_id" {
  description = "ID of the subscription the alias created."
  value       = local.subscription_id
}

output "subscription_resource_id" {
  description = "Resource ID of the new subscription."
  value       = "/subscriptions/${local.subscription_id}"
}

output "subscription_alias_id" {
  description = "Resource ID of the alias."
  value       = azapi_resource.subscription_alias.id
}
