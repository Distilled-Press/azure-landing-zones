terraform {
  required_version = "~> 1.13"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.13"
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
      version = "~> 0.14"
    }
  }
}

# Authentication comes from the Azure CLI sign-in (az login). The sub-vending
# module uses only the azapi provider, so no azurerm provider or subscription
# ID is needed here: every resource is addressed by its full resource ID.
provider "azapi" {}

provider "modtm" {}
