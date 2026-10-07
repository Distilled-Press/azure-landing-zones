// Chapter 8: a connectivity hub and one peered spoke.
// Deploy at subscription scope (the connectivity subscription).
//
// Always created (free): two resource groups, the hub VNet with its platform
// subnets, the spoke VNet, the spoke route table and the peering.
// Opt-in (billed per hour): Azure Firewall (deployFirewall) and a VPN gateway
// (deployVpnGateway).
targetScope = 'subscription'

// ---------- Parameters ----------

@description('Prefix used in the names this template creates.')
param prefix string = 'alz'

@description('Region for the hub, the spoke and everything in them.')
param location string = 'uksouth'

@description('Address space of the hub virtual network.')
param hubAddressSpace string = '10.10.0.0/22'

@description('Address prefixes of the hub platform subnets. All are created empty (subnets are free). AzureFirewallManagementSubnet is only created when firewallSkuTier is Basic.')
param hubSubnetPrefixes {
  firewall: string
  firewallManagement: string
  gateway: string
  dnsInbound: string
  dnsOutbound: string
  bastion: string
} = {
  firewall: '10.10.0.0/26'
  firewallManagement: '10.10.0.64/26'
  gateway: '10.10.0.128/27'
  dnsInbound: '10.10.0.160/28'
  dnsOutbound: '10.10.0.176/28'
  bastion: '10.10.1.0/26'
}

@description('Address space of the example spoke virtual network.')
param spokeAddressSpace string = '10.11.0.0/24'

@description('Address prefix of the spoke workload subnet.')
param spokeSubnetPrefix string = '10.11.0.0/26'

@description('Address ranges of the other spokes (for example the chapter 7 vended spokes). Routed to the firewall and allowed by the example rule.')
param otherSpokeAddressPrefixes string[] = [
  '10.100.0.0/16'
]

@description('Deploy Azure Firewall, its public IPs and the spoke routes to it. Billed per hour, so off by default.')
param deployFirewall bool = false

