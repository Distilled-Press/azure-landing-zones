# Chapter 8: a connectivity hub and one peered spoke.
#
# Always created (free): two resource groups, the hub VNet with its platform
# subnets, the spoke VNet, the spoke route table and the peering.
# Opt-in (billed per hour): Azure Firewall (deploy_firewall) and a VPN
# gateway (deploy_vpn_gateway).

locals {
  hub_name   = "${var.prefix}-hub-${var.location}"    # e.g. alz-hub-uksouth
  spoke_name = "${var.prefix}-spoke1-${var.location}" # e.g. alz-spoke1-uksouth

  # Basic needs a management NIC, so it needs AzureFirewallManagementSubnet.
  # Standard and Premium only need it for forced tunnelling.
  firewall_management_subnet_needed = var.firewall_sku_tier == "Basic"

  # Basic supports threat intelligence in alert mode only.
  threat_intel_mode = var.firewall_sku_tier == "Basic" ? "Alert" : "Deny"

  # Every spoke range: this spoke plus the others. The example firewall rule
  # allows traffic between any of them on var.spoke_to_spoke_ports.
  all_spoke_prefixes = concat([var.spoke_address_space], var.other_spoke_address_prefixes)
}

# ---------- Resource groups ----------

module "hub_resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.4.0"

  name             = "rg-${local.hub_name}"
  location         = var.location
  tags             = var.tags
  enable_telemetry = var.enable_telemetry
}

module "spoke_resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.4.0"

  name             = "rg-${local.spoke_name}"
  location         = var.location
  tags             = var.tags
  enable_telemetry = var.enable_telemetry
}

# ---------- 1. Hub virtual network and its platform subnets ----------
# The special subnet names (AzureFirewallSubnet, GatewaySubnet, ...) are fixed
# by Azure. They are created even when the service that uses them is off, so
# the address plan is settled once and turning a service on later doesn't
# reshape the VNet.

module "hub_vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.22.2"

  name             = "vnet-${local.hub_name}"
  location         = var.location
  parent_id        = module.hub_resource_group.resource_id
  address_space    = [var.hub_address_space]
  tags             = var.tags
  enable_telemetry = var.enable_telemetry

  subnets = merge(
    {
      firewall = {
        name           = "AzureFirewallSubnet"
        address_prefix = var.hub_subnet_prefixes.firewall
      }
      gateway = {
        name           = "GatewaySubnet"
        address_prefix = var.hub_subnet_prefixes.gateway
      }
      bastion = {
        name           = "AzureBastionSubnet"
        address_prefix = var.hub_subnet_prefixes.bastion
      }
      # Reserved for chapter 9's DNS Private Resolver: one subnet per
      # endpoint, each delegated to Microsoft.Network/dnsResolvers.
      dns_inbound = {
        name           = "snet-dns-inbound"
        address_prefix = var.hub_subnet_prefixes.dns_inbound
        delegations = [{
          name               = "Microsoft.Network.dnsResolvers"
          service_delegation = { name = "Microsoft.Network/dnsResolvers" }
        }]
      }
      dns_outbound = {
        name           = "snet-dns-outbound"
        address_prefix = var.hub_subnet_prefixes.dns_outbound
        delegations = [{
          name               = "Microsoft.Network.dnsResolvers"
          service_delegation = { name = "Microsoft.Network/dnsResolvers" }
        }]
      }
    },
    local.firewall_management_subnet_needed ? {
      firewall_management = {
        name           = "AzureFirewallManagementSubnet"
        address_prefix = var.hub_subnet_prefixes.firewall_management
      }
    } : {}
  )
}

# ---------- 2. Azure Firewall (opt-in) ----------

module "firewall_policy" {
  source  = "Azure/avm-res-network-firewallpolicy/azurerm"
  version = "0.3.4"
  count   = var.deploy_firewall ? 1 : 0

