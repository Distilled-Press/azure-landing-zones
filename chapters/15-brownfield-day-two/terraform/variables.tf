variable "subscription_id" {
  type        = string
  description = "ID of the subscription that holds the brownfield resources (where import/create-unmanaged.sh created them). Lower-case GUID."
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a lower-case subscription GUID."
  }
}

variable "prefix" {
  type        = string
  default     = "alz"
  description = "Prefix the brownfield script used (its second argument)."
  nullable    = false
}

variable "location" {
  type        = string
  default     = "uksouth"
  description = "Region the brownfield script used (its third argument)."
  nullable    = false
}
