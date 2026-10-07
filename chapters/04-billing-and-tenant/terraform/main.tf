locals {
  # The alias API takes the full management group resource ID.
  management_group_resource_id = var.management_group_id == null ? null : "/providers/Microsoft.Management/managementGroups/${var.management_group_id}"
}

# A subscription alias is a request to create a subscription. PUT it once and
# Azure creates the subscription against the billing scope and returns its ID.
resource "azapi_resource" "subscription_alias" {
  type      = "Microsoft.Subscription/aliases@2021-10-01"
  name      = var.subscription_alias_name
  parent_id = "/" # tenant scope

  body = {
    properties = {
      displayName  = var.subscription_display_name
      workload     = var.subscription_workload
      billingScope = var.billing_scope_id
      additionalProperties = {
        managementGroupId = local.management_group_resource_id
        tags              = var.subscription_tags
      }
    }
  }

  response_export_values = ["properties.subscriptionId"]

  lifecycle {
    # The alias resource can create a subscription but not update one: Azure
    # doesn't keep property changes sent to an existing alias. Rename or retag
    # the subscription itself instead. Ignoring name stops an edited alias name
    # from replacing (and so cancelling) the subscription.
    ignore_changes = [body, name]
  }
}

locals {
  subscription_id = azapi_resource.subscription_alias.output.properties.subscriptionId
}

# Deleting an alias does not cancel the subscription behind it. This action
# runs only on destroy and calls the Subscription - Cancel API, so a test
# deployment stops billing when you destroy it. Cancel fails while the
# subscription still contains resources.
resource "azapi_resource_action" "cancel_subscription" {
  count = var.cancel_subscription_on_destroy ? 1 : 0

  type        = "Microsoft.Resources/subscriptions@2021-10-01"
  resource_id = "/subscriptions/${local.subscription_id}"
  action      = "providers/Microsoft.Subscription/cancel"
  method      = "POST"
  when        = "destroy"
}
