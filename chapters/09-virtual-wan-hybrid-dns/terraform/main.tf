# Chapter 9: central private DNS, hybrid name resolution and a Virtual WAN
# variant, added to chapter 8's hub.
#
# Always created: a DNS resource group and the private DNS zones, linked to
# the hub VNet.
# Opt-in (billed per hour): the DNS Private Resolver with a forwarding
# ruleset (deploy_dns_resolver), and a Virtual WAN with one virtual hub
# (deploy_virtual_wan), optionally secured with Azure Firewall and routing
# intent (deploy_secured_hub, deploy_routing_intent).

locals {
  dns_name  = "${var.prefix}-dns-${var.location}"  # e.g. alz-dns-uksouth
  vwan_name = "${var.prefix}-vwan-${var.location}" # e.g. alz-vwan-uksouth

  # The secured hub needs a virtual hub to live in.
  deploy_secured_hub = var.deploy_virtual_wan && var.deploy_secured_hub
}

# ---------- Resource group for the DNS resources ----------

module "dns_resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.4.0"

  name             = "rg-${local.dns_name}"
  location         = var.location
  tags             = var.tags
  enable_telemetry = var.enable_telemetry
}

# ---------- (a) Central private DNS zones, linked to the hub ----------
# One zone per Private Link service, named exactly as Microsoft documents.
# Linking each zone to the hub VNet lets anything that resolves through the
# hub (the DNS Private Resolver's inbound endpoint, or VMs in the hub) get the
# private endpoint IPs. The ALZ pattern module also knows every documented
# zone; here it gets a short list.

module "private_dns_zones" {
  source  = "Azure/avm-ptn-network-private-link-private-dns-zones/azurerm"
  version = "0.23.2"

  location  = var.location
  parent_id = module.dns_resource_group.resource_id

  private_link_private_dns_zones = {
    for key, zone in var.private_dns_zones : key => { zone_name = zone }
  }

  virtual_network_link_default_virtual_networks = {
    hub = { virtual_network_resource_id = var.hub_virtual_network_id }
  }

  tags             = var.tags
  enable_telemetry = var.enable_telemetry
}

# ---------- (b) DNS Private Resolver (opt-in) ----------
# It goes in the hub VNet, in the two delegated subnets chapter 8 reserved:
# a resolver serves exactly one VNet, the hub is where the VPN/ExpressRoute
# gateway lands on-premises queries, and the hub is linked to the private DNS
# zones. Using pre-made subnets means this code never changes chapter 8's VNet.

module "dns_resolver" {
  source  = "Azure/avm-res-network-dnsresolver/azurerm"
  version = "0.8.0"
  count   = var.deploy_dns_resolver ? 1 : 0

  name                        = "dnspr-${local.dns_name}"
  location                    = var.location
  resource_group_name         = module.dns_resource_group.name
  virtual_network_resource_id = var.hub_virtual_network_id
  tags                        = var.tags
  enable_telemetry            = var.enable_telemetry

  # On-premises -> Azure: on-premises DNS servers conditionally forward the
  # privatelink zones to this static IP.
  inbound_endpoints = {
    inbound = {
      name                         = "in-${local.dns_name}"
      subnet_name                  = var.dns_inbound_subnet_name
      private_ip_allocation_method = "Static"
      private_ip_address           = var.dns_inbound_ip_address
    }
  }

  # Azure -> on-premises: queries for the on-premises domain leave through the
  # outbound endpoint to the on-premises DNS servers. The ruleset is linked to
  # the hub VNet; link spokes too if they use Azure-provided DNS.
  outbound_endpoints = {
    outbound = {
      name        = "out-${local.dns_name}"
      subnet_name = var.dns_outbound_subnet_name
      forwarding_ruleset = {
        default = {
          name                                        = "dnsfrs-${local.dns_name}"
          link_with_outbound_endpoint_virtual_network = true
          # The module names each rule after its map key (it ignores a
          # rule's name attribute), so the key is the rule name.
          rules = {
            "rule-${trimsuffix(replace(var.onprem_domain_name, ".", "-"), "-")}" = {
              domain_name              = var.onprem_domain_name
              destination_ip_addresses = { for ip in var.onprem_dns_servers : ip => "53" }
            }
          }
        }
      }
    }
  }
}

# ---------- (c) Virtual WAN variant (opt-in) ----------
# A Standard Virtual WAN with one virtual hub: the Microsoft-managed
# alternative to chapter 8's customer-managed hub VNet. The ALZ pattern module
# turns on DDoS protection, Bastion, gateways, a sidecar VNet, private DNS and
# a resolver by default; all are switched off so only the hub (and, if asked,
# its firewall and routing intent) is built.

module "vwan_resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.4.0"
  count   = var.deploy_virtual_wan ? 1 : 0

  name             = "rg-${local.vwan_name}"
  location         = var.location
  tags             = var.tags
  enable_telemetry = var.enable_telemetry
}

module "virtual_wan" {
  source  = "Azure/avm-ptn-alz-connectivity-virtual-wan/azurerm"
  version = "0.18.0"
  count   = var.deploy_virtual_wan ? 1 : 0

  tags             = var.tags
  enable_telemetry = var.enable_telemetry

  virtual_wan_settings = {
    enabled_resources = {
      ddos_protection_plan = false # DDoS Network Protection is billed monthly
    }
    virtual_wan = {
      name                = "vwan-${local.vwan_name}"
      location            = var.location
      resource_group_name = module.vwan_resource_group[0].name
      type                = "Standard" # Basic has no firewall, VNet-to-VNet or inter-hub transit
    }
  }

  virtual_hubs = {
    primary = {
      location          = var.location
      default_parent_id = module.vwan_resource_group[0].resource_id

      enabled_resources = {
        firewall                              = local.deploy_secured_hub
        firewall_policy                       = local.deploy_secured_hub
        bastion                               = false
        virtual_network_gateway_express_route = false
        virtual_network_gateway_vpn           = false
        private_dns_zones                     = false
        private_dns_resolver                  = false
        sidecar_virtual_network               = false
      }

      hub = {
        name           = "vhub-${local.vwan_name}"
        address_prefix = var.virtual_hub_address_prefix
      }

      firewall = {
        name     = "afw-${local.vwan_name}"
        sku_name = "AZFW_Hub"
        sku_tier = var.virtual_hub_firewall_sku_tier
        zones    = var.availability_zones
      }

      firewall_policy = {
        name                     = "afwp-${local.vwan_name}"
        sku                      = var.virtual_hub_firewall_sku_tier
        threat_intelligence_mode = var.virtual_hub_firewall_sku_tier == "Basic" ? "Alert" : "Deny"
      }

      # Routing intent: one policy per traffic type, both pointing at this
      # hub's firewall (the key "primary" is the hub key above).
      routing_intents = local.deploy_secured_hub && var.deploy_routing_intent ? {
        default = {
          name = "ri-${local.vwan_name}"
          routing_policies = [
            {
              name                  = "InternetTraffic"
              destinations          = ["Internet"]
              next_hop_firewall_key = "primary"
            },
            {
              name                  = "PrivateTraffic"
              destinations          = ["PrivateTraffic"]
              next_hop_firewall_key = "primary"
            }
          ]
        }
      } : {}
    }
  }
}
