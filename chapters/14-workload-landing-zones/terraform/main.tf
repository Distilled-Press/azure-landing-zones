# Chapter 14: a data workload landing zone in a spoke.
#
# Always created (free): the workload resource group, the spoke VNet with the
# two Databricks subnets (delegated, with an NSG) and a private endpoint
# subnet, and, if hub_peering_enabled, peering to the chapter 8 hub.
# Opt-in with deploy_databricks (billed): an Azure Databricks workspace
# (Premium, VNet injection, secure cluster connectivity), a NAT gateway for
# cluster egress, private endpoints with private DNS, an access connector and
# an ADLS Gen2 storage account as the lake.

locals {
  name = "${var.prefix}-${var.workload_name}-${var.location}" # e.g. alz-data-uksouth

  managed_resource_group_name = coalesce(var.databricks_managed_resource_group_name, "rg-${local.name}-dbw-managed")

  nat_gateway_deployed = var.deploy_databricks && var.nat_gateway_enabled
  private_endpoints    = var.deploy_databricks && var.private_endpoints_enabled

  # With a back-end (databricks_ui_api) private endpoint, cluster-to-control-plane
  # traffic goes over Private Link, so Databricks drops its AzureDatabricks
  # outbound NSG rule. Without one, it keeps all its rules.
  required_nsg_rules = local.private_endpoints ? "NoAzureDatabricksRules" : "AllRules"

  # Private DNS zones: use the ones passed in (chapter 9's central zones) or
  # create them here.
  dns_zone_names = {
    databricks = "privatelink.azuredatabricks.net"
    blob       = "privatelink.blob.core.windows.net"
    dfs        = "privatelink.dfs.core.windows.net"
  }
  dns_zones_to_create = local.private_endpoints ? {
    for k, zone in local.dns_zone_names : k => zone if lookup(var.private_dns_zone_ids, k, null) == null
  } : {}
  dns_zone_ids = {
    for k, zone in local.dns_zone_names : k => coalesce(
      lookup(var.private_dns_zone_ids, k, null),
      try(module.private_dns_zone[k].resource_id, null),
      "none"
    )
  }

  databricks_delegation = [{
    name               = "Microsoft.Databricks.workspaces"
    service_delegation = { name = "Microsoft.Databricks/workspaces" }
  }]
}

# ---------- Resource group ----------

module "resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.4.0"

  name             = "rg-${local.name}"
  location         = var.location
  tags             = var.tags
  enable_telemetry = var.enable_telemetry
}

# ---------- 1. Spoke network (free) ----------

# One NSG for both Databricks subnets (Databricks recommends one per
# workspace). It starts empty: when the workspace is created, Databricks adds
# its own rules through the subnet delegation, and the AVM module ignores
# changes to security rules, so Terraform never fights them.
module "nsg_databricks" {
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "0.6.0"

  name             = "nsg-${local.name}-dbw"
  location         = var.location
  parent_id        = module.resource_group.resource_id
  tags             = var.tags
  enable_telemetry = var.enable_telemetry
}

# Clusters need outbound access (the SCC relay, storage, libraries). New VNets
# have no default outbound access, so the NAT gateway is the egress path.
# StandardV2 is zone-redundant and needs StandardV2 public IPs.
module "nat_gateway" {
  source  = "Azure/avm-res-network-natgateway/azurerm"
  version = "0.3.2"
  count   = local.nat_gateway_deployed ? 1 : 0

  name             = "ng-${local.name}"
  location         = var.location
  parent_id        = module.resource_group.resource_id
  sku_name         = "StandardV2"
  tags             = var.tags
  enable_telemetry = var.enable_telemetry

  public_ips = {
    egress = { name = "pip-${local.name}-ng" }
  }
  public_ip_configuration = {
    egress = { sku = "StandardV2" }
  }
}

module "vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.22.2"

  name             = "vnet-${local.name}"
  location         = var.location
  parent_id        = module.resource_group.resource_id
  address_space    = [var.address_space]
  tags             = var.tags
  enable_telemetry = var.enable_telemetry

  subnets = {
    # Both Databricks subnets: delegated to Microsoft.Databricks/workspaces,
    # with the NSG attached, used by no other resource.
    host = {
      name                   = "snet-dbw-host"
      address_prefix         = var.subnet_prefixes.host
      delegations            = local.databricks_delegation
      network_security_group = { id = module.nsg_databricks.resource_id }
      nat_gateway            = local.nat_gateway_deployed ? { id = module.nat_gateway[0].resource_id } : null
    }
    container = {
      name                   = "snet-dbw-container"
      address_prefix         = var.subnet_prefixes.container
      delegations            = local.databricks_delegation
      network_security_group = { id = module.nsg_databricks.resource_id }
      nat_gateway            = local.nat_gateway_deployed ? { id = module.nat_gateway[0].resource_id } : null
    }
    private_endpoints = {
      name           = "snet-pe"
      address_prefix = var.subnet_prefixes.private_endpoints
    }
  }
}

# Peering to the chapter 8 hub, both directions (the hub side is created in
# the hub's subscription, so the deploying identity needs rights there too).
module "hub_peering" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm//modules/peering"
  version = "0.22.2"
  count   = var.hub_peering_enabled ? 1 : 0

  name                      = "peer-${local.name}-to-hub"
  parent_id                 = module.vnet.resource_id
  remote_virtual_network_id = var.hub_virtual_network_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true

  create_reverse_peering               = true
  reverse_name                         = "peer-hub-to-${local.name}"
  reverse_allow_virtual_network_access = true
  reverse_allow_forwarded_traffic      = true
}

