output "resource_group_id" {
  description = "Resource ID of the adopted resource group."
  value       = azurerm_resource_group.brownfield.id
}

output "virtual_network_id" {
  description = "Resource ID of the adopted VNet."
  value       = azurerm_virtual_network.brownfield.id
}

output "network_security_group_id" {
  description = "Resource ID of the adopted NSG."
  value       = azurerm_network_security_group.app.id
}
