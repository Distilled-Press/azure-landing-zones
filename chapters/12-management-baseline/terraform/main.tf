locals {
  resource_group_name     = coalesce(var.resource_group_name, "rg-${var.prefix}-management-${var.location}")
  action_group_short_name = coalesce(var.action_group_short_name, substr("${var.prefix}-platform", 0, 12))
}

# ---------- Resource group ----------

module "resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.4.0"

  name             = local.resource_group_name
  location         = var.location
  tags             = var.tags
  enable_telemetry = var.enable_telemetry
}

# ---------- Central Log Analytics workspace ----------

module "log_analytics" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "0.5.1"

  name                                      = "log-${var.prefix}-${var.location}"
  location                                  = var.location
  resource_group_name                       = module.resource_group.name
  log_analytics_workspace_sku               = "PerGB2018"
  log_analytics_workspace_retention_in_days = var.log_analytics_retention_in_days
  log_analytics_workspace_daily_quota_gb    = var.log_analytics_daily_quota_gb

  # The module's default is "false" for both, which closes the workspace to
  # public ingestion and query (only Azure Monitor Private Link Scope traffic).
  # Without a private link scope, agents couldn't send data and the portal
  # couldn't query it, so open both explicitly.
  log_analytics_workspace_internet_ingestion_enabled = "true"
  log_analytics_workspace_internet_query_enabled     = "true"

  tags             = var.tags
  enable_telemetry = var.enable_telemetry
}

# ---------- Data collection rule: VM insights ----------
# The DCR the ALZ "Deploy-VM-Monitoring" family of policies points the Azure
# Monitor Agent at (policy default value ama_vm_insights_data_collection_rule_id).
# Nothing is collected until a machine is associated with it.

module "dcr_vm_insights" {
  source  = "Azure/avm-res-insights-datacollectionrule/azurerm"
  version = "0.1.0"

  name        = "dcr-${var.prefix}-vminsights-${var.location}"
  location    = var.location
  parent_id   = module.resource_group.resource_id
  description = "VM insights performance counters (InsightsMetrics) for Windows and Linux machines."

  data_sources = {
    performance_counters = [
      {
        name                          = "VMInsightsPerfCounters"
        streams                       = ["Microsoft-InsightsMetrics"]
        sampling_frequency_in_seconds = 60
        counter_specifiers            = ["\\VmInsights\\DetailedMetrics"]
      }
    ]
  }

  destinations = {
    log_analytics = [
      {
        name                  = "VMInsightsPerf-Logs-Dest"
        workspace_resource_id = module.log_analytics.resource_id
      }
    ]
  }

  data_flows = [
    {
      streams      = ["Microsoft-InsightsMetrics"]
      destinations = ["VMInsightsPerf-Logs-Dest"]
    }
  ]

  tags             = var.tags
  enable_telemetry = var.enable_telemetry
}

# ---------- User-assigned identity for the Azure Monitor Agent policies ----------
# The ALZ AMA policies assign this identity to virtual machines so the agent
# authenticates without a system-assigned identity on each VM.

module "ama_identity" {
  source  = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version = "0.5.3"

  name                = "id-${var.prefix}-ama-${var.location}"
  location            = var.location
  resource_group_name = module.resource_group.name

  tags             = var.tags
  enable_telemetry = var.enable_telemetry
}

# ---------- Platform action group ----------
# Plain azurerm resource: the AVM Terraform action group module is still
# "proposed" in the AVM index and not on the registry.
# Location must be "global" for Service Health alerts to reach it.

resource "azurerm_monitor_action_group" "platform" {
  name                = "ag-${var.prefix}-platform"
  resource_group_name = module.resource_group.name
  location            = "global"
  short_name          = local.action_group_short_name
  tags                = var.tags

  dynamic "email_receiver" {
    for_each = { for i, address in var.action_group_email_addresses : "email-${i + 1}" => address }

    content {
      name                    = email_receiver.key
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

# ---------- Service Health alert ----------
# Wired straight to the action group: alert processing rules don't apply to
# Service Health alerts, so routing them through one would silently drop them.
# Plain azurerm resource for the same reason as the action group.

resource "azurerm_monitor_activity_log_alert" "service_health" {
  count = var.service_health_alert_enabled ? 1 : 0

  name                = "alert-${var.prefix}-servicehealth"
  resource_group_name = module.resource_group.name
  location            = "global"
  scopes              = ["/subscriptions/${var.subscription_id}"]
  description         = "Service Health events for this subscription, sent directly to ${azurerm_monitor_action_group.platform.name}."
  tags                = var.tags

  criteria {
    category = "ServiceHealth"

    service_health {
      events    = var.service_health_event_types
      locations = length(var.service_health_regions) > 0 ? var.service_health_regions : null
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.platform.id
  }
}
