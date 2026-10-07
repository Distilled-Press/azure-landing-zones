terraform {
  required_version = "~> 1.13"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.8"
    }
  }
}

# Authentication comes from the Azure CLI sign-in (az login). Everything here is
# at management group scope, but the provider still needs a subscription to
# talk to: it uses subscription_id if set, otherwise the CLI's default.
provider "azurerm" {
  features {}
  subscription_id                 = var.subscription_id
  resource_provider_registrations = "none"
}
