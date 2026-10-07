terraform {
  required_version = "~> 1.13"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.13"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
    modtm = {
      source  = "Azure/modtm"
      version = "~> 0.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
}

# Authentication comes from the Azure CLI sign-in (az login). Both providers
# get the connectivity subscription ID explicitly: azurerm 4.x requires it,
# and the modules mix azurerm resources (DNS resolver) and azapi resources
# (private DNS zones, Virtual WAN).
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "azapi" {
  subscription_id = var.subscription_id
}

provider "modtm" {}
