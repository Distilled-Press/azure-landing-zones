# Helper: rewrites ../lib/architecture_definitions/alz_custom.alz_architecture_definition.json
# with a new management group prefix. The ALZ provider reads that file before
# Terraform plans anything, so it can't be generated inside the main
# configuration. Run this first, then use the same prefix in the main folder:
#
#   terraform -chdir=set-prefix init
#   terraform -chdir=set-prefix apply -var prefix=mylz
#
# It creates nothing in Azure. Its state only tracks the local file.

terraform {
  required_version = ">= 1.12, < 2.0"

  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
  }
}

variable "prefix" {
  type        = string
  description = "Management group ID prefix, for example alz or mylz."
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_.()]{0,39}$", var.prefix))
    error_message = "Use 1-40 characters: letters, numbers, hyphens, underscores, periods and parentheses, starting with a letter or number."
  }
}

resource "local_file" "architecture_definition" {
  filename = "${path.module}/../lib/architecture_definitions/alz_custom.alz_architecture_definition.json"
  content = templatefile("${path.module}/alz_custom.alz_architecture_definition.json.tftpl", {
    prefix = var.prefix
  })
  file_permission = "0644"
}

output "architecture_definition_file" {
  value = abspath(local_file.architecture_definition.filename)
}
