terraform {
  required_version = "~> 1.13"

  required_providers {
    # The identity module and the role assignment use azurerm.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
    # The resource group and storage account modules use AzAPI.
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
  }
}

# Authentication comes from the Azure CLI sign-in (az login). This is the
# one-off bootstrap that creates the pipeline's identities, so it runs as a
# person, not as a pipeline.
provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

provider "azapi" {
  subscription_id = var.subscription_id
}

provider "modtm" {}
