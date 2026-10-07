variable "prefix" {
  type        = string
  default     = "alz"
  description = <<DESCRIPTION
Prefix for the management group IDs. The intermediate root is `<prefix>` and
the others are `<prefix>-platform`, `<prefix>-corp` and so on. The IDs live in
lib/architecture_definitions/alz_custom.alz_architecture_definition.json, so
to change the prefix run the set-prefix helper first (see README); a check
stops the plan if the file and this variable disagree.
DESCRIPTION
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_.()]{0,39}$", var.prefix))
    error_message = "Use 1-40 characters: letters, numbers, hyphens, underscores, periods and parentheses, starting with a letter or number."
  }
}

variable "parent_management_group_id" {
  type        = string
  default     = null
  description = <<DESCRIPTION
ID (name, not resource ID) of the management group the intermediate root is
created under. Leave null to use the tenant root group (its ID is the tenant ID).
DESCRIPTION

  validation {
    condition     = var.parent_management_group_id == null ? true : !strcontains(var.parent_management_group_id, "/")
    error_message = "Give the management group ID only, not /providers/Microsoft.Management/managementGroups/..."
  }
}

variable "location" {
  type        = string
  default     = "uksouth"
  description = "Region for the policy assignments' managed identities (the hierarchy itself has no region)."
  nullable    = false
}

variable "policy_assignment_enforcement_mode" {
  type        = string
  default     = "DoNotEnforce"
  description = <<DESCRIPTION
`DoNotEnforce` (default) sets every ALZ policy assignment to DoNotEnforce:
compliance is evaluated and reported, but nothing is denied and no
deployIfNotExists/modify deployment runs on create or update. Use this for a
test deployment.

`Default` keeps the enforcement mode the ALZ library ships with (most
assignments enforce; the Enforce-GR-* guardrails and a few others ship as
DoNotEnforce). Only choose it once policy_default_values points at real
platform resources. Enable-DDoS-VNET stays DoNotEnforce unless you supply
ddos_protection_plan_id, as the library advises.
DESCRIPTION
  nullable    = false

  validation {
    condition     = contains(["DoNotEnforce", "Default"], var.policy_assignment_enforcement_mode)
    error_message = "Must be DoNotEnforce or Default."
  }
}

variable "policy_default_values" {
  type        = map(string)
  default     = {}
  description = <<DESCRIPTION
Values for the ALZ library's policy defaults, keyed by default name, for
example log_analytics_workspace_id, ddos_protection_plan_id,
ama_user_assigned_managed_identity_id, ama_vm_insights_data_collection_rule_id,
private_dns_zone_subscription_id or email_security_contact. Anything you leave
out keeps the library's placeholder (a resource ID in subscription
00000000-0000-0000-0000-000000000000), which needs no real resource; the module
skips the policy role assignments for placeholder scopes. Real resource IDs
must exist before you apply, because the module grants the policy identities
roles on them.
DESCRIPTION
  nullable    = false
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = "AVM module usage telemetry (see https://aka.ms/avm/telemetryinfo). Set false to opt out."
  nullable    = false
}
