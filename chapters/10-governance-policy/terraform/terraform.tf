terraform {
  required_version = "~> 1.13"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.8"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14"
    }
  }
}

# Authentication comes from the Azure CLI sign-in (az login). Everything here
# is at management group scope, but the azurerm provider still needs a
# subscription to start: with no subscription_id it uses the Azure CLI's
# default subscription (az account show). Nothing is deployed into it.
# azurerm 5.x registers no resource providers by default, and none are needed
# for management groups and policy.
provider "azurerm" {
  features {}
}
