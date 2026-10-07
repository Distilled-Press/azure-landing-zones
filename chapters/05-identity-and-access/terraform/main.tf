locals {
  mg_prefix = "/providers/Microsoft.Management/managementGroups"

  intermediate_root_id = "${local.mg_prefix}/${var.intermediate_root_management_group_id}"
  platform_id          = "${local.mg_prefix}/${var.platform_management_group_id}"
  landing_zones_id     = "${local.mg_prefix}/${var.landing_zones_management_group_id}"
  workload_id          = "${local.mg_prefix}/${var.workload_management_group_id}"

  # Built-in role definition IDs are the same in every tenant.
  built_in_role_ids = {
    owner           = "8e3af657-a8ff-443c-a75c-2fe8c4bcb635"
    contributor     = "b24988ac-6180-42a0-ab88-20f7382dd24c"
    security_reader = "39bc4728-0917-49c7-9d2c-d95423bc2eb4"
  }

  # A role definition ID scoped to a management group.
  role_id = { for k, v in local.built_in_role_ids : k => "/providers/Microsoft.Authorization/roleDefinitions/${v}" }
}

# -----------------------------------------------------------------------------
# (a) Custom role definitions at the intermediate root
# Both follow the custom roles the Azure landing zone reference architecture
# ships (ALZ library: Application-Owners and Network-Management).
# -----------------------------------------------------------------------------

# Workload teams: Contributor-like, but they can't change RBAC, create public
# IPs, create or change virtual networks (the platform team owns IP space and
# connectivity), or purge deleted key vaults.
resource "azurerm_role_definition" "application_owner" {
  role_definition_id = uuidv5("url", "${local.intermediate_root_id}/application-owner")
  name               = "Landing Zone Application Owner (${var.prefix})"
  description        = "Contributor role for application and operations teams in a landing zone, without RBAC writes, public IPs, virtual network writes or key vault purge."
  scope              = local.intermediate_root_id
  assignable_scopes  = [local.intermediate_root_id]

  permissions {
    actions = ["*"]
    not_actions = [
      "Microsoft.Authorization/*/write",
      "Microsoft.Network/publicIPAddresses/write",
      "Microsoft.Network/virtualNetworks/write",
      "Microsoft.KeyVault/locations/deletedVaults/purge/action",
    ]
    data_actions     = []
    not_data_actions = []
  }
}

# Network operations: read everything, manage networking, run deployments and
# raise support tickets. Nothing outside Microsoft.Network.
resource "azurerm_role_definition" "network_management" {
  role_definition_id = uuidv5("url", "${local.intermediate_root_id}/network-management")
  name               = "Network Management (${var.prefix})"
  description        = "Platform-wide connectivity management: virtual networks, route tables, NSGs, NVAs, VPN, ExpressRoute and related resources."
  scope              = local.intermediate_root_id
  assignable_scopes  = [local.intermediate_root_id]

  permissions {
    actions = [
      "*/read",
      "Microsoft.Network/*",
      "Microsoft.Resources/deployments/*",
      "Microsoft.Support/*",
    ]
    not_actions      = []
    data_actions     = []
    not_data_actions = []
  }
}

# -----------------------------------------------------------------------------
# (b) Built-in and custom roles assigned to Microsoft Entra groups at
# management group scopes. Groups, not users: membership changes don't need a
# new role assignment.
# -----------------------------------------------------------------------------

# Platform team: Owner at Platform. Active only when PIM is off; with PIM on,
# the eligible assignment below replaces it.
resource "azurerm_role_assignment" "platform_team_owner" {
  count = var.enable_pim_eligible_assignments ? 0 : 1

  scope              = local.platform_id
  role_definition_id = "${local.platform_id}${local.role_id.owner}"
  principal_id       = var.platform_team_group_object_id
  principal_type     = "Group"
  description        = "Platform team manages the platform subscriptions."
}

# Workload team: Contributor at its landing zone management group.
resource "azurerm_role_assignment" "workload_team_contributor" {
  scope              = local.workload_id
  role_definition_id = "${local.workload_id}${local.role_id.contributor}"
  principal_id       = var.workload_team_group_object_id
  principal_type     = "Group"
  description        = "Workload team builds in the landing zones under this management group."
}

# Security operations: Security Reader across the whole estate.
resource "azurerm_role_assignment" "security_ops_reader" {
  scope              = local.intermediate_root_id
  role_definition_id = "${local.intermediate_root_id}${local.role_id.security_reader}"
  principal_id       = var.security_ops_group_object_id
  principal_type     = "Group"
  description        = "Security operations view security posture across the estate."
}

# Network operations: the custom Network Management role across the estate.
resource "azurerm_role_assignment" "network_ops" {
  count = var.network_ops_group_object_id == null ? 0 : 1

  scope              = local.intermediate_root_id
  role_definition_id = azurerm_role_definition.network_management.role_definition_resource_id
  principal_id       = var.network_ops_group_object_id
  principal_type     = "Group"
  description        = "Network operations manage connectivity across the estate."
}

# -----------------------------------------------------------------------------
# (c) Optional PIM-eligible assignments (Microsoft Entra ID P2 or ID Governance)
# Eligible means the group's members must activate the role (MFA,
# justification, approval, as the PIM role settings require) before they
# hold it, and it expires after the activation window.
# -----------------------------------------------------------------------------

resource "azurerm_pim_eligible_role_assignment" "platform_team_owner" {
  count = var.enable_pim_eligible_assignments ? 1 : 0

  scope              = local.platform_id
  role_definition_id = "${local.platform_id}${local.role_id.owner}"
  principal_id       = var.platform_team_group_object_id
  justification      = "Platform team: just-in-time Owner on the Platform management group."

  schedule {
    expiration {
      duration_days = var.pim_eligibility_duration_days
    }
  }
}

# Platform admins get no standing access to workload landing zones; they can
# activate Contributor there to troubleshoot.
resource "azurerm_pim_eligible_role_assignment" "platform_team_landing_zones_contributor" {
  count = var.enable_pim_eligible_assignments ? 1 : 0

  scope              = local.landing_zones_id
  role_definition_id = "${local.landing_zones_id}${local.role_id.contributor}"
  principal_id       = var.platform_team_group_object_id
  justification      = "Platform team: just-in-time Contributor on landing zones for troubleshooting."

  schedule {
    expiration {
      duration_days = var.pim_eligibility_duration_days
    }
  }
}
