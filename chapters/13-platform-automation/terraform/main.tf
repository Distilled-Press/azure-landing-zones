locals {
  resource_group_name = coalesce(var.resource_group_name, "rg-${var.prefix}-platform-automation-${var.location}")
  repo                = "${var.github_organization}/${var.github_repository}"

  # GitHub's OIDC token subject ("sub" claim) for each kind of workflow job.
  # The federated credential's subject must match it exactly.
  github_subject = {
    environment  = "repo:${local.repo}:environment:%s"
    branch       = "repo:${local.repo}:ref:refs/heads/%s"
    tag          = "repo:${local.repo}:ref:refs/tags/%s"
    pull_request = "repo:${local.repo}:pull_request"
  }

  # identity key => credential name => credential, as the AVM module expects.
  federated_credentials = {
    for id_key, id in var.identities : id_key => merge(
      {
        for cred_key, cred in id.federated_credentials : cred_key => {
          name     = "github-${cred_key}"
          issuer   = "https://token.actions.githubusercontent.com"
          audience = ["api://AzureADTokenExchange"]
          subject  = cred.type == "pull_request" ? local.github_subject.pull_request : format(local.github_subject[cred.type], cred.value)
        }
      },
      {
        for cred_key, cred in var.additional_federated_credentials : cred_key => {
          name     = cred_key
          issuer   = cred.issuer
          audience = ["api://AzureADTokenExchange"]
          subject  = cred.subject
        } if cred.identity_key == id_key
      }
    )
  }
}

# ---------- Resource group ----------

module "resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.4.0"

  name             = local.resource_group_name
  location         = var.location
  tags             = var.tags
  enable_telemetry = var.enable_telemetry
}

# ---------- User-assigned managed identities with federated credentials ----------
# No client secret anywhere: GitHub signs a short-lived OIDC token for the job,
# and Microsoft Entra ID swaps it for an access token only if the token's
# issuer, subject and audience match one of these credentials.

module "identity" {
  source   = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version  = "0.5.3"
  for_each = var.identities

  name                           = "id-${var.prefix}-platform-${each.key}-${var.location}"
  location                       = var.location
  resource_group_name            = module.resource_group.name
  federated_identity_credentials = local.federated_credentials[each.key]

  tags             = var.tags
  enable_telemetry = var.enable_telemetry
}

# ---------- Role on the management group ----------
# Plain azurerm resource: one assignment at one scope reads more clearly than the
# AVM role assignment module, which resolves principals through lookup maps and
# brings in the azuread provider.

resource "azurerm_role_assignment" "management_group" {
  for_each = var.identities

  scope                = "/providers/Microsoft.Management/managementGroups/${var.management_group_id}"
  role_definition_name = each.value.role_definition_name
  principal_id         = module.identity[each.key].principal_id
  principal_type       = "ServicePrincipal"
  description          = "Platform pipeline (${each.key}) for ${local.repo}"
}

# Read access to the subscription the pipelines sign in to (see variable).
resource "azurerm_role_assignment" "subscription_reader" {
  for_each = var.subscription_reader_enabled ? var.identities : {}

  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Reader"
  principal_id         = module.identity[each.key].principal_id
  principal_type       = "ServicePrincipal"
  description          = "Platform pipeline (${each.key}) sign-in subscription"
}

# ---------- Optional: Terraform state storage ----------

resource "random_string" "state" {
  count = var.state_storage_enabled ? 1 : 0

  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

module "state_storage" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.10.0"
  count   = var.state_storage_enabled ? 1 : 0

  name             = "st${var.prefix}tfstate${random_string.state[0].result}"
  location         = var.location
  parent_id        = module.resource_group.resource_id
  account_sku_name = "Standard_LRS"

  # Entra ID only: no account keys, so the pipelines must use OIDC for the
  # backend too (use_azuread_auth / ARM_USE_AZUREAD).
  shared_access_key_enabled = false
  # GitHub-hosted runners and Microsoft-hosted agents come from the internet.
  # With private self-hosted runners, turn this off and add a private endpoint.
  public_network_access_enabled = true
  network_rules                 = null

  # Recover from a bad write or an accidental delete of the state file.
  blob_properties = {
    versioning_enabled                = true
    delete_retention_policy           = { enabled = true, days = 30 }
    container_delete_retention_policy = { enabled = true, days = 30 }
  }

  containers = {
    tfstate = {
      name = "tfstate"
      role_assignments = {
        for id_key, id in var.identities : id_key => {
          role_definition_id_or_name = "Storage Blob Data Contributor"
          principal_id               = module.identity[id_key].principal_id
          principal_type             = "ServicePrincipal"
        }
      }
    }
  }

  tags             = var.tags
  enable_telemetry = var.enable_telemetry
}
