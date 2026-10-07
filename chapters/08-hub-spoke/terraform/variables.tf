variable "subscription_id" {
  type        = string
  description = "ID of the connectivity subscription the hub (and, in this example, the spoke) is deployed to. Lower-case GUID."

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
  description = "Region for the hub, the spoke and everything in them."
}

# ---------- Address plan ----------

variable "hub_address_space" {
  type        = string
  default     = "10.10.0.0/22"
  description = "Address space of the hub virtual network."
}

variable "hub_subnet_prefixes" {
  type = object({
    firewall            = optional(string, "10.10.0.0/26")
    firewall_management = optional(string, "10.10.0.64/26")
    gateway             = optional(string, "10.10.0.128/27")
    dns_inbound         = optional(string, "10.10.0.160/28")
    dns_outbound        = optional(string, "10.10.0.176/28")
    bastion             = optional(string, "10.10.1.0/26")
  })
  default     = {}
  description = <<DESCRIPTION
Address prefixes of the hub's platform subnets. All are created empty (subnets are free):
- `firewall`: AzureFirewallSubnet (/26 minimum).
- `firewall_management`: AzureFirewallManagementSubnet (/26 minimum). Only created when `firewall_sku_tier` is Basic, which needs it.
- `gateway`: GatewaySubnet (/27 or larger recommended).
- `dns_inbound`, `dns_outbound`: subnets delegated to Microsoft.Network/dnsResolvers for chapter 9's DNS Private Resolver (/28 minimum each).
- `bastion`: AzureBastionSubnet (/26 minimum), reserved for Azure Bastion; no Bastion host is deployed.
DESCRIPTION
}

variable "spoke_address_space" {
  type        = string
  default     = "10.11.0.0/24"
  description = "Address space of the example spoke virtual network."
}

variable "spoke_subnet_prefix" {
  type        = string
  default     = "10.11.0.0/26"
  description = "Address prefix of the spoke's workload subnet."
}

variable "other_spoke_address_prefixes" {
  type        = list(string)
  default     = ["10.100.0.0/16"]
  description = "Address ranges of the other spokes (for example the chapter 7 vended spokes, 10.100.x.x). The spoke route table sends them to the firewall, and the example firewall rule allows traffic between them and this spoke."
}

# ---------- Azure Firewall (billed per hour: off by default) ----------

variable "deploy_firewall" {
  type        = bool
  default     = false
  description = "Deploy Azure Firewall, its public IP addresses and the routes that send spoke traffic to it. Azure Firewall is billed for every hour it exists, so this is off by default."
}

variable "firewall_sku_tier" {
  type        = string
  default     = "Basic"
  description = "Azure Firewall and firewall policy tier: Basic, Standard or Premium. Basic needs AzureFirewallManagementSubnet and a second (management) public IP."

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.firewall_sku_tier)
    error_message = "firewall_sku_tier must be Basic, Standard or Premium."
  }
}

variable "spoke_to_spoke_ports" {
  type        = list(string)
  default     = ["22", "443", "3389"]
  description = "TCP destination ports the example network rule allows between spokes."
}

# ---------- VPN gateway (billed per hour, slow to create: off by default) ----------

variable "deploy_vpn_gateway" {
  type        = bool
  default     = false
  description = "Deploy a VPN gateway in GatewaySubnet and turn on gateway transit for the spoke. Billed per hour; creation can take 45 minutes or more."
}

variable "vpn_gateway_sku" {
  type        = string
  default     = "VpnGw1AZ"
  description = "VPN gateway SKU. New gateways must use an AZ SKU (non-AZ VpnGw1-5 can no longer be created)."

  validation {
    condition     = contains(["VpnGw1AZ", "VpnGw2AZ", "VpnGw3AZ", "VpnGw4AZ", "VpnGw5AZ"], var.vpn_gateway_sku)
    error_message = "vpn_gateway_sku must be one of VpnGw1AZ to VpnGw5AZ."
  }
}

# ---------- Common ----------

variable "availability_zones" {
  type        = list(number)
  default     = [1, 2, 3]
  description = "Availability zones for the firewall and the public IP addresses. Set [] in a region without availability zones."
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
