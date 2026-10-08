variable "subscription_id" {
  type        = string
  description = "ID of the workload landing zone subscription (for example one vended by chapter 7). Lower-case GUID."
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a lower-case subscription GUID."
  }
}

variable "prefix" {
  type        = string
  default     = "alz"
  description = "Prefix used in the names this code creates. Lower-case letters and digits (it is also part of the storage account name)."
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]{2,6}$", var.prefix))
    error_message = "prefix must be 2-6 lower-case letters or digits."
  }
}

variable "workload_name" {
  type        = string
  default     = "data"
  description = "Short workload name used in resource names, e.g. rg-<prefix>-<workload_name>-<location>."
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.workload_name))
    error_message = "workload_name must be 2-10 lower-case letters or digits."
  }
}

variable "location" {
  type        = string
  default     = "uksouth"
  description = "Region for the workload. The Databricks workspace and its VNet must be in the same region and subscription."
  nullable    = false
}

# ---------- Network (free) ----------

variable "address_space" {
  type        = string
  default     = "10.12.0.0/22"
  description = "Address space of the workload spoke VNet. Databricks VNet injection needs a VNet between /16 and /24."
  nullable    = false
}

variable "subnet_prefixes" {
  type = object({
    host              = optional(string, "10.12.0.0/24")
    container         = optional(string, "10.12.1.0/24")
    private_endpoints = optional(string, "10.12.2.0/27")
  })
  default     = {}
  description = <<DESCRIPTION
Subnet prefixes inside address_space:
- `host`: Databricks host ("public") subnet. /26 or larger; can't be changed after the workspace exists.
- `container`: Databricks container ("private") subnet. Same size as host is recommended.
- `private_endpoints`: subnet for the workspace and storage private endpoints.
Each cluster node takes one address in host and one in container, so a /24 pair gives about 250 nodes.
DESCRIPTION
  nullable    = false
}

variable "hub_peering_enabled" {
  type        = bool
  default     = false
  description = "Peer the workload spoke to the chapter 8 hub (both directions). Off by default."
  nullable    = false
}

variable "hub_virtual_network_id" {
  type        = string
  default     = null
  description = "Resource ID of the hub VNet (chapter 8 output hub_virtual_network_id). Required when hub_peering_enabled = true."

  validation {
    condition     = !var.hub_peering_enabled || can(regex("/providers/Microsoft.Network/virtualNetworks/", var.hub_virtual_network_id))
    error_message = "hub_peering_enabled = true needs hub_virtual_network_id set to a virtual network resource ID."
  }
}

# ---------- Databricks and the lake (billed: off by default) ----------

variable "deploy_databricks" {
  type        = bool
  default     = false
  description = "Deploy the Azure Databricks workspace (Premium, VNet injection, no public IP), the NAT gateway, the private endpoints and DNS, the access connector and the ADLS Gen2 lake. Billed (see the README), so off by default."
  nullable    = false
}

variable "nat_gateway_enabled" {
  type        = bool
  default     = true
  description = "With deploy_databricks: a StandardV2 NAT gateway on both Databricks subnets. Clusters in a VNet created after 31 March 2026 have no default outbound access and need an explicit egress path; set false only if you route egress through a hub firewall instead."
  nullable    = false
}

variable "private_endpoints_enabled" {
  type        = bool
  default     = true
  description = "With deploy_databricks: a databricks_ui_api private endpoint for the workspace (back-end Private Link, so required NSG rules become NoAzureDatabricksRules) and dfs/blob private endpoints for the lake."
  nullable    = false
}

variable "workspace_public_network_access_enabled" {
  type        = bool
  default     = true
  description = "Allow users to reach the workspace UI and API from the internet. false needs private_endpoints_enabled = true; this code then also adds a browser_authentication endpoint, and users need a network path and DNS to the spoke (VPN/ExpressRoute through the hub)."
  nullable    = false

  validation {
    condition     = var.workspace_public_network_access_enabled || var.private_endpoints_enabled
    error_message = "workspace_public_network_access_enabled = false needs private_endpoints_enabled = true, or nothing can reach the workspace."
  }
}

variable "private_dns_zone_ids" {
  type = object({
    databricks = optional(string)
    blob       = optional(string)
    dfs        = optional(string)
  })
  default     = {}
  description = <<DESCRIPTION
Existing private DNS zones to use instead of creating them here, for example chapter 9's central zones in the connectivity subscription:
- `databricks`: privatelink.azuredatabricks.net
- `blob`: privatelink.blob.core.windows.net
- `dfs`: privatelink.dfs.core.windows.net
A zone left null is created in the workload resource group and linked to the spoke VNet.
DESCRIPTION
  nullable    = false
}

variable "databricks_managed_resource_group_name" {
  type        = string
  default     = null
  description = "Name of the managed resource group Databricks creates and owns. Default: rg-<prefix>-<workload_name>-<location>-dbw-managed."
}

# ---------- Common ----------

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the resource group and resources."
  nullable    = false
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = "AVM module usage telemetry. See https://aka.ms/avm/telemetryinfo."
  nullable    = false
}
