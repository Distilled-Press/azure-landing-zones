# Chapter 15: the brownfield resources as Terraform code.
#
# This is the configuration terraform plan -generate-config-out produced for
# the three imported resources, cleaned up:
#   - literal names and IDs replaced with locals (locals.tf) and references, so the NSG
#     and the subnet are linked in code, not just in Azure
#   - arguments left at their defaults or empty (null, [], "") removed
#   - the inline security rule and subnet written as blocks
#   - read-only values (id, guid) removed
# It must still describe exactly what's in Azure: plan after the import has to
# say "No changes". Anything it doesn't match is a change Terraform would make.
#
# Plain azurerm resources rather than AVM modules: -generate-config-out writes
# plain resource blocks, and the point here is the one-to-one match between
# Azure and code. Moving into AVM modules afterwards is a refactoring step
# (removed + import blocks), covered in the README.

resource "azurerm_resource_group" "brownfield" {
  name     = local.resource_group_name
  location = var.location
  tags = {
    environment = "test"
    owner       = "app-team"
  }
}

resource "azurerm_network_security_group" "app" {
  name                = local.nsg_name
  location            = azurerm_resource_group.brownfield.location
  resource_group_name = azurerm_resource_group.brownfield.name
  tags = {
    environment = "test"
  }

  # Rules are inline, so this list is the whole truth: a rule added in the
  # portal shows up in plan as one Terraform would remove.
  security_rule {
    name                       = "allow-https-from-vnet"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "VirtualNetwork"
    source_port_range          = "*"
    destination_address_prefix = "VirtualNetwork"
    destination_port_range     = "443"
  }
}

resource "azurerm_virtual_network" "brownfield" {
  name                = local.vnet_name
  location            = azurerm_resource_group.brownfield.location
  resource_group_name = azurerm_resource_group.brownfield.name
  address_space       = ["10.20.0.0/24"]
  tags = {
    environment = "test"
  }

  # Inline subnet: Terraform owns the VNet's whole subnet list. Don't mix with
  # separate azurerm_subnet resources for the same VNet.
  subnet {
    name                            = "snet-app"
    address_prefixes                = ["10.20.0.0/26"]
    security_group                  = azurerm_network_security_group.app.id
    default_outbound_access_enabled = false
  }
}
