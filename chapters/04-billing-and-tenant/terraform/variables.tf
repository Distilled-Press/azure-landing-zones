variable "billing_scope_id" {
  type        = string
  description = <<DESCRIPTION
Full resource ID of the billing scope the subscription is billed to.
Microsoft Customer Agreement: the invoice section ID, in the form
/providers/Microsoft.Billing/billingAccounts/<account>/billingProfiles/<profile>/invoiceSections/<section>.
Enterprise Agreement: /providers/Microsoft.Billing/billingAccounts/<enrolment>/enrollmentAccounts/<account>.
See the README for the az billing commands that list these IDs.
DESCRIPTION

  validation {
    condition     = can(regex("^/providers/Microsoft.Billing/billingAccounts/[^/]+/(billingProfiles/[^/]+/invoiceSections/[^/]+|enrollmentAccounts/[^/]+)$", var.billing_scope_id))
    error_message = "billing_scope_id must be a full MCA invoice section ID or EA enrollment account ID starting /providers/Microsoft.Billing/billingAccounts/."
  }
}

variable "subscription_alias_name" {
  type        = string
  description = "Name of the alias (the creation request). It is the idempotency key: the same alias name never creates a second subscription. Letters, digits and hyphens; start with a letter; no periods."

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]{0,61}[A-Za-z0-9]$", var.subscription_alias_name))
    error_message = "Use 2-63 letters, digits and hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "subscription_display_name" {
  type        = string
  description = "Display name of the new subscription, for example alz-corp-app1-prod."
}

variable "subscription_workload" {
  type        = string
  default     = "Production"
  description = "Workload type: Production (Microsoft Azure Plan) or DevTest (Microsoft Azure Plan for DevTest, if the billing profile has it enabled)."

  validation {
    condition     = contains(["Production", "DevTest"], var.subscription_workload)
    error_message = "subscription_workload must be Production or DevTest."
  }
}

variable "management_group_id" {
  type        = string
  default     = null
  description = "Optional ID (name) of the management group to place the new subscription in, for example alz-corp. Null leaves it in the tenant's default management group."
}

variable "subscription_tags" {
  type        = map(string)
  default     = {}
  description = "Tags to set on the subscription itself."
}

variable "cancel_subscription_on_destroy" {
  type        = bool
  default     = true
  description = "When true, terraform destroy cancels the subscription before deleting the alias. When false, destroy only deletes the alias and the subscription keeps running (and billing)."
}
