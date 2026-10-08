// Chapter 14: a data workload landing zone in a spoke.
// Deploy at resource group scope, into the workload resource group
// (az group create first; see the README).
//
// Always created (free): the spoke VNet with the two Databricks subnets
// (delegated, with an NSG) and a private endpoint subnet, and, if
// hubPeeringEnabled, peering to the chapter 8 hub.
// Opt-in with deployDatabricks (billed): an Azure Databricks workspace
// (Premium, VNet injection, secure cluster connectivity), a NAT gateway for
// cluster egress, private endpoints with private DNS, an access connector and
// an ADLS Gen2 storage account as the lake.
targetScope = 'resourceGroup'

// ---------- Parameters ----------

@description('Prefix used in the names this template creates. Lower-case letters and digits (it is also part of the storage account name).')
@minLength(2)
@maxLength(6)
param prefix string = 'alz'

@description('Short workload name used in resource names.')
@minLength(2)
@maxLength(10)
param workloadName string = 'data'

@description('Region for the workload. The Databricks workspace and its VNet must be in the same region and subscription.')
param location string = resourceGroup().location

@description('Address space of the workload spoke VNet (Databricks VNet injection needs /16 to /24).')
param addressSpace string = '10.12.0.0/22'

@description('Subnet prefixes: Databricks host ("public") and container ("private") subnets, /26 or larger and fixed once the workspace exists, and the private endpoint subnet.')
param subnetPrefixes {
  host: string
  container: string
  privateEndpoints: string
} = {
  host: '10.12.0.0/24'
  container: '10.12.1.0/24'
  privateEndpoints: '10.12.2.0/27'
}

@description('Peer the workload spoke to the chapter 8 hub (both directions). Off by default.')
param hubPeeringEnabled bool = false

@description('Resource ID of the hub VNet (chapter 8 output hubVirtualNetworkId). Required when hubPeeringEnabled is true.')
param hubVirtualNetworkId string = ''

@description('Deploy the Databricks workspace, NAT gateway, private endpoints and DNS, access connector and ADLS Gen2 lake. Billed, so off by default.')
param deployDatabricks bool = false

@description('With deployDatabricks: a StandardV2 NAT gateway on both Databricks subnets. New VNets have no default outbound access, so clusters need an explicit egress path.')
param natGatewayEnabled bool = true

@description('With deployDatabricks: a databricks_ui_api private endpoint (back-end Private Link; required NSG rules become NoAzureDatabricksRules) and dfs/blob private endpoints for the lake.')
param privateEndpointsEnabled bool = true

@description('Allow users to reach the workspace UI and API from the internet. false needs privateEndpointsEnabled; a browser_authentication endpoint is then added too.')
param workspacePublicNetworkAccessEnabled bool = true

@description('Existing private DNS zones (for example chapter 9 central zones) by key: databricks, blob, dfs. A zone left out is created here and linked to the spoke VNet.')
param privateDnsZoneIds {
  databricks: string?
  blob: string?
  dfs: string?
} = {}

@description('Name of the managed resource group Databricks creates and owns.')
param databricksManagedResourceGroupName string = 'rg-${prefix}-${workloadName}-${location}-dbw-managed'

@description('Tags applied to the resources.')
param tags object = {}

@description('AVM module usage telemetry. See https://aka.ms/avm/telemetryinfo.')
param enableTelemetry bool = true

// ---------- Derived values ----------

var name = '${prefix}-${workloadName}-${location}' // e.g. alz-data-uksouth

var natGatewayDeployed = deployDatabricks && natGatewayEnabled
var privateEndpointsDeployed = deployDatabricks && privateEndpointsEnabled

// With a back-end (databricks_ui_api) private endpoint, cluster-to-control-plane
// traffic goes over Private Link, so Databricks drops its AzureDatabricks
// outbound NSG rule.
var requiredNsgRules = privateEndpointsDeployed ? 'NoAzureDatabricksRules' : 'AllRules'

var createDatabricksZone = privateEndpointsDeployed && empty(privateDnsZoneIds.?databricks ?? '')
var createBlobZone = privateEndpointsDeployed && empty(privateDnsZoneIds.?blob ?? '')
var createDfsZone = privateEndpointsDeployed && empty(privateDnsZoneIds.?dfs ?? '')

var lakeName = 'st${prefix}lake${take(uniqueString(resourceGroup().id), 6)}'

// ---------- Guard ----------

// Fails the deployment if the switches contradict each other (used by the
// workspace's publicNetworkAccess below, so the check is in the template).
var publicAccessCheck = workspacePublicNetworkAccessEnabled || privateEndpointsEnabled
  ? true
  : fail('workspacePublicNetworkAccessEnabled = false needs privateEndpointsEnabled = true.')

// ---------- 1. Spoke network (free) ----------

