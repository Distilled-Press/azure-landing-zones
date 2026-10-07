terraform {
  required_version = "~> 1.13"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.13"
    }
  }
}

# Authentication comes from the Azure CLI sign-in (az login). The alias is a
# tenant-scope resource, so no subscription ID is needed to create it.
provider "azapi" {}
