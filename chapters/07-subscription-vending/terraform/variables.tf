variable "request_file" {
  type        = string
  default     = "../requests/example-payments-prod.yaml"
  description = "Path to the subscription request YAML file, relative to this folder."
}

variable "prefix" {
  type        = string
  default     = "alz"
  description = "Prefix used in the names this code creates."
}

variable "subscription_alias_enabled" {
  type        = bool
  default     = false
  description = <<DESCRIPTION
true: create a NEW subscription with a subscription alias against `billing_scope`.
false (default): configure the EXISTING subscription given in `existing_subscription_id`.
Warning: in alias mode, `terraform destroy` CANCELS the subscription.
DESCRIPTION
}

variable "billing_scope" {
  type        = string
  default     = null
  description = "Billing scope for a new subscription (alias mode only), e.g. an MCA invoice section: /providers/Microsoft.Billing/billingAccounts/{account}/billingProfiles/{profile}/invoiceSections/{section}."

  validation {
    condition     = !var.subscription_alias_enabled || try(startswith(var.billing_scope, "/providers/Microsoft.Billing/billingAccounts/"), false)
    error_message = "subscription_alias_enabled = true needs billing_scope starting /providers/Microsoft.Billing/billingAccounts/."
  }
}

variable "existing_subscription_id" {
  type        = string
  default     = null
  description = "ID of an existing subscription to configure (existing mode only). Lower-case GUID."

  validation {
    condition     = var.subscription_alias_enabled || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.existing_subscription_id))
    error_message = "With subscription_alias_enabled = false, existing_subscription_id must be a lower-case subscription GUID."
  }
}

variable "existing_subscription_update" {
  type        = bool
  default     = true
  description = "Existing mode only: apply the request's tags to the subscription and rename it to <prefix>-<workload>-<environment>. Set false to leave the subscription's name and tags alone."
}

variable "hub_peering_enabled" {
  type        = bool
  default     = false
  description = "Peer the spoke to a hub virtual network (chapter 8). Off by default."
}

variable "hub_virtual_network_id" {
  type        = string
  default     = null
  description = "Resource ID of the hub virtual network. Required when hub_peering_enabled = true."

  validation {
    condition     = !var.hub_peering_enabled || can(regex("/providers/Microsoft.Network/virtualNetworks/", var.hub_virtual_network_id))
    error_message = "hub_peering_enabled = true needs hub_virtual_network_id set to a virtual network resource ID."
  }
}

variable "hub_use_remote_gateways" {
  type        = bool
  default     = false
  description = "Let the spoke use the hub's VPN/ExpressRoute gateway. Only set true if the hub has a gateway, or peering fails."
}

variable "register_resource_providers" {
  type        = bool
  default     = true
  description = "Register the resource providers listed in the request (free)."
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = "AVM module usage telemetry. See https://aka.ms/avm/telemetryinfo."
}
