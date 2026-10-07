variable "subscription_id" {
  type        = string
  default     = null
  description = "Optional subscription ID for the azurerm provider to connect through. Null uses the Azure CLI's default subscription. Nothing is deployed into it."
}

variable "prefix" {
  type        = string
  default     = "alz"
  description = "Prefix added to custom role names so they are unique in the tenant."
}

# Management group IDs (names), matching chapter 6's hierarchy.
variable "intermediate_root_management_group_id" {
  type        = string
  default     = "alz"
  description = "ID of the intermediate root management group. Custom roles are defined here and are assignable at it and everything below it."
}

variable "platform_management_group_id" {
  type        = string
  default     = "alz-platform"
  description = "ID of the Platform management group."
}

variable "landing_zones_management_group_id" {
  type        = string
  default     = "alz-landingzones"
  description = "ID of the Landing zones management group (used for the optional PIM-eligible platform access)."
}

variable "workload_management_group_id" {
  type        = string
  default     = "alz-corp"
  description = "ID of the landing zone management group where the workload team gets Contributor."
}

# Microsoft Entra security groups. Object IDs, not display names.
variable "platform_team_group_object_id" {
  type        = string
  description = "Object ID of the Microsoft Entra group for the platform team (Owner at Platform)."
}

variable "workload_team_group_object_id" {
  type        = string
  description = "Object ID of the Microsoft Entra group for a workload team (Contributor at the workload landing zone management group)."
}

variable "security_ops_group_object_id" {
  type        = string
  description = "Object ID of the Microsoft Entra group for security operations (Security Reader at the intermediate root)."
}

variable "network_ops_group_object_id" {
  type        = string
  default     = null
  description = "Optional object ID of the Microsoft Entra group for network operations (custom Network Management role at the intermediate root). Null skips the assignment."
}

# PIM. Off by default: eligible assignments need Microsoft Entra ID P2 or
# Microsoft Entra ID Governance licences for every user who is eligible.
variable "enable_pim_eligible_assignments" {
  type        = bool
  default     = false
  description = "When true, the platform team's Owner at Platform becomes a PIM-eligible assignment instead of an active one, and the platform team gets eligible Contributor at Landing zones. Needs Microsoft Entra ID P2 or ID Governance."
}

variable "pim_eligibility_duration_days" {
  type        = number
  default     = 365
  description = "How long the eligible assignments last, in days. Must be within the maximum the PIM role settings allow at the scope."

  validation {
    condition     = var.pim_eligibility_duration_days >= 1
    error_message = "pim_eligibility_duration_days must be at least 1."
  }
}
