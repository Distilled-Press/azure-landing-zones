terraform {
  required_version = "~> 1.13"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.13"
    }
    # The Databricks workspace module needs azurerm < 5.0.
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
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }
}

# Authentication comes from the Azure CLI sign-in (az login). Both providers
# get the workload subscription explicitly: the modules mix azapi resources
# (VNet, NSG, NAT gateway, DNS zones, storage, workspace) and azurerm resources
# (private endpoints, access connector, role assignments).
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "azapi" {
  subscription_id = var.subscription_id
}

provider "modtm" {}
