output "dns_resource_group_name" {
  description = "Name of the DNS resource group."
  value       = module.dns_resource_group.name
}

output "private_dns_zone_ids" {
  description = "Resource IDs of the private DNS zones, by key. Chapter 10's Deploy-Private-DNS-Zones policy assignment needs these."
  value       = module.private_dns_zones.private_dns_zone_resource_ids
}

output "dns_resolver_inbound_ip" {
  description = "IP of the DNS Private Resolver inbound endpoint (null when deploy_dns_resolver = false). Point on-premises conditional forwarders here."
  value       = var.deploy_dns_resolver ? module.dns_resolver[0].inbound_endpoint_ips["inbound"] : null
}

output "dns_forwarding_rulesets" {
  description = "The DNS forwarding ruleset(s) (empty when deploy_dns_resolver = false)."
  value       = var.deploy_dns_resolver ? module.dns_resolver[0].forwarding_rulesets : {}
}

output "virtual_wan_id" {
  description = "Resource ID of the Virtual WAN (null when deploy_virtual_wan = false)."
  value       = var.deploy_virtual_wan ? module.virtual_wan[0].resource_id : null
}

output "virtual_hub_id" {
  description = "Resource ID of the virtual hub (null when deploy_virtual_wan = false)."
  value       = var.deploy_virtual_wan ? module.virtual_wan[0].virtual_hub_resource_ids["primary"] : null
}

output "virtual_hub_firewall_private_ip" {
  description = "Private IP of the secured hub's Azure Firewall (null unless deploy_secured_hub = true)."
  value       = var.deploy_virtual_wan && var.deploy_secured_hub ? module.virtual_wan[0].firewall_private_ip_address["primary"] : null
}
