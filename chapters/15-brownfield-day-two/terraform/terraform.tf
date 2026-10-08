terraform {
  # import blocks and -generate-config-out need Terraform 1.5 or later; the
  # book's code is pinned to 1.13.
  required_version = "~> 1.13"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.8"
    }
  }
}

# Authentication comes from the Azure CLI sign-in (az login) on a laptop, or
# from OIDC in the drift workflow (ARM_USE_OIDC, ARM_CLIENT_ID, ARM_TENANT_ID).
# azurerm 5.x registers no resource providers by default; Microsoft.Network is
# already registered wherever a VNet exists.
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
