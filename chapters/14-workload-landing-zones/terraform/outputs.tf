output "resource_group_name" {
  description = "Name of the workload resource group."
  value       = module.resource_group.name
}

output "virtual_network_id" {
  description = "Resource ID of the workload spoke VNet."
  value       = module.vnet.resource_id
}

output "subnet_ids" {
  description = "Resource IDs of the spoke subnets, by key (host, container, private_endpoints)."
  value       = { for k, s in module.vnet.subnets : k => s.resource_id }
}

output "databricks_workspace_id" {
  description = "Resource ID of the Databricks workspace (null when deploy_databricks = false)."
  value       = var.deploy_databricks ? module.databricks[0].resource_id : null
}

output "databricks_workspace_name" {
  description = "Name of the Databricks workspace (null when deploy_databricks = false). The destroy steps in the README need it."
  value       = var.deploy_databricks ? module.databricks[0].name : null
}

output "databricks_workspace_url" {
  description = "Workspace URL, adb-<id>.<n>.azuredatabricks.net (null when deploy_databricks = false)."
  value       = var.deploy_databricks ? module.databricks[0].databricks_workspace_url : null
}

output "databricks_managed_resource_group_id" {
  description = "Resource ID of the managed resource group Databricks owns (null when deploy_databricks = false)."
  value       = var.deploy_databricks ? module.databricks[0].databricks_workspace_managed_resource_group_id : null
}

output "access_connector_id" {
  description = "Resource ID of the access connector to register as a Unity Catalog storage credential (null when deploy_databricks = false)."
  value       = var.deploy_databricks ? module.databricks[0].databricks_access_connector_ids["lake"] : null
}

output "lake_storage_account_name" {
  description = "Name of the ADLS Gen2 storage account (null when deploy_databricks = false)."
  value       = var.deploy_databricks ? module.lake[0].name : null
}

output "nat_gateway_public_ip_id" {
  description = "Resource ID of the clusters' stable egress public IP (null when the NAT gateway isn't deployed). az network public-ip show --ids <id> --query ipAddress shows the address."
  value       = local.nat_gateway_deployed ? values(module.nat_gateway[0].public_ip_resource)[0].id : null
}
