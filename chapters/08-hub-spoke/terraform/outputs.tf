output "hub_resource_group_name" {
  description = "Name of the hub resource group."
  value       = module.hub_resource_group.name
}

output "hub_virtual_network_id" {
  description = "Resource ID of the hub virtual network. Chapter 9 takes this as its input; chapter 7 takes it as hub_virtual_network_id for spoke peering."
  value       = module.hub_vnet.resource_id
}

output "hub_subnet_ids" {
  description = "Resource IDs of the hub subnets, by key."
  value       = { for k, s in module.hub_vnet.subnets : k => s.resource_id }
}

output "spoke_virtual_network_id" {
  description = "Resource ID of the example spoke virtual network."
  value       = module.spoke_vnet.resource_id
}

output "spoke_route_table_id" {
  description = "Resource ID of the spoke route table."
  value       = module.spoke_route_table.resource_id
}

output "firewall_private_ip" {
  description = "Private IP address of Azure Firewall (null when deploy_firewall = false). The spoke routes use it as their next hop."
  value       = local.firewall_private_ip
}

output "firewall_policy_id" {
  description = "Resource ID of the firewall policy (null when deploy_firewall = false)."
  value       = var.deploy_firewall ? module.firewall_policy[0].resource_id : null
}

output "vpn_gateway_id" {
  description = "Resource ID of the VPN gateway (null when deploy_vpn_gateway = false)."
  value       = var.deploy_vpn_gateway ? module.vpn_gateway[0].resource_id : null
}