# ---------- 2. Private DNS zones (with the private endpoints) ----------

module "private_dns_zone" {
  source   = "Azure/avm-res-network-privatednszone/azurerm"
  version  = "0.5.0"
  for_each = local.dns_zones_to_create

  domain_name      = each.value
  parent_id        = module.resource_group.resource_id
  tags             = var.tags
  enable_telemetry = var.enable_telemetry

  virtual_network_links = {
    spoke = {
      name               = "link-${local.name}"
      virtual_network_id = module.vnet.resource_id
    }
  }
}

# ---------- 3. Azure Databricks workspace (opt-in, billed) ----------

module "databricks" {
  source  = "Azure/avm-res-databricks-workspace/azurerm"
  version = "0.5.0"
  count   = var.deploy_databricks ? 1 : 0

  name                        = "dbw-${local.name}"
  location                    = var.location
  resource_group_name         = module.resource_group.name
  sku                         = "premium" # Private Link and VNet injection with SCC need Premium
  managed_resource_group_name = local.managed_resource_group_name
  tags                        = var.tags
  enable_telemetry            = var.enable_telemetry

  custom_parameters = {
    virtual_network_id  = module.vnet.resource_id
    public_subnet_name  = module.vnet.subnets["host"].name
    private_subnet_name = module.vnet.subnets["container"].name
    no_public_ip        = true # secure cluster connectivity: no public IPs on cluster nodes
    # The module insists on these two IDs to order the NSG association before
    # the workspace. With the AVM VNet module the NSG is a property of the
    # subnet, not a separate association resource, so the subnet IDs stand in.
    public_subnet_network_security_group_association_id  = module.vnet.subnets["host"].resource_id
    private_subnet_network_security_group_association_id = module.vnet.subnets["container"].resource_id
  }

  public_network_access_enabled         = var.workspace_public_network_access_enabled
  network_security_group_rules_required = local.required_nsg_rules

  private_endpoints = local.private_endpoints ? merge(
    {
      # Back-end (and front-end) Private Link: REST API and cluster relay.
      ui_api = {
        name                          = "pep-${local.name}-dbw-ui-api"
        subresource_name              = "databricks_ui_api"
        subnet_resource_id            = module.vnet.subnets["private_endpoints"].resource_id
        private_dns_zone_resource_ids = [local.dns_zone_ids.databricks]
      }
    },
    var.workspace_public_network_access_enabled ? {} : {
      # Browser SSO over Private Link. One per region and DNS zone; it serves
      # every workspace in the region that shares the zone.
      browser_auth = {
        name                          = "pep-${local.name}-dbw-auth"
        subresource_name              = "browser_authentication"
        subnet_resource_id            = module.vnet.subnets["private_endpoints"].resource_id
        private_dns_zone_resource_ids = [local.dns_zone_ids.databricks]
      }
    }
  ) : {}

  # The identity Unity Catalog uses to reach the lake (role assignment below).
  access_connector = {
    lake = {
      name     = "dbac-${local.name}"
      identity = { type = "SystemAssigned" }
    }
  }

  # The module reads the resource group with a data source. Waiting for it
  # (and for the subnets, DNS zones and NAT gateway) avoids a "not found" on
  # the first apply and puts the workspace after its network.
  depends_on = [module.resource_group, module.vnet, module.private_dns_zone]
}

# ---------- 4. ADLS Gen2 lake (opt-in with the same switch) ----------

resource "random_string" "lake" {
  count = var.deploy_databricks ? 1 : 0

  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

module "lake" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.10.0"
  count   = var.deploy_databricks ? 1 : 0

  name             = "st${var.prefix}lake${random_string.lake[0].result}"
  location         = var.location
  parent_id        = module.resource_group.resource_id
  account_kind     = "StorageV2"
  account_sku_name = "Standard_LRS"
  is_hns_enabled   = true # hierarchical namespace: ADLS Gen2

  # Private only, Entra ID only.
  public_network_access_enabled   = false
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  network_rules = {
    bypass         = ["AzureServices"]
    default_action = "Deny"
  }

  containers = {
    raw = { name = "raw" }
  }

  private_endpoints = var.private_endpoints_enabled ? {
    dfs = {
      name                          = "pep-${local.name}-lake-dfs"
      subresource_name              = "dfs"
      subnet_resource_id            = module.vnet.subnets["private_endpoints"].resource_id
      private_dns_zone_resource_ids = [local.dns_zone_ids.dfs]
    }
    blob = {
      name                          = "pep-${local.name}-lake-blob"
      subresource_name              = "blob"
      subnet_resource_id            = module.vnet.subnets["private_endpoints"].resource_id
      private_dns_zone_resource_ids = [local.dns_zone_ids.blob]
    }
  } : {}

  # Unity Catalog reaches the lake as the access connector's managed identity.
  role_assignments = {
    access_connector = {
      role_definition_id_or_name = "Storage Blob Data Contributor"
      principal_id               = module.databricks[0].databricks_access_connector_principal_ids["lake"]
      principal_type             = "ServicePrincipal"
    }
  }

  tags             = var.tags
  enable_telemetry = var.enable_telemetry
}
