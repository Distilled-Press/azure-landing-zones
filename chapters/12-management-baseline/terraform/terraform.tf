terraform {
  required_version = "~> 1.13"

  required_providers {
    # The AVM resource modules for the workspace and the identity use azurerm;
    # the action group and the Service Health alert are plain azurerm resources.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
    # The resource group and data collection rule modules use AzAPI.
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.13"
    }
    # Reads the Azure landing zones library for the opt-in AMBA-ALZ policies.
    alz = {
      source  = "Azure/alz"
      version = "~> 0.22"
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

# Authentication comes from the Azure CLI sign-in (az login). azurerm 4.x needs
# the subscription ID explicitly; it is an input with no default.
provider "azurerm" {
  subscription_id = var.subscription_id

  features {
    log_analytics_workspace {
      # A deleted workspace otherwise stays soft-deleted for 14 days.
      permanently_delete_on_destroy = true
    }
  }
}

provider "azapi" {
  subscription_id = var.subscription_id
}

provider "modtm" {}

# Only used when deploy_amba = true. The local ./lib folder names the AMBA
# library release it builds on (platform/amba 2026.06.2) and adds a
# single-management-group architecture for it.
provider "alz" {
  library_references = [
    {
      custom_url = "${path.root}/lib"
    }
  ]
}
