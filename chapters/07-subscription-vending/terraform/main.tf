# Subscription vending: one request file in, one configured subscription out.

locals {
  # 1. Read the request. Everything workload-specific comes from this file.
  request = yamldecode(file("${path.root}/${var.request_file}"))

  location = try(local.request.location, "uksouth")
  name     = "${var.prefix}-${local.request.workload}-${local.request.environment}" # e.g. alz-payments-prod

  # The request's tags plus two the platform always sets.
  tags = merge(local.request.tags, {
    managedBy = "subscription-vending"
    requestId = local.name
  })

  # A role may be a built-in role name ("Contributor") or a role definition GUID.
  role_assignments = {
    for ra in local.request.role_assignments :
    "${ra.principal_id}-${replace(lower(ra.role), " ", "-")}" => {
      principal_id = ra.principal_id
      definition = can(regex("^[0-9a-fA-F-]{36}$", ra.role)) ? (
        "/providers/Microsoft.Authorization/roleDefinitions/${lower(ra.role)}"
      ) : ra.role
      principal_type = try(ra.principal_type, null)
    }
  }

  # Budget notifications: one per threshold, all to the request's email list.
  budget_notifications = {
    for t in local.request.budget.thresholds : "threshold-${t}" => {
      enabled        = true
      operator       = "GreaterThan"
      threshold      = t
      threshold_type = try(local.request.budget.threshold_type, "Actual")
      contact_emails = local.request.budget.contact_emails
    }
  }

  # One (empty) network security group per subnet. NSGs are free.
  subnets = { for s in local.request.network.subnets : s.name => s }
}

# Budgets must start on the first day of the current month. time_static
# records the creation time once, so later plans don't keep moving the date.
resource "time_static" "budget_start" {}

locals {
  budget_start = formatdate("YYYY-MM-01'T'00:00:00Z", time_static.budget_start.rfc3339)
  budget_end   = "${tonumber(formatdate("YYYY", time_static.budget_start.rfc3339)) + 10}-${formatdate("MM", time_static.budget_start.rfc3339)}-01T00:00:00Z"
}

module "sub_vending" {
  source  = "Azure/avm-ptn-alz-sub-vending/azure"
  version = "0.3.3"

  location         = local.location
  enable_telemetry = var.enable_telemetry

  # 2. New subscription (alias) or existing subscription.
  subscription_alias_enabled   = var.subscription_alias_enabled
  subscription_alias_name      = var.subscription_alias_enabled ? local.name : null
  subscription_display_name    = local.name
  subscription_billing_scope   = var.subscription_alias_enabled ? var.billing_scope : null
  subscription_workload        = var.subscription_alias_enabled ? local.request.subscription_workload_type : null
  subscription_id              = var.subscription_alias_enabled ? null : var.existing_subscription_id
  subscription_update_existing = !var.subscription_alias_enabled && var.existing_subscription_update
  subscription_tags            = local.tags

  # 3. Management group placement.
  subscription_management_group_association_enabled = true
  subscription_management_group_id                  = local.request.management_group_id

  # 4. Resource providers.
  subscription_register_resource_providers_enabled = var.register_resource_providers
  subscription_register_resource_providers_and_features = {
    for rp in try(local.request.resource_providers, []) : rp => []
  }

  # 5. Budget with email notifications from the request.
  budget_enabled = true
  budgets = {
    monthly = {
      name              = "budget-${local.name}"
      amount            = local.request.budget.amount
      time_grain        = "Monthly"
      time_period_start = local.budget_start
      time_period_end   = local.budget_end
      notifications     = local.budget_notifications
    }
  }

  # 6. Spoke network: resource group, NSGs and virtual network. No peering
  #    unless hub_peering_enabled is set (the hub is built in chapter 8).
  resource_group_creation_enabled = true
  resource_groups = {
    network = {
      name     = "rg-${local.name}-network-${local.location}"
      location = local.location
      tags     = local.tags
    }
  }

  network_security_group_enabled = true
  network_security_groups = {
    for k, s in local.subnets : k => {
      name               = "nsg-${local.name}-${s.name}"
      resource_group_key = "network"
      tags               = local.tags
    }
  }

  virtual_network_enabled = true
  virtual_networks = {
    spoke = {
      name               = "vnet-${local.name}-${local.location}"
      address_space      = local.request.network.address_space
      resource_group_key = "network"
      tags               = local.tags
      subnets = {
        for k, s in local.subnets : k => {
          name                   = s.name
          address_prefix         = s.address_prefix
          network_security_group = { key_reference = k }
        }
      }

      hub_peering_enabled     = var.hub_peering_enabled
      hub_network_resource_id = var.hub_peering_enabled ? var.hub_virtual_network_id : null
      hub_peering_options_tohub = {
        use_remote_gateways = var.hub_use_remote_gateways
      }
    }
  }

  # 7. Role assignments at subscription scope.
  role_assignment_enabled = true
  role_assignments        = local.role_assignments
}