@description('Azure Firewall and firewall policy tier. Basic needs AzureFirewallManagementSubnet and a management public IP.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param firewallSkuTier string = 'Basic'

@description('TCP destination ports the example network rule allows between spokes.')
param spokeToSpokePorts string[] = [
  '22'
  '443'
  '3389'
]

@description('Deploy a VPN gateway in GatewaySubnet and turn on gateway transit. Billed per hour; creation can take 45 minutes or more.')
param deployVpnGateway bool = false

@description('VPN gateway SKU. New gateways must use an AZ SKU.')
@allowed([
  'VpnGw1AZ'
  'VpnGw2AZ'
  'VpnGw3AZ'
  'VpnGw4AZ'
  'VpnGw5AZ'
])
param vpnGatewaySku string = 'VpnGw1AZ'

@description('Availability zones for the firewall and public IPs. Use [] in a region without zones.')
param availabilityZones int[] = [
  1
  2
  3
]

@description('Tags applied to the resource groups and resources.')
param tags object = {}

@description('AVM module usage telemetry. See https://aka.ms/avm/telemetryinfo.')
param enableTelemetry bool = true

// ---------- Derived values ----------

var hubName = '${prefix}-hub-${location}' // e.g. alz-hub-uksouth
var spokeName = '${prefix}-spoke1-${location}' // e.g. alz-spoke1-uksouth

// Basic needs a management NIC, so it needs AzureFirewallManagementSubnet.
var firewallManagementSubnetNeeded = firewallSkuTier == 'Basic'

// Basic supports threat intelligence in alert mode only.
var threatIntelMode = firewallSkuTier == 'Basic' ? 'Alert' : 'Deny'

var allSpokePrefixes = concat([spokeAddressSpace], otherSpokeAddressPrefixes)

var dnsResolverDelegation = 'Microsoft.Network/dnsResolvers'

// ---------- Resource groups ----------

module hubResourceGroup 'br/public:avm/res/resources/resource-group:0.4.4' = {
  name: 'rg-${hubName}'
  params: {
    name: 'rg-${hubName}'
    location: location
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

module spokeResourceGroup 'br/public:avm/res/resources/resource-group:0.4.4' = {
  name: 'rg-${spokeName}'
  params: {
    name: 'rg-${spokeName}'
    location: location
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

// ---------- 1. Hub virtual network and its platform subnets ----------
// The special subnet names are fixed by Azure. They are created even when the
// service that uses them is off, so the address plan is settled once.

module hubVnet 'br/public:avm/res/network/virtual-network:0.10.2' = {
  scope: resourceGroup('rg-${hubName}')
  name: 'vnet-${hubName}'
  dependsOn: [
    hubResourceGroup
  ]
  params: {
    name: 'vnet-${hubName}'
    location: location
    addressPrefixes: [
      hubAddressSpace
    ]
    tags: tags
    enableTelemetry: enableTelemetry
    subnets: concat(
      [
        {
          name: 'AzureFirewallSubnet'
          addressPrefix: hubSubnetPrefixes.firewall
          defaultOutboundAccess: false
        }
        {
          name: 'GatewaySubnet'
          addressPrefix: hubSubnetPrefixes.gateway
          defaultOutboundAccess: false
        }
        {
          name: 'AzureBastionSubnet'
          addressPrefix: hubSubnetPrefixes.bastion
          defaultOutboundAccess: false
        }
        // Reserved for chapter 9's DNS Private Resolver: one subnet per
        // endpoint, each delegated to Microsoft.Network/dnsResolvers.
        {
          name: 'snet-dns-inbound'
          addressPrefix: hubSubnetPrefixes.dnsInbound
          delegation: dnsResolverDelegation
          defaultOutboundAccess: false
        }
        {
          name: 'snet-dns-outbound'
          addressPrefix: hubSubnetPrefixes.dnsOutbound
          delegation: dnsResolverDelegation
          defaultOutboundAccess: false
        }
      ],
      firewallManagementSubnetNeeded
        ? [
            {
              name: 'AzureFirewallManagementSubnet'
              addressPrefix: hubSubnetPrefixes.firewallManagement
              defaultOutboundAccess: false
            }
          ]
        : []
    )
  }
}

// ---------- 2. Azure Firewall (opt-in) ----------

// The policy holds one rule collection group with one network rule
// collection: allow TCP on the chosen ports between spoke ranges. Everything
// else is denied by default.
module firewallPolicy 'br/public:avm/res/network/firewall-policy:0.3.6' = if (deployFirewall) {
  scope: resourceGroup('rg-${hubName}')
  name: 'afwp-${hubName}'
  dependsOn: [
    hubResourceGroup
  ]
  params: {
    name: 'afwp-${hubName}'
    location: location
    tier: firewallSkuTier // must match the firewall's tier
    threatIntelMode: threatIntelMode
    tags: tags
    enableTelemetry: enableTelemetry
    ruleCollectionGroups: [
      {
        name: 'rcg-spoke-to-spoke'
        priority: 200
        ruleCollections: [
          {
            ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
            name: 'allow-spoke-to-spoke'
            priority: 100
            action: {
              type: 'Allow'
            }
            rules: [
              {
                ruleType: 'NetworkRule'
                name: 'spoke-to-spoke-tcp'
                ipProtocols: [
                  'TCP'
                ]
                sourceAddresses: allSpokePrefixes
                destinationAddresses: allSpokePrefixes
                destinationPorts: spokeToSpokePorts
              }
            ]
          }
        ]
      }
    ]
  }
}

// The module creates the public IP, and for Basic the management public IP
// and management IP configuration in AzureFirewallManagementSubnet.
module firewall 'br/public:avm/res/network/azure-firewall:0.11.1' = if (deployFirewall) {
  scope: resourceGroup('rg-${hubName}')
  name: 'afw-${hubName}'
  params: {
    name: 'afw-${hubName}'
    location: location
    azureSkuTier: firewallSkuTier
    virtualNetworkResourceId: hubVnet.outputs.resourceId
    firewallPolicyId: firewallPolicy!.outputs.resourceId
    threatIntelMode: threatIntelMode
    availabilityZones: availabilityZones // also used for both public IPs
    publicIPAddressObject: {
      name: 'pip-${hubName}-afw'
      skuName: 'Standard'
      publicIPAllocationMethod: 'Static'
    }
    managementIPAddressObject: {
      name: 'pip-${hubName}-afw-mgmt'
      skuName: 'Standard'
      publicIPAllocationMethod: 'Static'
    }
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

var firewallPrivateIp = deployFirewall ? firewall!.outputs.privateIp : ''

// ---------- 3. VPN gateway (opt-in, 45+ minutes to create) ----------

module vpnGateway 'br/public:avm/res/network/virtual-network-gateway:0.12.0' = if (deployVpnGateway) {
  scope: resourceGroup('rg-${hubName}')
  name: 'vgw-${hubName}'
  params: {
    name: 'vgw-${hubName}'
    location: location
    gatewayType: 'Vpn'
    skuName: vpnGatewaySku
    vpnType: 'RouteBased'
    vpnGatewayGeneration: vpnGatewaySku == 'VpnGw1AZ' ? 'Generation1' : 'Generation2'
    virtualNetworkResourceId: hubVnet.outputs.resourceId // uses its GatewaySubnet
    clusterSettings: {
      clusterMode: 'activePassiveNoBgp' // one public IP, no BGP
    }
    primaryPublicIPName: 'pip-${hubName}-vgw'
    publicIpAvailabilityZones: availabilityZones
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

// ---------- 4. Spoke: route table, VNet, peering ----------

// The route table always exists (free). Its routes only exist when the
// firewall does: 0.0.0.0/0 and every other spoke range go to the firewall's
// private IP. Gateway route propagation stays on (see the README).
module spokeRouteTable 'br/public:avm/res/network/route-table:0.5.0' = {
  scope: resourceGroup('rg-${spokeName}')
  name: 'rt-${spokeName}'
  dependsOn: [
    spokeResourceGroup
  ]
  params: {
    name: 'rt-${spokeName}'
    location: location
    disableBgpRoutePropagation: false
    routes: deployFirewall
      ? concat(
          [
            {
              name: 'udr-default-to-firewall'
              properties: {
                addressPrefix: '0.0.0.0/0'
                nextHopType: 'VirtualAppliance'
                nextHopIpAddress: firewallPrivateIp
              }
            }
          ],
          map(otherSpokeAddressPrefixes, prefix => {
            name: 'udr-spoke-${replace(replace(prefix, '.', '-'), '/', '_')}-to-firewall'
            properties: {
              addressPrefix: prefix
              nextHopType: 'VirtualAppliance'
              nextHopIpAddress: firewallPrivateIp
            }
          })
        )
      : []
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

// Peering is two resources, one on each VNet; the module creates both. The
// spoke may use the hub's gateway only when one exists, and the hub offers
// gateway transit only then. Both sides allow forwarded traffic, so packets
// the firewall forwards between spokes are accepted.
module spokeVnet 'br/public:avm/res/network/virtual-network:0.10.2' = {
  scope: resourceGroup('rg-${spokeName}')
  name: 'vnet-${spokeName}'
  dependsOn: [
    vpnGateway // useRemoteGateways fails unless the gateway already exists
  ]
  params: {
    name: 'vnet-${spokeName}'
    location: location
    addressPrefixes: [
      spokeAddressSpace
    ]
    subnets: [
      {
        name: 'snet-workload'
        addressPrefix: spokeSubnetPrefix
        routeTableResourceId: spokeRouteTable.outputs.resourceId
        defaultOutboundAccess: false
      }
    ]
    peerings: [
      {
        name: 'peer-${spokeName}-to-${hubName}'
        remoteVirtualNetworkResourceId: hubVnet.outputs.resourceId
        allowVirtualNetworkAccess: true
        allowForwardedTraffic: true
        allowGatewayTransit: false
        useRemoteGateways: deployVpnGateway
        remotePeeringEnabled: true
        remotePeeringName: 'peer-${hubName}-to-${spokeName}'
        remotePeeringAllowVirtualNetworkAccess: true
        remotePeeringAllowForwardedTraffic: true
        remotePeeringAllowGatewayTransit: deployVpnGateway
        remotePeeringUseRemoteGateways: false
      }
    ]
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

// ---------- Outputs ----------

@description('Name of the hub resource group.')
output hubResourceGroupName string = 'rg-${hubName}'

@description('Resource ID of the hub virtual network. Chapter 9 takes this as its input.')
output hubVirtualNetworkId string = hubVnet.outputs.resourceId

@description('Resource ID of the example spoke virtual network.')
output spokeVirtualNetworkId string = spokeVnet.outputs.resourceId

@description('Private IP address of Azure Firewall (empty when deployFirewall is false).')
output firewallPrivateIp string = firewallPrivateIp

@description('Resource ID of the VPN gateway (empty when deployVpnGateway is false).')
output vpnGatewayId string = deployVpnGateway ? vpnGateway!.outputs.resourceId : ''
