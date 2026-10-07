# Helper: rewrites ../lib/architecture_definitions/amba_single.alz_architecture_definition.json
# with the management group AMBA is deployed to. The ALZ provider reads that
# file before Terraform plans anything, so it can't be generated inside the
# main configuration. Run this first, then use the same ID in the main folder:
#
#   terraform -chdir=set-amba-scope init
#   terraform -chdir=set-amba-scope apply -var management_group_id=mg-amba-test
#
# It creates nothing in Azure. Its state only tracks the local file.

terraform {
  required_version = "~> 1.13"

  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
  }
}

variable "management_group_id" {
  type        = string
  description = "ID (not resource ID) of the existing management group to deploy AMBA to."
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_.()]{0,89}$", var.management_group_id))
    error_message = "Give the management group ID only (letters, numbers, hyphens, underscores, periods, parentheses)."
  }
}

resource "local_file" "architecture_definition" {
  filename = "${path.module}/../lib/architecture_definitions/amba_single.alz_architecture_definition.json"
  content = templatefile("${path.module}/amba_single.alz_architecture_definition.json.tftpl", {
    management_group_id = var.management_group_id
  })
  file_permission = "0644"
}

output "architecture_definition_file" {
  value = abspath(local_file.architecture_definition.filename)
}
