// Chapter 15: adopt the brownfield resources into a deployment stack.
// Deploy at subscription scope with az stack sub create (see the README), so
// the stack manages the resource group as well as the NSG and the VNet.
//
// The resources already exist (import/create-unmanaged.sh made them). Creating
// the stack with this template makes Azure deploy the same definitions over
// them: nothing changes, and the stack records all three as managed. From then
// on, removing a resource from this file detaches it (detachAll) or deletes it
// (deleteAll), and deny settings can stop changes made outside the stack.
targetScope = 'subscription'

@description('Prefix the brownfield script used (its second argument).')
param prefix string = 'alz'

@description('Region the brownfield script used (its third argument).')
param location string = 'uksouth'

var name = '${prefix}-brownfield-${location}' // e.g. alz-brownfield-uksouth

resource rg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: 'rg-${name}'
  location: location
  tags: {
    environment: 'test'
    owner: 'app-team'
  }
}

module network 'modules/network.bicep' = {
  name: 'brownfield-network'
  scope: rg
  params: {
    location: location
    nsgName: 'nsg-${name}'
    vnetName: 'vnet-${name}'
  }
}

@description('Resource ID of the adopted resource group.')
output resourceGroupId string = rg.id

@description('Resource ID of the adopted VNet.')
output virtualNetworkId string = network.outputs.vnetId

@description('Resource ID of the adopted NSG.')
output networkSecurityGroupId string = network.outputs.nsgId
