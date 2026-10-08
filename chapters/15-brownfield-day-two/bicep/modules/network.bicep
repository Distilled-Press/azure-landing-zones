// Chapter 15: the brownfield NSG and VNet, decompiled and cleaned.
//
// Started as: az group export --name rg-alz-brownfield-uksouth > main.json
//             az bicep decompile --file main.json
// Cleaned up:
//   - generated parameter names (such as virtualNetworks_vnet_..._name) and
//     hard-coded IDs replaced with parameters, variables and symbolic references
//   - read-only and service-set properties removed (provisioningState,
//     resourceGuid, etag, id)
//   - any child resources (subnets, securityRules) that repeat an inline array
//     removed, so each subnet and rule is declared once, inline, and the subnet
//     references the NSG symbolically
//   - properties left at Azure's defaults removed
// It must still match what's in Azure: what-if against the adopted resources
// should report no changes.

@description('Region of the resources.')
param location string

@description('Name of the NSG.')
param nsgName string

@description('Name of the VNet.')
param vnetName string

@description('Address space of the VNet.')
param addressSpace string = '10.20.0.0/24'

@description('Address prefix of the app subnet.')
param subnetPrefix string = '10.20.0.0/26'

resource nsg 'Microsoft.Network/networkSecurityGroups@2025-05-01' = {
  name: nsgName
  location: location
  tags: {
    environment: 'test'
  }
  properties: {
    // Inline rules: this array is the whole truth for the NSG's rules.
    securityRules: [
      {
        name: 'allow-https-from-vnet'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '443'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2025-05-01' = {
  name: vnetName
  location: location
  tags: {
    environment: 'test'
  }
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressSpace
      ]
    }
    // Inline subnets: a VNet deployed without a subnet that exists in Azure
    // would try to delete it, so every subnet is listed here.
    subnets: [
      {
        name: 'snet-app'
        properties: {
          addressPrefix: subnetPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
          defaultOutboundAccess: false
        }
      }
    ]
  }
}

output nsgId string = nsg.id
output vnetId string = vnet.id
