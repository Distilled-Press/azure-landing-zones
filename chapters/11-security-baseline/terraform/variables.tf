variable "subscription_id" {
  type        = string
  description = "Subscription to apply the security baseline to (for example the security or management subscription, or a test subscription). Lower-case GUID."

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a lower-case subscription GUID."
  }
}

variable "prefix" {
  type        = string
  default     = "alz"
  description = "Prefix used in resource names."
}

variable "location" {
  type        = string
  default     = "uksouth"
  description = "Region for the Sentinel resource group and Log Analytics workspace."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for the resource group and workspace."
}

# ---------- Defender for Cloud: email notifications ----------

variable "security_contact_emails" {
  type        = list(string)
  description = "Email addresses that receive Defender for Cloud alert and attack path notifications."

  validation {
    condition     = length(var.security_contact_emails) > 0 && alltrue([for e in var.security_contact_emails : can(regex("^[^@\\s;]+@[^@\\s;]+$", e))])
    error_message = "Give at least one email address, without semicolons."
  }
}

variable "security_contact_phone" {
  type        = string
  default     = ""
  description = "Optional phone number recorded on the security contact."
}

variable "notify_roles" {
  type        = list(string)
  default     = ["Owner"]
  description = "Subscription roles that also get the emails: any of AccountAdmin, ServiceAdmin, Owner, Contributor. [] turns role notifications off."

  validation {
    condition     = alltrue([for r in var.notify_roles : contains(["AccountAdmin", "ServiceAdmin", "Owner", "Contributor"], r)])
    error_message = "notify_roles can contain AccountAdmin, ServiceAdmin, Owner and Contributor."
  }
}

variable "alert_minimal_severity" {
  type        = string
  default     = "Medium"
  description = "Lowest security alert severity that sends an email: High, Medium or Low."

  validation {
    condition     = contains(["High", "Medium", "Low"], var.alert_minimal_severity)
    error_message = "alert_minimal_severity must be High, Medium or Low."
  }
}

variable "attack_path_minimal_risk_level" {
  type        = string
  default     = "Critical"
  description = "Lowest attack path risk level that sends an email: Critical, High, Medium or Low. Attack paths come from the paid Defender CSPM plan."

  validation {
    condition     = contains(["Critical", "High", "Medium", "Low"], var.attack_path_minimal_risk_level)
    error_message = "attack_path_minimal_risk_level must be Critical, High, Medium or Low."
  }
}

# ---------- Defender for Cloud: paid plans (opt-in) ----------

variable "defender_plans" {
  type = map(object({
    subplan    = optional(string)
    extensions = optional(map(map(string)), {})
  }))
  default     = {}
  description = <<DESCRIPTION
PAID Defender plans to turn on (tier Standard) for the WHOLE subscription. Default {}: none, so only the free foundational CSPM applies.
Key = plan name (Microsoft.Security/pricings name). Examples:
  VirtualMachines  = { subplan = "P1" }                      # Defender for Servers Plan 1
  StorageAccounts  = { subplan = "DefenderForStorageV2" }    # Defender for Storage
  KeyVaults        = {}                                      # Defender for Key Vault
  CloudPosture     = {}                                      # Defender CSPM
extensions = { <extension name> = { <additional property> = "<value>" } }; an extension not listed is not enabled.
Costs: https://azure.microsoft.com/pricing/details/defender-for-cloud/
terraform destroy (or removing a key) sets that plan back to Free.
DESCRIPTION

  validation {
    condition = alltrue([for k in keys(var.defender_plans) : contains([
      "AI", "Api", "AppServices", "Arm", "CloudPosture", "Containers", "CosmosDbs", "KeyVaults",
      "OpenSourceRelationalDatabases", "SqlServers", "SqlServerVirtualMachines", "StorageAccounts", "VirtualMachines",
    ], k)])
    error_message = "Unknown Defender plan name. See the README for the list."
  }
}

# ---------- Microsoft Sentinel (opt-in) ----------

variable "deploy_sentinel" {
  type        = bool
  default     = false
  description = "Create a resource group and Log Analytics workspace and onboard Microsoft Sentinel to it. BILLABLE: see the README."
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "Workspace retention in days (30-730)."

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}

variable "connect_azure_activity" {
  type        = bool
  default     = true
  description = "With deploy_sentinel: send this subscription's Activity log to the workspace (what the Azure Activity data connector uses). The AzureActivity table is free."
}
