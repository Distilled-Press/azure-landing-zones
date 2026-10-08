# Chapter 11: security baseline for one subscription.
#
#   Defender for Cloud
#     - security contact "default": emails for alerts and attack paths   (free)
#     - foundational CSPM: on by default, nothing to deploy                (free)
#     - paid plans from var.defender_plans                                 (default: none)
#   Microsoft Sentinel (deploy_sentinel = true only)
#     - rg-<prefix>-security-<region> / law-<prefix>-security-<region>    (billable)
#     - Sentinel onboarding on the workspace
#     - subscription Activity log -> workspace (Azure Activity connector)

locals {
  subscription_resource_id = "/subscriptions/${var.subscription_id}"
  sentinel_name            = "${var.prefix}-security-${var.location}"

  # Activity log categories, the diagnostic setting categories for a subscription.
  activity_log_categories = [
    "Administrative", "Security", "ServiceHealth", "Alert",
    "Recommendation", "Policy", "Autoscale", "ResourceHealth",
  ]
}

# ---------------------------------------------------------------------------
# Defender for Cloud: who gets told
# ---------------------------------------------------------------------------

# There is one security contact per subscription and its name must be
# "default". azapi uses the 2023-12-01-preview API, which adds attack path
# notifications; azurerm_security_center_contact still uses an older one.
resource "azapi_resource" "security_contact" {
  type      = "Microsoft.Security/securityContacts@2023-12-01-preview"
  name      = "default"
  parent_id = local.subscription_resource_id

  body = {
    properties = {
      isEnabled = true
      emails    = join(";", var.security_contact_emails)
      phone     = var.security_contact_phone
      notificationsByRole = {
        state = length(var.notify_roles) > 0 ? "On" : "Off"
        roles = var.notify_roles
      }
      # In the order the API returns them (AttackPath first); the other
      # order shows as a change on every plan.
      notificationsSources = [
        {
          sourceType       = "AttackPath"
          minimalRiskLevel = var.attack_path_minimal_risk_level
        },
        {
          sourceType      = "Alert"
          minimalSeverity = var.alert_minimal_severity
        },
      ]
    }
  }
}

# ---------------------------------------------------------------------------
# Defender for Cloud: paid plans, opt-in only
# ---------------------------------------------------------------------------

# Nothing is created for foundational CSPM: it's free and on for every
# subscription. Each entry here turns on a PAID plan for the WHOLE subscription.
# Deleting the resource (terraform destroy, or removing the key) sets the plan
# back to Free.
resource "azurerm_security_center_subscription_pricing" "plan" {
  for_each = var.defender_plans

  resource_type = each.key
  tier          = "Standard"
  subplan       = each.value.subplan

  dynamic "extension" {
    for_each = each.value.extensions
    content {
      name                            = extension.key
      additional_extension_properties = length(extension.value) > 0 ? extension.value : null
    }
  }
}

# ---------------------------------------------------------------------------
# Microsoft Sentinel, opt-in
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "security" {
  count = var.deploy_sentinel ? 1 : 0

  name     = "rg-${local.sentinel_name}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_log_analytics_workspace" "security" {
  count = var.deploy_sentinel ? 1 : 0

  name                = "law-${local.sentinel_name}"
  resource_group_name = azurerm_resource_group.security[0].name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

# Sentinel is "turned on" for a workspace by one onboarding-state resource.
resource "azurerm_sentinel_log_analytics_workspace_onboarding" "security" {
  count = var.deploy_sentinel ? 1 : 0

  workspace_id = azurerm_log_analytics_workspace.security[0].id
}

# The Azure Activity data connector now uses the diagnostic settings pipeline:
# a subscription diagnostic setting that sends the Activity log to the
# Sentinel workspace. Data lands in the AzureActivity table (free).
resource "azurerm_monitor_diagnostic_setting" "activity_to_sentinel" {
  count = var.deploy_sentinel && var.connect_azure_activity ? 1 : 0

  name                       = "activity-to-${local.sentinel_name}"
  target_resource_id         = local.subscription_resource_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.security[0].id

  dynamic "enabled_log" {
    for_each = local.activity_log_categories
    content {
      category = enabled_log.value
    }
  }

  depends_on = [azurerm_sentinel_log_analytics_workspace_onboarding.security]
}