  name                                     = "afwp-${local.hub_name}"
  location                                 = var.location
  resource_group_name                      = module.hub_resource_group.name
  firewall_policy_sku                      = var.firewall_sku_tier # must match the firewall's tier
  firewall_policy_threat_intelligence_mode = local.threat_intel_mode
  tags                                     = var.tags
  enable_telemetry                         = var.enable_telemetry
}

# One rule collection group with one network rule collection: allow TCP on the
# chosen ports between spoke ranges. Everything else is denied by default.
module "firewall_rules" {
  source  = "Azure/avm-res-network-firewallpolicy/azurerm//modules/rule_collection_groups"
  version = "0.3.4"
  count   = var.deploy_firewall ? 1 : 0

  firewall_policy_rule_collection_group_firewall_policy_id = module.firewall_policy[0].resource_id
  firewall_policy_rule_collection_group_name               = "rcg-spoke-to-spoke"
  firewall_policy_rule_collection_group_priority           = 200

  firewall_policy_rule_collection_group_network_rule_collection = [{
    name     = "allow-spoke-to-spoke"
    priority = 100
    action   = "Allow"
    rule = [{
      name                  = "spoke-to-spoke-tcp"
      protocols             = ["TCP"]
      source_addresses      = local.all_spoke_prefixes
      destination_addresses = local.all_spoke_prefixes
      destination_ports     = var.spoke_to_spoke_ports
    }]
  }]
}

module "firewall_public_ip" {
  source  = "Azure/avm-res-network-publicipaddress/azurerm"
  version = "0.2.1"
  count   = var.deploy_firewall ? 1 : 0

  name                = "pip-${local.hub_name}-afw"
  location            = var.location
  resource_group_name = module.hub_resource_group.name
  sku                 = "Standard"
  allocation_method   = "Static"
  zones               = var.availability_zones
  tags                = var.tags
  enable_telemetry    = var.enable_telemetry
}

module "firewall_management_public_ip" {
  source  = "Azure/avm-res-network-publicipaddress/azurerm"
  version = "0.2.1"
  count   = var.deploy_firewall && local.firewall_management_subnet_needed ? 1 : 0

  name                = "pip-${local.hub_name}-afw-mgmt"
  location            = var.location
  resource_group_name = module.hub_resource_group.name
  sku                 = "Standard"
  allocation_method   = "Static"
  zones               = var.availability_zones
  tags                = var.tags
  enable_telemetry    = var.enable_telemetry
}

module "firewall" {
  source  = "Azure/avm-res-network-azurefirewall/azurerm"
  version = "0.4.0"
  count   = var.deploy_firewall ? 1 : 0

  name                = "afw-${local.hub_name}"
  location            = var.location
  resource_group_name = module.hub_resource_group.name
  firewall_sku_name   = "AZFW_VNet"
  firewall_sku_tier   = var.firewall_sku_tier
  firewall_policy_id  = module.firewall_policy[0].resource_id
  firewall_zones      = [for z in var.availability_zones : tostring(z)]
  tags                = var.tags
  enable_telemetry    = var.enable_telemetry

  ip_configurations = {
    default = {
      name                 = "ipconfig-default"
      public_ip_address_id = module.firewall_public_ip[0].resource_id
      subnet_id            = module.hub_vnet.subnets["firewall"].resource_id
    }
  }

  firewall_management_ip_configuration = local.firewall_management_subnet_needed ? {
    name                 = "ipconfig-management"
    public_ip_address_id = module.firewall_management_public_ip[0].resource_id
    subnet_id            = module.hub_vnet.subnets["firewall_management"].resource_id
  } : null

  # The rule collection group is a child of the policy; create it before the
  # firewall starts using the policy and remove the firewall first on destroy.
  depends_on = [module.firewall_rules]
}

locals {
  firewall_private_ip = var.deploy_firewall ? module.firewall[0].resource.ip_configuration[0].private_ip_address : null
}

# ---------- 3. VPN gateway (opt-in, 45+ minutes to create) ----------

module "vpn_gateway" {
  source  = "Azure/avm-ptn-vnetgateway/azurerm"
  version = "0.10.3"
  count   = var.deploy_vpn_gateway ? 1 : 0

