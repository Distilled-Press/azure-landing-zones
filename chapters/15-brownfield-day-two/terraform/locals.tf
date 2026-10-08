# Names shared by main.tf and imports.tf. In a file of their own so that the
# import blocks still work while main.tf is moved aside for
# terraform plan -generate-config-out (see the README).

locals {
  name                = "${var.prefix}-brownfield-${var.location}" # e.g. alz-brownfield-uksouth
  resource_group_name = "rg-${local.name}"
  nsg_name            = "nsg-${local.name}"
  vnet_name           = "vnet-${local.name}"
}
