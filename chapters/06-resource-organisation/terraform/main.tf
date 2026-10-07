# Tenant ID = ID of the tenant root group, the default parent.
data "azapi_client_config" "current" {}

locals {
  parent_management_group_id = coalesce(var.parent_management_group_id, data.azapi_client_config.current.tenant_id)

  # The architecture definition in ./lib names the management groups.
  architecture_file = jsondecode(file("${path.module}/lib/architecture_definitions/alz_custom.alz_architecture_definition.json"))
  architecture_root = one([for mg in local.architecture_file.management_groups : mg.id if mg.parent_id == null])

  # The library expects each default value as JSON: { "value": ... }.
  policy_default_values = { for name, value in var.policy_default_values : name => jsonencode({ value = value }) }

  # Every policy assignment in the hierarchy, as management group => names.
  policy_assignment_names = {
    for mg in data.alz_architecture.inventory.management_groups : mg.id => keys(mg.policy_assignments)
  }

  # DoNotEnforce: switch every assignment to DoNotEnforce.
  # Default: keep the library's modes, except DDoS without a real plan.
  enforcement_overrides = var.policy_assignment_enforcement_mode == "DoNotEnforce" ? {
    for mg_id, names in local.policy_assignment_names : mg_id => {
      policy_assignments = { for name in names : name => { enforcement_mode = "DoNotEnforce" } }
    }
    } : {
    for mg_id, names in local.policy_assignment_names : mg_id => {
      policy_assignments = { "Enable-DDoS-VNET" = { enforcement_mode = "DoNotEnforce" } }
    } if contains(names, "Enable-DDoS-VNET") && !contains(keys(var.policy_default_values), "ddos_protection_plan_id")
  }
}

# A read-only pass over the same architecture to list its policy assignments,
# so the enforcement switch above covers whatever the library version contains.
data "alz_architecture" "inventory" {
  name                     = local.architecture_file.name
  root_management_group_id = local.parent_management_group_id
  location                 = var.location
  policy_default_values    = local.policy_default_values

  lifecycle {
    precondition {
      condition     = local.architecture_root == var.prefix
      error_message = "The architecture definition in lib/ uses the prefix '${local.architecture_root}' but var.prefix is '${var.prefix}'. Run the set-prefix helper (see README) or change var.prefix."
    }
  }
}

module "alz" {
  source  = "Azure/avm-ptn-alz/azurerm"
  version = "0.22.0"

  architecture_name            = local.architecture_file.name
  parent_resource_id           = local.parent_management_group_id
  location                     = var.location
  policy_default_values        = local.policy_default_values
  policy_assignments_to_modify = local.enforcement_overrides
  enable_telemetry             = var.enable_telemetry

  # No subscription_placement here: moving subscriptions into the hierarchy
  # is chapter 7 (subscription vending).
}
