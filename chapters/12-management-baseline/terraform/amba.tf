# Azure Monitor Baseline Alerts for Azure Landing Zones (AMBA-ALZ), opt-in.
#
# The documented Terraform route: the AMBA policies come from the Azure landing
# zones library (platform/amba) through the ALZ provider and the AVM pattern
# module avm-ptn-alz; the AVM pattern module avm-ptn-monitoring-amba-alz creates
# the resource group and user-assigned identity AMBA's log search alerts use.
# Everything here has count = 0 unless deploy_amba = true.

data "azapi_client_config" "current" {}

locals {
  amba_architecture_file = jsondecode(file("${path.module}/lib/architecture_definitions/amba_single.alz_architecture_definition.json"))
  amba_architecture_root = one([for mg in local.amba_architecture_file.management_groups : mg.id if mg.parent_id == null])

  # Where AMBA sends notifications. The ID is built from names, not taken from
  # the resource, so the ALZ data source can read it at plan time on the first
  # run; the module's policy_assignments_dependencies waits for the resource.
  platform_action_group_id  = "/subscriptions/${var.subscription_id}/resourceGroups/${local.resource_group_name}/providers/Microsoft.Insights/actionGroups/ag-${var.prefix}-platform"
  amba_byo_action_group_ids = var.amba_use_platform_action_group ? [local.platform_action_group_id] : []
  amba_action_group_emails  = var.amba_use_platform_action_group ? [] : var.amba_action_group_email_addresses

  # The library expects each default value as JSON: { "value": ... }.
  amba_policy_default_values = {
    amba_alz_management_subscription_id            = jsonencode({ value = var.subscription_id })
    amba_alz_resource_group_location               = jsonencode({ value = var.location })
    amba_alz_resource_group_name                   = jsonencode({ value = var.amba_resource_group_name })
    amba_alz_resource_group_tags                   = jsonencode({ value = merge({ _deployed_by_amba = "true" }, var.tags) })
    amba_alz_user_assigned_managed_identity_name   = jsonencode({ value = var.amba_user_assigned_managed_identity_name })
    amba_alz_byo_user_assigned_managed_identity_id = jsonencode({ value = "" })
    amba_alz_disable_tag_name                      = jsonencode({ value = "MonitorDisable" })
    amba_alz_disable_tag_values                    = jsonencode({ value = ["true", "Test", "Dev", "Sandbox"] })
    amba_alz_action_group_email                    = jsonencode({ value = local.amba_action_group_emails })
    amba_alz_arm_role_id                           = jsonencode({ value = [] })
    amba_alz_webhook_service_uri                   = jsonencode({ value = [] })
    amba_alz_event_hub_resource_id                 = jsonencode({ value = [] })
    amba_alz_function_resource_id                  = jsonencode({ value = "" })
    amba_alz_function_trigger_url                  = jsonencode({ value = "" })
    amba_alz_logicapp_resource_id                  = jsonencode({ value = "" })
    amba_alz_logicapp_callback_url                 = jsonencode({ value = "" })
    amba_alz_byo_alert_processing_rule             = jsonencode({ value = "" })
    amba_alz_byo_action_group                      = jsonencode({ value = local.amba_byo_action_group_ids })
    amba_alz_sha_action_group_resources = jsonencode({
      value = {
        actionGroupEmail    = local.amba_action_group_emails
        logicappResourceId  = ""
        logicappCallbackUrl = ""
        eventHubResourceId  = []
        webhookServiceUri   = []
        functionResourceId  = ""
        functionTriggerUrl  = ""
      }
    })
  }

  # DoNotEnforce: switch every AMBA assignment to DoNotEnforce. Default: leave
  # the library's modes alone.
  amba_enforcement_overrides = var.deploy_amba && var.amba_enforcement_mode == "DoNotEnforce" ? {
    for mg in data.alz_architecture.amba[0].management_groups : mg.id => {
      policy_assignments = { for name in keys(mg.policy_assignments) : name => { enforcement_mode = "DoNotEnforce" } }
    }
  } : {}
}

# A read-only pass over the same architecture, to list the assignment names
# for the enforcement switch above.
data "alz_architecture" "amba" {
  count = var.deploy_amba ? 1 : 0

  name                     = local.amba_architecture_file.name
  root_management_group_id = data.azapi_client_config.current.tenant_id
  location                 = var.location
  policy_default_values    = local.amba_policy_default_values

  lifecycle {
    precondition {
      condition     = local.amba_architecture_root == var.amba_management_group_id
      error_message = "lib/architecture_definitions/amba_single.alz_architecture_definition.json targets '${local.amba_architecture_root}' but var.amba_management_group_id is '${var.amba_management_group_id}'. Run the set-amba-scope helper (see README) or change the variable."
    }
  }
}

# Resource group + user-assigned identity for AMBA, with Monitoring Reader on
# the management group.
module "amba_identity" {
  source  = "Azure/avm-ptn-monitoring-amba-alz/azurerm"
  version = "0.4.0"
  count   = var.deploy_amba ? 1 : 0

  location                            = var.location
  root_management_group_name          = var.amba_management_group_id
  resource_group_name                 = var.amba_resource_group_name
  user_assigned_managed_identity_name = var.amba_user_assigned_managed_identity_name
  tags                                = merge({ _deployed_by_amba = "true" }, var.tags)
  enable_telemetry                    = var.enable_telemetry
}

# The AMBA policy definitions, initiatives and assignments, from the library.
module "amba_policy" {
  source  = "Azure/avm-ptn-alz/azurerm"
  version = "0.22.0"
  count   = var.deploy_amba ? 1 : 0

  architecture_name            = local.amba_architecture_file.name
  parent_resource_id           = data.azapi_client_config.current.tenant_id # unused: the management group already exists
  location                     = var.location
  policy_default_values        = local.amba_policy_default_values
  policy_assignments_to_modify = local.amba_enforcement_overrides
  policy_assignments_dependencies = [
    module.amba_identity[0].user_assigned_managed_identity_resource_id,
    azurerm_monitor_action_group.platform.id,
  ]
  enable_telemetry = var.enable_telemetry

  retries = {
    policy_role_assignments = {
      error_message_regex = [
        "AuthorizationFailed",
        "ResourceNotFound",
        "RoleAssignmentNotFound",
        "context deadline exceeded",
      ]
    }
  }
}
