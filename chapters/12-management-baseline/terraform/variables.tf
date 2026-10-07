variable "subscription_id" {
  type        = string
  description = "ID of the management subscription the resources are created in. Lower-case GUID."
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a lower-case subscription GUID."
  }
}

variable "prefix" {
  type        = string
  default     = "alz"
  description = "Prefix used in the names this code creates."
  nullable    = false
}

variable "location" {
  type        = string
  default     = "uksouth"
  description = "Region of the resource group, workspace, data collection rule and identity."
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  default     = null
  description = "Name of the management resource group. Default: rg-<prefix>-management-<location>."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for every resource created here."
  nullable    = false
}

# ---------- Log Analytics workspace ----------

variable "log_analytics_retention_in_days" {
  type        = number
  default     = 30
  description = "Interactive (analytics) retention for the workspace. 30-730 days; the first 31 days are included in the ingestion price."
  nullable    = false

  validation {
    condition     = var.log_analytics_retention_in_days >= 30 && var.log_analytics_retention_in_days <= 730
    error_message = "Use 30 to 730 days."
  }
}

variable "log_analytics_daily_quota_gb" {
  type        = number
  default     = null
  description = <<DESCRIPTION
Optional daily cap in GB. null (default) means no cap. When the cap is reached,
collection stops until the workspace's daily reset hour, so treat it as a
safety net for unexpected spikes, not a cost control.
DESCRIPTION

  validation {
    condition     = var.log_analytics_daily_quota_gb == null ? true : var.log_analytics_daily_quota_gb > 0
    error_message = "Use a positive number of GB, or null for no cap."
  }
}

# ---------- Action group and Service Health ----------

variable "action_group_email_addresses" {
  type        = list(string)
  default     = []
  description = <<DESCRIPTION
Email receivers for the platform action group. Each NEW address gets a
"Verify your email address" message with a one-time passcode that must be
entered within 30 minutes; until then it receives no alerts (see README).
DESCRIPTION
  nullable    = false

  validation {
    condition     = alltrue([for e in var.action_group_email_addresses : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "Every entry must be an email address."
  }
}

variable "action_group_short_name" {
  type        = string
  default     = null
  description = "Short name shown in SMS and email notifications (1-12 characters). Default: <prefix>-platform, cut to 12."

  validation {
    condition     = var.action_group_short_name == null ? true : length(var.action_group_short_name) >= 1 && length(var.action_group_short_name) <= 12
    error_message = "The short name must be 1-12 characters."
  }
}

variable "service_health_alert_enabled" {
  type        = bool
  default     = true
  description = "Create the Service Health activity log alert on the subscription, wired directly to the action group."
  nullable    = false
}

variable "service_health_event_types" {
  type        = list(string)
  default     = ["Incident", "Maintenance", "Informational", "ActionRequired", "Security"]
  description = "Service Health event types to alert on: Incident (service issues), Maintenance (planned maintenance), Informational and ActionRequired (health advisories), Security (security advisories)."
  nullable    = false

  validation {
    condition     = length(var.service_health_event_types) > 0 && alltrue([for t in var.service_health_event_types : contains(["Incident", "Maintenance", "Informational", "ActionRequired", "Security"], t)])
    error_message = "Use one or more of Incident, Maintenance, Informational, ActionRequired, Security."
  }
}

variable "service_health_regions" {
  type        = list(string)
  default     = []
  description = "Regions to alert on, as Service Health names them (for example \"UK South\", \"Global\"). Empty (default) means all regions."
  nullable    = false
}

# ---------- Azure Monitor Baseline Alerts (AMBA-ALZ), opt-in ----------

variable "deploy_amba" {
  type        = bool
  default     = false
  description = <<DESCRIPTION
Deploy the AMBA-ALZ policies (platform/amba library) to amba_management_group_id:
143 policy definitions, 16 initiatives and 15 initiative assignments, plus a
resource group and user-assigned identity for AMBA. Off by default.
DESCRIPTION
  nullable    = false
}

variable "amba_management_group_id" {
  type        = string
  default     = "alz"
  description = <<DESCRIPTION
ID (not resource ID) of the EXISTING management group AMBA is deployed to.
Every AMBA initiative is assigned there. The ID is also written in
lib/architecture_definitions/amba_single.alz_architecture_definition.json; run
the set-amba-scope helper to change it (see README). A check stops the plan if
the two disagree.
DESCRIPTION
  nullable    = false
}

variable "amba_enforcement_mode" {
  type        = string
  default     = "DoNotEnforce"
  description = <<DESCRIPTION
DoNotEnforce (default): AMBA initiatives report compliance but deploy nothing
on create or update. Default: they deploy alert rules, alert processing rules
and action groups into subscriptions under the management group.
DESCRIPTION
  nullable    = false

  validation {
    condition     = contains(["DoNotEnforce", "Default"], var.amba_enforcement_mode)
    error_message = "Must be DoNotEnforce or Default."
  }
}

variable "amba_use_platform_action_group" {
  type        = bool
  default     = true
  description = <<DESCRIPTION
true (default): AMBA uses this chapter's action group ("bring your own
notifications"), so its alerts reach receivers who have already verified their
addresses. false: AMBA's policies create their own action groups in each
subscription, emailing amba_action_group_email_addresses.
DESCRIPTION
  nullable    = false
}

variable "amba_action_group_email_addresses" {
  type        = list(string)
  default     = []
  description = "Only used when amba_use_platform_action_group = false: emails for the action groups AMBA's policies create. Each new address needs OTP verification."
  nullable    = false
}

variable "amba_resource_group_name" {
  type        = string
  default     = "rg-amba-monitoring-001"
  description = "Resource group for the AMBA identity in this subscription, and the name AMBA's policies use for the alert resource group they create in each subscription."
  nullable    = false
}

variable "amba_user_assigned_managed_identity_name" {
  type        = string
  default     = "id-amba-prod-001"
  description = "Name of the user-assigned identity AMBA's log search alerts run as (granted Monitoring Reader on the management group)."
  nullable    = false
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = "AVM module usage telemetry (https://aka.ms/avm/telemetryinfo). No cost."
  nullable    = false
}
