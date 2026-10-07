variable "subscription_id" {
  type        = string
  description = "Subscription for the identity resource group (and the optional state storage). In ALZ, the management subscription. Lower-case GUID."
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a lower-case subscription GUID."
  }
}

variable "management_group_id" {
  type        = string
  description = "ID (not resource ID) of the management group the identities get their roles on, for example the intermediate root \"alz\" or the parent chapter 6 builds under."
  nullable    = false

  validation {
    condition     = !strcontains(var.management_group_id, "/")
    error_message = "Give the management group ID only, not /providers/Microsoft.Management/managementGroups/..."
  }
}

variable "prefix" {
  type        = string
  default     = "alz"
  description = "Prefix used in the names this code creates."
  nullable    = false
}

variable "location" {
  type        = string
  default     = "uksouth"
  description = "Region of the resource group, identities and optional storage account."
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  default     = null
  description = "Name of the resource group for the identities. Default: rg-<prefix>-platform-automation-<location>."
}

variable "github_organization" {
  type        = string
  description = "GitHub organisation (or user) that owns the repository, as in github.com/<organization>/<repository>."
  nullable    = false
}

variable "github_repository" {
  type        = string
  description = "GitHub repository name that runs the platform pipeline."
  nullable    = false
}

variable "identities" {
  type = map(object({
    role_definition_name = string
    federated_credentials = map(object({
      type  = string # environment | branch | pull_request | tag
      value = optional(string)
    }))
  }))
  default = {
    # Plans: read-only on the management group. Trusted for pull requests and
    # for runs on main (the plan before an apply).
    plan = {
      role_definition_name = "Reader"
      federated_credentials = {
        pull-request = { type = "pull_request" }
        main-branch  = { type = "branch", value = "main" }
      }
    }
    # Applies: Owner on the management group (chapter 6 creates role
    # assignments for policy identities, which Contributor can't). Trusted only
    # for jobs in the protected "alz-apply" environment.
    apply = {
      role_definition_name = "Owner"
      federated_credentials = {
        apply-environment = { type = "environment", value = "alz-apply" }
      }
    }
  }
  description = <<DESCRIPTION
One user-assigned managed identity per key, each with a role on the management
group and federated credentials for the GitHub repository. Credential types and
the subject each produces:
- environment:  repo:<org>/<repo>:environment:<value>
- branch:       repo:<org>/<repo>:ref:refs/heads/<value>
- tag:          repo:<org>/<repo>:ref:refs/tags/<value>
- pull_request: repo:<org>/<repo>:pull_request   (no value)
DESCRIPTION
  nullable    = false

  validation {
    condition = alltrue(flatten([
      for k, v in var.identities : [
        for ck, c in v.federated_credentials :
        contains(["environment", "branch", "tag", "pull_request"], c.type) && (c.type == "pull_request" ? c.value == null : c.value != null)
      ]
    ]))
    error_message = "Each federated credential type must be environment, branch, tag or pull_request; pull_request takes no value, the others need one."
  }

  validation {
    condition     = alltrue([for k, v in var.identities : length(v.federated_credentials) <= 20])
    error_message = "A user-assigned managed identity holds at most 20 federated credentials."
  }
}

variable "additional_federated_credentials" {
  type = map(object({
    identity_key = string # key in var.identities
    issuer       = string
    subject      = string
  }))
  default     = {}
  description = <<DESCRIPTION
Federated credentials from other issuers, for example an Azure DevOps
workload-identity-federation service connection: copy the Issuer and Subject
identifier the service connection shows. The map key is the credential name.
DESCRIPTION
  nullable    = false
}

variable "subscription_reader_enabled" {
  type        = bool
  default     = true
  description = <<DESCRIPTION
Also give every identity Reader on subscription_id. azure/login and the Azure
DevOps AzureCLI task select that subscription when they sign in, so the identity
must be able to read it. In a real ALZ the management subscription sits under
the management group and Reader is inherited; set false then.
DESCRIPTION
  nullable    = false
}

variable "state_storage_enabled" {
  type        = bool
  default     = false
  description = "Create a storage account and container for Terraform state, with Storage Blob Data Contributor on the container for every identity. Billable (small); off by default."
  nullable    = false
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for every resource created here."
  nullable    = false
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = "AVM module usage telemetry (https://aka.ms/avm/telemetryinfo). No cost."
  nullable    = false
}
