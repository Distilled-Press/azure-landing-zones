output "tenant_id" {
  description = "Tenant ID: the AZURE_TENANT_ID repository variable."
  value       = module.identity[keys(var.identities)[0]].tenant_id
}

output "subscription_id" {
  description = "The AZURE_SUBSCRIPTION_ID repository variable (any subscription the identities can read; the azurerm and azapi providers need one)."
  value       = var.subscription_id
}

output "client_ids" {
  description = "Identity key => client ID: the AZURE_CLIENT_ID_PLAN / AZURE_CLIENT_ID_APPLY repository variables."
  value       = { for k, m in module.identity : k => m.client_id }
}

output "principal_ids" {
  description = "Identity key => principal (object) ID."
  value       = { for k, m in module.identity : k => m.principal_id }
}

output "federated_credential_subjects" {
  description = "Identity key => the subjects its federated credentials trust."
  value       = { for k, creds in local.federated_credentials : k => sort([for c in creds : c.subject]) }
}

output "role_assignments" {
  description = "Identity key => role on the management group."
  value       = { for k, r in azurerm_role_assignment.management_group : k => "${r.role_definition_name} on ${r.scope}" }
}

output "state_backend" {
  description = "Backend settings for the pipelines, or null when state_storage_enabled = false."
  value = var.state_storage_enabled ? {
    resource_group_name  = module.resource_group.name
    storage_account_name = module.state_storage[0].name
    container_name       = "tfstate"
  } : null
}