// One NSG for both Databricks subnets, declared with no properties, as in
// Microsoft's Databricks VNet-injection quickstart template. Databricks adds
// its own rules to it through the subnet delegation. Known issue (README):
// once the workspace exists, redeploying this template fails here with
// ConflictWithNetworkIntentPolicy, because an NSG sent without rules would
// remove the rules the workspace's network intent policy requires. Azure
// refuses, so the rules are never lost, but the deployment can't be re-run.
resource nsgDatabricks 'Microsoft.Network/networkSecurityGroups@2025-05-01' = {
  name: 'nsg-${name}-dbw'
  location: location
  tags: tags
}

// Clusters need outbound access (SCC relay, storage, libraries). New VNets have
// no default outbound access, so the NAT gateway is the egress path.
// StandardV2 is zone-redundant by default and needs StandardV2 public IPs.
module natGateway 'br/public:avm/res/network/nat-gateway:2.1.1' = if (natGatewayDeployed) {
  name: 'ng-${name}'
  params: {
    name: 'ng-${name}'
    location: location
    natGatewaySku: 'StandardV2'
    availabilityZone: -1 // no zone pinned: StandardV2 spans the region's zones
    publicIPAddresses: [
      {
        name: 'pip-${name}-ng'
        skuName: 'StandardV2'
        publicIPAllocationMethod: 'Static'
        availabilityZones: [
          1
          2
          3
        ]
      }
    ]
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

module vnet 'br/public:avm/res/network/virtual-network:0.10.2' = {
  name: 'vnet-${name}'
  params: {
    name: 'vnet-${name}'
    location: location
    addressPrefixes: [
      addressSpace
    ]
    subnets: [
      // Both Databricks subnets: delegated to Microsoft.Databricks/workspaces,
      // with the NSG attached, used by no other resource.
      {
        name: 'snet-dbw-host'
        addressPrefix: subnetPrefixes.host
        delegation: 'Microsoft.Databricks/workspaces'
        networkSecurityGroupResourceId: nsgDatabricks.id
        natGatewayResourceId: natGatewayDeployed ? natGateway!.outputs.resourceId : null
        defaultOutboundAccess: false
      }
      {
        name: 'snet-dbw-container'
        addressPrefix: subnetPrefixes.container
        delegation: 'Microsoft.Databricks/workspaces'
        networkSecurityGroupResourceId: nsgDatabricks.id
        natGatewayResourceId: natGatewayDeployed ? natGateway!.outputs.resourceId : null
        defaultOutboundAccess: false
      }
      {
        name: 'snet-pe'
        addressPrefix: subnetPrefixes.privateEndpoints
        defaultOutboundAccess: false
      }
    ]
    // Peering to the chapter 8 hub; the module creates the hub side too (in
    // the hub's subscription and resource group).
    peerings: hubPeeringEnabled
      ? [
          {
            name: 'peer-${name}-to-hub'
            remoteVirtualNetworkResourceId: hubVirtualNetworkId
            allowVirtualNetworkAccess: true
            allowForwardedTraffic: true
            remotePeeringEnabled: true
            remotePeeringName: 'peer-hub-to-${name}'
            remotePeeringAllowVirtualNetworkAccess: true
            remotePeeringAllowForwardedTraffic: true
          }
        ]
      : []
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

var peSubnetId = vnet.outputs.subnetResourceIds[2]

// ---------- 2. Private DNS zones (with the private endpoints) ----------

module dnsZoneDatabricks 'br/public:avm/res/network/private-dns-zone:0.8.1' = if (createDatabricksZone) {
  name: 'pdns-${name}-databricks'
  params: {
    name: 'privatelink.azuredatabricks.net'
    location: 'global'
    virtualNetworkLinks: [
      {
        name: 'link-${name}'
        virtualNetworkResourceId: vnet.outputs.resourceId
      }
    ]
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

module dnsZoneBlob 'br/public:avm/res/network/private-dns-zone:0.8.1' = if (createBlobZone) {
  name: 'pdns-${name}-blob'
  params: {
    name: 'privatelink.blob.${environment().suffixes.storage}'
    location: 'global'
    virtualNetworkLinks: [
      {
        name: 'link-${name}'
        virtualNetworkResourceId: vnet.outputs.resourceId
      }
    ]
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

module dnsZoneDfs 'br/public:avm/res/network/private-dns-zone:0.8.1' = if (createDfsZone) {
  name: 'pdns-${name}-dfs'
  params: {
    name: 'privatelink.dfs.${environment().suffixes.storage}'
    location: 'global'
    virtualNetworkLinks: [
      {
        name: 'link-${name}'
        virtualNetworkResourceId: vnet.outputs.resourceId
      }
    ]
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

var databricksZoneId = createDatabricksZone ? dnsZoneDatabricks!.outputs.resourceId : (privateDnsZoneIds.?databricks ?? '')
var blobZoneId = createBlobZone ? dnsZoneBlob!.outputs.resourceId : (privateDnsZoneIds.?blob ?? '')
var dfsZoneId = createDfsZone ? dnsZoneDfs!.outputs.resourceId : (privateDnsZoneIds.?dfs ?? '')

// ---------- 3. Azure Databricks workspace (opt-in, billed) ----------

module databricks 'br/public:avm/res/databricks/workspace:0.12.0' = if (deployDatabricks) {
  name: 'dbw-${name}'
  params: {
    name: 'dbw-${name}'
    location: location
    skuName: 'premium' // Private Link and VNet injection with SCC need Premium
    managedResourceGroupResourceId: '${subscription().id}/resourceGroups/${databricksManagedResourceGroupName}'
    customVirtualNetworkResourceId: vnet.outputs.resourceId
    customPublicSubnetName: 'snet-dbw-host'
    customPrivateSubnetName: 'snet-dbw-container'
    disablePublicIp: true // secure cluster connectivity: the module defaults to false
    publicNetworkAccess: publicAccessCheck && !workspacePublicNetworkAccessEnabled ? 'Disabled' : 'Enabled'
    requiredNsgRules: requiredNsgRules
    privateEndpoints: privateEndpointsDeployed
      ? concat(
          [
            {
              // Back-end (and front-end) Private Link: REST API and cluster relay.
              name: 'pep-${name}-dbw-ui-api'
              service: 'databricks_ui_api'
              subnetResourceId: peSubnetId
              privateDnsZoneGroup: {
                privateDnsZoneGroupConfigs: [
                  {
                    privateDnsZoneResourceId: databricksZoneId
                  }
                ]
              }
            }
          ],
          workspacePublicNetworkAccessEnabled
            ? []
            : [
                {
                  // Browser SSO over Private Link (one per region and DNS zone).
                  name: 'pep-${name}-dbw-auth'
                  service: 'browser_authentication'
                  subnetResourceId: peSubnetId
                  privateDnsZoneGroup: {
                    privateDnsZoneGroupConfigs: [
                      {
                        privateDnsZoneResourceId: databricksZoneId
                      }
                    ]
                  }
                }
              ]
        )
      : []
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

// The identity Unity Catalog uses to reach the lake.
module accessConnector 'br/public:avm/res/databricks/access-connector:0.4.3' = if (deployDatabricks) {
  name: 'dbac-${name}'
  params: {
    name: 'dbac-${name}'
    location: location
    managedIdentities: {
      systemAssigned: true
    }
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

// ---------- 4. ADLS Gen2 lake (opt-in with the same switch) ----------

module lake 'br/public:avm/res/storage/storage-account:0.33.1' = if (deployDatabricks) {
  name: lakeName
  params: {
    name: lakeName
    location: location
    kind: 'StorageV2'
    skuName: 'Standard_LRS'
    enableHierarchicalNamespace: true // ADLS Gen2
    // Private only, Entra ID only.
    publicNetworkAccess: 'Disabled'
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    blobServices: {
      containers: [
        {
          name: 'raw'
        }
      ]
    }
    privateEndpoints: privateEndpointsEnabled
      ? [
          {
            name: 'pep-${name}-lake-dfs'
            service: 'dfs'
            subnetResourceId: peSubnetId
            privateDnsZoneGroup: {
              privateDnsZoneGroupConfigs: [
                {
                  privateDnsZoneResourceId: dfsZoneId
                }
              ]
            }
          }
          {
            name: 'pep-${name}-lake-blob'
            service: 'blob'
            subnetResourceId: peSubnetId
            privateDnsZoneGroup: {
              privateDnsZoneGroupConfigs: [
                {
                  privateDnsZoneResourceId: blobZoneId
                }
              ]
            }
          }
        ]
      : []
    // Unity Catalog reaches the lake as the access connector's identity.
    roleAssignments: [
      {
        roleDefinitionIdOrName: 'Storage Blob Data Contributor'
        principalId: accessConnector!.outputs.systemAssignedMIPrincipalId!
        principalType: 'ServicePrincipal'
      }
    ]
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

// ---------- Outputs ----------

@description('Resource ID of the workload spoke VNet.')
output virtualNetworkId string = vnet.outputs.resourceId

@description('Resource ID of the Databricks workspace (empty when deployDatabricks is false).')
output databricksWorkspaceId string = deployDatabricks ? databricks!.outputs.resourceId : ''

@description('Name of the Databricks workspace (empty when deployDatabricks is false).')
output databricksWorkspaceName string = deployDatabricks ? databricks!.outputs.name : ''

@description('Workspace URL (empty when deployDatabricks is false).')
output databricksWorkspaceUrl string = deployDatabricks ? databricks!.outputs.workspaceUrl : ''

@description('Name of the Databricks managed resource group.')
output databricksManagedResourceGroupName string = databricksManagedResourceGroupName

@description('Resource ID of the access connector, for a Unity Catalog storage credential (empty when deployDatabricks is false).')
output accessConnectorId string = deployDatabricks ? accessConnector!.outputs.resourceId : ''

@description('Name of the ADLS Gen2 storage account (empty when deployDatabricks is false).')
output lakeStorageAccountName string = deployDatabricks ? lake!.outputs.name : ''