  name                              = "vgw-${local.hub_name}"
  location                          = var.location
  parent_id                         = module.hub_resource_group.resource_id
  type                              = "Vpn"
  sku                               = var.vpn_gateway_sku
  vpn_type                          = "RouteBased"
  vpn_generation                    = var.vpn_gateway_sku == "VpnGw1AZ" ? "Generation1" : "Generation2"
  vpn_active_active_enabled         = false # one public IP; active-active needs two
  vpn_bgp_enabled                   = false
  subnet_creation_enabled           = false # GatewaySubnet already exists in the hub VNet
  virtual_network_gateway_subnet_id = module.hub_vnet.subnets["gateway"].resource_id
  tags                              = var.tags
  enable_telemetry                  = var.enable_telemetry

  ip_configurations = {
    default = {
      name = "ipconfig-default"
      public_ip = {
        name  = "pip-${local.hub_name}-vgw"
        zones = var.availability_zones
      }
    }
  }
}

# ---------- 4. Spoke: route table, VNet, peering ----------

# The route table always exists (free). Its routes only exist when the
# firewall does: 0.0.0.0/0 and every other spoke range go to the firewall's
# private IP. Without them, spoke traffic uses Azure's system routes.
module "spoke_route_table" {
  source  = "Azure/avm-res-network-routetable/azurerm"
  version = "0.5.0"

  name                = "rt-${local.spoke_name}"
  location            = var.location
  resource_group_name = module.spoke_resource_group.name
  tags                = var.tags
  enable_telemetry    = var.enable_telemetry

  # Gateway route propagation stays on: with a VPN gateway, on-premises
  # prefixes reach the spoke directly through the gateway (more specific than
  # 0.0.0.0/0). To inspect hybrid traffic as well, turn propagation off here
  # AND add a GatewaySubnet route table pointing the spoke ranges at the
  # firewall (see the README).
  bgp_route_propagation_enabled = true

  routes = var.deploy_firewall ? merge(
    {
      default = {
        name                   = "udr-default-to-firewall"
        address_prefix         = "0.0.0.0/0"
        next_hop_type          = "VirtualAppliance"
        next_hop_in_ip_address = local.firewall_private_ip
      }
    },
    {
      for i, prefix in var.other_spoke_address_prefixes : "spoke-${i}" => {
        name                   = "udr-spoke-${replace(replace(prefix, ".", "-"), "/", "_")}-to-firewall"
        address_prefix         = prefix
        next_hop_type          = "VirtualAppliance"
        next_hop_in_ip_address = local.firewall_private_ip
      }
    }
  ) : {}
}

module "spoke_vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.22.2"

  name             = "vnet-${local.spoke_name}"
  location         = var.location
  parent_id        = module.spoke_resource_group.resource_id
  address_space    = [var.spoke_address_space]
  tags             = var.tags
  enable_telemetry = var.enable_telemetry

  subnets = {
    workload = {
      name           = "snet-workload"
      address_prefix = var.spoke_subnet_prefix
      route_table    = { id = module.spoke_route_table.resource_id }
    }
  }
}

# Peering is two resources, one on each VNet. The spoke side may use the hub's
# gateway only when one exists, and the hub side offers gateway transit only
# then. Both sides allow forwarded traffic, so packets the firewall forwards
# between spokes are accepted.
module "spoke_to_hub_peering" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm//modules/peering"
  version = "0.22.2"

  name                      = "peer-${local.spoke_name}-to-${local.hub_name}"
  parent_id                 = module.spoke_vnet.resource_id
  remote_virtual_network_id = module.hub_vnet.resource_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  use_remote_gateways          = var.deploy_vpn_gateway

  create_reverse_peering               = true
  reverse_name                         = "peer-${local.hub_name}-to-${local.spoke_name}"
  reverse_allow_virtual_network_access = true
  reverse_allow_forwarded_traffic      = true
  reverse_allow_gateway_transit        = var.deploy_vpn_gateway

  # use_remote_gateways fails unless the gateway already exists.
  depends_on = [module.vpn_gateway]
}
