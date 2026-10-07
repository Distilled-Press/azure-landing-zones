variable "subscription_id" {
  type        = string
  description = "ID of the connectivity subscription (the one holding chapter 8's hub). Lower-case GUID."

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a lower-case subscription GUID."
  }
}

variable "prefix" {
  type        = string
  default     = "alz"
  description = "Prefix used in the names this code creates."
}

variable "location" {
  type        = string
  default     = "uksouth"
  description = "Region for the resource groups, the DNS Private Resolver and the virtual hub. The resolver must be in the same region as the hub VNet."
}

variable "hub_virtual_network_id" {
  type        = string
  description = "Resource ID of chapter 8's hub virtual network (its hub_virtual_network_id output). The private DNS zones are linked to it, and the DNS Private Resolver uses its snet-dns-inbound and snet-dns-outbound subnets."

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+$", var.hub_virtual_network_id))
    error_message = "hub_virtual_network_id must be a virtual network resource ID."
  }
}

# ---------- (a) Central private DNS zones (free to create; billed per zone per month) ----------

variable "private_dns_zones" {
  type = map(string)
  default = {
    azure_storage_blob = "privatelink.blob.core.windows.net"
    azure_key_vault    = "privatelink.vaultcore.azure.net"
    azure_sql_server   = "privatelink.database.windows.net"
  }
  description = "Private Link private DNS zones to create, keyed by a short name. Zone names must be the ones Microsoft documents for each service (Azure Private Endpoint private DNS zone values)."
}

# ---------- (b) DNS Private Resolver (billed per hour: off by default) ----------

variable "deploy_dns_resolver" {
  type        = bool
  default     = false
  description = "Deploy the DNS Private Resolver (inbound and outbound endpoints) and a forwarding ruleset. Each endpoint is billed per hour, so this is off by default."
}

variable "dns_inbound_subnet_name" {
  type        = string
  default     = "snet-dns-inbound"
  description = "Name of the hub subnet (delegated to Microsoft.Network/dnsResolvers) for the inbound endpoint. Chapter 8 creates it."
}

variable "dns_outbound_subnet_name" {
  type        = string
  default     = "snet-dns-outbound"
  description = "Name of the hub subnet (delegated to Microsoft.Network/dnsResolvers) for the outbound endpoint. Chapter 8 creates it."
}

variable "dns_inbound_ip_address" {
  type        = string
  default     = "10.10.0.164"
  description = "Static IP of the inbound endpoint, inside the inbound subnet (chapter 8 default 10.10.0.160/28; Azure reserves the first four addresses). On-premises DNS servers forward to this address."
}

variable "onprem_domain_name" {
  type        = string
  default     = "corp.example.com."
  description = "On-premises DNS domain the example forwarding rule sends to on-premises DNS servers. Must end with a dot."

  validation {
    condition     = endswith(var.onprem_domain_name, ".")
    error_message = "onprem_domain_name must be a fully qualified name ending with a dot, e.g. corp.example.com."
  }
}

variable "onprem_dns_servers" {
  type        = list(string)
  default     = ["10.0.0.4"]
  description = "IP addresses of the on-premises DNS servers the example rule forwards to (port 53)."
}

# ---------- (c) Virtual WAN variant (billed per hour: off by default) ----------

variable "deploy_virtual_wan" {
  type        = bool
  default     = false
  description = "Deploy a Standard Virtual WAN with one virtual hub. The hub is billed per hour from creation, so this is off by default."
}

variable "virtual_hub_address_prefix" {
  type        = string
  default     = "10.20.0.0/22"
  description = "Address prefix of the virtual hub. /24 is the minimum, /23 is recommended and a hub with Azure Firewall needs /22. It can't be changed after creation and mustn't overlap other networks."
}

variable "deploy_secured_hub" {
  type        = bool
  default     = false
  description = "Deploy Azure Firewall in the virtual hub (a secured virtual hub). Billed per hour on top of the hub. Needs deploy_virtual_wan."
}

variable "virtual_hub_firewall_sku_tier" {
  type        = string
  default     = "Standard"
  description = "Tier of the secured hub's Azure Firewall and its policy: Basic, Standard or Premium."

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.virtual_hub_firewall_sku_tier)
    error_message = "virtual_hub_firewall_sku_tier must be Basic, Standard or Premium."
  }
}

variable "deploy_routing_intent" {
  type        = bool
  default     = false
  description = "Configure routing intent on the secured hub: internet and private traffic both go through its Azure Firewall. Needs deploy_secured_hub."

  validation {
    condition     = !var.deploy_routing_intent || var.deploy_secured_hub
    error_message = "deploy_routing_intent needs deploy_secured_hub = true (routing intent sends traffic to the hub's firewall)."
  }
}

# ---------- Common ----------

variable "availability_zones" {
  type        = list(number)
  default     = [1, 2, 3]
  description = "Availability zones for the secured hub's Azure Firewall. Set [] in a region without availability zones."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the resource groups and resources."
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = "AVM module usage telemetry. See https://aka.ms/avm/telemetryinfo."
}
