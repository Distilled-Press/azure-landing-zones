using 'main.bicep'

param prefix = 'alz'
param workloadName = 'data'
param location = 'uksouth'

// Address plan (defaults shown in main.bicep): 10.12.0.0/22 with host
// 10.12.0.0/24, container 10.12.1.0/24, private endpoints 10.12.2.0/27.

// Peering to the chapter 8 hub (free).
param hubPeeringEnabled = false
// param hubVirtualNetworkId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-alz-hub-uksouth/providers/Microsoft.Network/virtualNetworks/vnet-alz-hub-uksouth'

// Databricks, NAT gateway, private endpoints and lake: billed.
// Override on the command line: --parameters deployDatabricks=true
// Read the README's clean-up steps before you turn this on.
param deployDatabricks = false
param natGatewayEnabled = true
param privateEndpointsEnabled = true
param workspacePublicNetworkAccessEnabled = true

// Central private DNS zones from chapter 9 (leave empty to create zones here):
// param privateDnsZoneIds = {
//   databricks: '/subscriptions/.../privateDnsZones/privatelink.azuredatabricks.net'
//   blob: '/subscriptions/.../privateDnsZones/privatelink.blob.core.windows.net'
//   dfs: '/subscriptions/.../privateDnsZones/privatelink.dfs.core.windows.net'
// }

param tags = {
  environment: 'test'
  managedBy: 'bicep'
}
