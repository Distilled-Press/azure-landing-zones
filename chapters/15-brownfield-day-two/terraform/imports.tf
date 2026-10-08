# Chapter 15: adopt the three resources import/create-unmanaged.sh created.
#
# Each import block says: the Azure resource with this ID becomes this address
# in Terraform state. terraform plan shows "3 to import"; terraform apply writes
# them into state without changing anything in Azure (as long as main.tf
# matches what's there). Once imported, these blocks do nothing more: delete
# them, or keep them as a record of where the resources came from.
#
# To see what Terraform would write for you, move main.tf aside and run:
#   terraform plan -generate-config-out=generated.tf
# (see the README). main.tf is that output, cleaned up.

import {
  to = azurerm_resource_group.brownfield
  id = "/subscriptions/${var.subscription_id}/resourceGroups/${local.resource_group_name}"
}

import {
  to = azurerm_network_security_group.app
  id = "/subscriptions/${var.subscription_id}/resourceGroups/${local.resource_group_name}/providers/Microsoft.Network/networkSecurityGroups/${local.nsg_name}"
}

import {
  to = azurerm_virtual_network.brownfield
  id = "/subscriptions/${var.subscription_id}/resourceGroups/${local.resource_group_name}/providers/Microsoft.Network/virtualNetworks/${local.vnet_name}"
}
