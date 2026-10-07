variable "prefix" {
  type        = string
  default     = "alz"
  description = "Prefix for every name this code creates. The test management group is <prefix>-policytest."

  validation {
    # Policy assignment and exemption names at management group scope are
    # limited to 24 characters; the longest name here is <prefix>-inherit-tag.
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,9}$", var.prefix))
    error_message = "prefix must be 1-10 characters: lower-case letters, digits and hyphens."
  }
}

variable "parent_management_group_id" {
  type        = string
  default     = null
  description = "ID (not resource ID) of the management group to create the test management group under, e.g. alz. null (default) = the tenant root group."
}

variable "location" {
  type        = string
  default     = "uksouth"
  description = "Region recorded for the Modify assignment's system-assigned managed identity. It doesn't limit what the policy acts on."
}

variable "enforcement_mode" {
  type        = string
  default     = "DoNotEnforce"
  description = "Enforcement mode of both assignments. DoNotEnforce (default): evaluate and report only; no deny, no modify on create or update. Default: enforce."

  validation {
    condition     = contains(["Default", "DoNotEnforce"], var.enforcement_mode)
    error_message = "enforcement_mode must be Default or DoNotEnforce."
  }
}

variable "required_tag_name" {
  type        = string
  default     = "costCentre"
  description = "Tag every resource group must carry (custom definition), and the tag resources inherit from their resource group (Modify assignment)."
}

variable "guardrail_effect" {
  type        = string
  default     = "Audit"
  description = "Effect for both policies in the guardrails initiative: Audit (default) or Deny. Deny only blocks anything when enforcement_mode is Default."

  validation {
    condition     = contains(["Audit", "Deny"], var.guardrail_effect)
    error_message = "guardrail_effect must be Audit or Deny."
  }
}

variable "allowed_locations" {
  type        = list(string)
  default     = ["uksouth", "ukwest"]
  description = "Regions resources may be created in (Allowed locations built-in policy). Resources in the 'global' region are always allowed by that policy."
}

variable "exemption_expires_on" {
  type        = string
  default     = null
  description = "When the allowed-locations waiver stops applying, in UTC ISO 8601 (e.g. 2026-12-31T23:59:59Z). null (default) = 30 days after the first apply."

  validation {
    condition     = var.exemption_expires_on == null || can(formatdate("YYYY", var.exemption_expires_on))
    error_message = "exemption_expires_on must be an RFC 3339 timestamp such as 2026-12-31T23:59:59Z."
  }
}

variable "create_remediation_task" {
  type        = bool
  default     = false
  description = "Create a remediation task for the Modify assignment. Off by default: Learn advises creating management group remediation tasks after compliance has been evaluated, and Azure deletes remediation tasks 60 days after their last change. See the README for the CLI command."
}
