terraform {
  required_version = "~> 1.13"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.8"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.13"
    }
  }
}

# Authentication comes from the Azure CLI sign-in (az login).
provider "azurerm" {
  subscription_id = var.subscription_id

  # azurerm 5.x registers no resource providers by default. Register only what
  # this module uses. Registration is free and is never undone by destroy.
  resource_providers_to_register = [
    "Microsoft.Security",
    "Microsoft.OperationalInsights",
    "Microsoft.SecurityInsights",
    "Microsoft.Insights",
  ]

  features {
    log_analytics_workspace {
      # Test-friendly: skip the 14-day soft delete so the same name can be
      # reused straight away. Remove this for a real security workspace.
      permanently_delete_on_destroy = true
    }
    resource_group {
      # Sentinel can add resources of its own to the workspace's resource
      # group; let terraform destroy remove the group anyway.
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Used for the Defender for Cloud security contact (current API version,
# which azurerm_security_center_contact doesn't use).
provider "azapi" {}
