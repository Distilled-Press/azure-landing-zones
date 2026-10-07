terraform {
  required_version = ">= 1.12, < 2.0"

  required_providers {
    # Reads the Azure landing zones library and works out the management
    # groups, policy assets and policy role assignments to create.
    alz = {
      source  = "Azure/alz"
      version = "~> 0.22"
    }
    # Creates the resources (the AVM ALZ module uses AzAPI throughout).
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.13"
    }
  }
}

# The library is our local ./lib folder. Its alz_library_metadata.json names
# the Microsoft ALZ library release it builds on (platform/alz 2026.10.0), and
# the provider fetches that dependency into .alzlib/ on first use.
provider "alz" {
  library_references = [
    {
      custom_url = "${path.root}/lib"
    }
  ]
}

# Signs in with the Azure CLI (az login); no IDs or secrets in code.
provider "azapi" {}
