// Chapter 9: central private DNS, hybrid name resolution and a Virtual WAN
// variant, added to chapter 8's hub. Deploy at subscription scope (the
// connectivity subscription that holds the hub).
//
// Always created: a DNS resource group and the private DNS zones, linked to
// the hub VNet.
// Opt-in (billed per hour): the DNS Private Resolver with a forwarding
// ruleset (deployDnsResolver), and a Virtual WAN with one virtual hub
// (deployVirtualWan), optionally secured with Azure Firewall and routing
// intent (deploySecuredHub, deployRoutingIntent).
targetScope = 'subscription'

// ---------- Parameters ----------

@description('Prefix used in the names this template creates.')
param prefix string = 'alz'

@description('Region for the resource groups, the DNS Private Resolver and the virtual hub. The resolver must be in the same region as the hub VNet.')
param location string = 'uksouth'

@description('Resource ID of chapter 8\'s hub virtual network. The zones are linked to it and the resolver uses its snet-dns-inbound and snet-dns-outbound subnets.')
param hubVirtualNetworkResourceId string

// The zone names are the literal names Microsoft documents for the public
// cloud, so the linter's cloud-portability warning is switched off for them.
@description('Private Link private DNS zones to create. Names must be the ones Microsoft documents for each service.')
param privateDnsZoneNames string[] = [
  #disable-next-line no-hardcoded-env-urls
  'privatelink.blob.core.windows.net'
  'privatelink.vaultcore.azure.net'
  #disable-next-line no-hardcoded-env-urls
  'privatelink.database.windows.net'
]

@description('Deploy the DNS Private Resolver (inbound and outbound endpoints) and a forwarding ruleset. Billed per endpoint per hour, so off by default.')
param deployDnsResolver bool = false

@description('Name of the hub subnet for the inbound endpoint (chapter 8 creates it, delegated to Microsoft.Network/dnsResolvers).')
param dnsInboundSubnetName string = 'snet-dns-inbound'

@description('Name of the hub subnet for the outbound endpoint (chapter 8 creates it, delegated to Microsoft.Network/dnsResolvers).')
param dnsOutboundSubnetName string = 'snet-dns-outbound'

@description('Static IP of the inbound endpoint, inside the inbound subnet. On-premises DNS servers forward to this address.')
param dnsInboundIpAddress string = '10.10.0.164'

@description('On-premises DNS domain the example forwarding rule sends to the on-premises DNS servers. Must end with a dot.')
param onpremDomainName string = 'corp.example.com.'

@description('IP addresses of the on-premises DNS servers (port 53).')
param onpremDnsServers string[] = [
  '10.0.0.4'
]

@description('Deploy a Standard Virtual WAN with one virtual hub. The hub is billed per hour from creation, so off by default.')
param deployVirtualWan bool = false

@description('Address prefix of the virtual hub: /24 minimum, /23 recommended, /22 with Azure Firewall. Fixed after creation.')
param virtualHubAddressPrefix string = '10.20.0.0/22'

@description('Deploy Azure Firewall in the virtual hub (secured virtual hub). Billed per hour on top of the hub. Needs deployVirtualWan.')
param deploySecuredHub bool = false

@description('Tier of the secured hub\'s Azure Firewall and its policy.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param virtualHubFirewallSkuTier string = 'Standard'

@description('Configure routing intent: internet and private traffic both go through the secured hub\'s firewall. Needs deploySecuredHub.')
param deployRoutingIntent bool = false

@description('Availability zones for the secured hub\'s Azure Firewall. Use [] in a region without zones.')
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

var dnsName = '${prefix}-dns-${location}' // e.g. alz-dns-uksouth
var vwanName = '${prefix}-vwan-${location}' // e.g. alz-vwan-uksouth

var securedHub = deployVirtualWan && deploySecuredHub
var routingIntent = securedHub && deployRoutingIntent

// ---------- Resource group for the DNS resources ----------

module dnsResourceGroup 'br/public:avm/res/resources/resource-group:0.4.4' = {
  name: 'rg-${dnsName}'
  params: {
    name: 'rg-${dnsName}'
    location: location
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

// ---------- (a) Central private DNS zones, linked to the hub ----------
// One zone per Private Link service, named exactly as Microsoft documents.
// The pattern module knows every documented zone; here it gets a short list.

module privateDnsZones 'br/public:avm/ptn/network/private-link-private-dns-zones:0.7.3' = {
  scope: resourceGroup('rg-${dnsName}')
  name: 'pdz-${dnsName}'
  dependsOn: [
    dnsResourceGroup
  ]
  params: {
    location: location
    privateLinkPrivateDnsZones: privateDnsZoneNames
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: hubVirtualNetworkResourceId
      }
    ]
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

// ---------- (b) DNS Private Resolver (opt-in) ----------
// It goes in the hub VNet, in the two delegated subnets chapter 8 reserved:
// a resolver serves exactly one VNet, the hub is where on-premises queries
// arrive through the gateway, and the hub is linked to the private DNS zones.

module dnsResolver 'br/public:avm/res/network/dns-resolver:0.5.8' = if (deployDnsResolver) {
  scope: resourceGroup('rg-${dnsName}')
  name: 'dnspr-${dnsName}'
  dependsOn: [
    dnsResourceGroup
  ]
  params: {
    name: 'dnspr-${dnsName}'
    location: location
    virtualNetworkResourceId: hubVirtualNetworkResourceId
    // On-premises -> Azure: on-premises DNS servers forward to this static IP.
    inboundEndpoints: [
      {
        name: 'in-${dnsName}'
        subnetResourceId: '${hubVirtualNetworkResourceId}/subnets/${dnsInboundSubnetName}'
        privateIpAllocationMethod: 'Static'
        privateIpAddress: dnsInboundIpAddress
      }
    ]
    // Azure -> on-premises: queries matching the ruleset leave from here.
    outboundEndpoints: [
      {
        name: 'out-${dnsName}'
        subnetResourceId: '${hubVirtualNetworkResourceId}/subnets/${dnsOutboundSubnetName}'
      }
    ]
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

module dnsForwardingRuleset 'br/public:avm/res/network/dns-forwarding-ruleset:0.5.4' = if (deployDnsResolver) {
  scope: resourceGroup('rg-${dnsName}')
  name: 'dnsfrs-${dnsName}'
  params: {
    name: 'dnsfrs-${dnsName}'
    location: location
    dnsForwardingRulesetOutboundEndpointResourceIds: [
      dnsResolver!.outputs.outboundEndpointsObject[0].resourceId
    ]
    forwardingRules: [
      {
        name: 'rule-${join(filter(split(onpremDomainName, '.'), label => !empty(label)), '-')}' // e.g. rule-corp-example-com
        domainName: onpremDomainName
        forwardingRuleState: 'Enabled'
        targetDnsServers: [
          for ip in onpremDnsServers: {
            ipAddress: ip
            port: 53
          }
        ]
      }
    ]
    // Linked to the hub; link spokes too if they use Azure-provided DNS.
    virtualNetworkLinks: [
      {
        name: 'link-hub'
        virtualNetworkResourceId: hubVirtualNetworkResourceId
      }
    ]
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

// ---------- (c) Virtual WAN variant (opt-in) ----------
// A Standard Virtual WAN with one virtual hub: the Microsoft-managed
// alternative to chapter 8's hub VNet. No gateways are deployed.

module vwanResourceGroup 'br/public:avm/res/resources/resource-group:0.4.4' = if (deployVirtualWan) {
  name: 'rg-${vwanName}'
  params: {
    name: 'rg-${vwanName}'
    location: location
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

// The secured hub's firewall needs a policy that already exists.
module virtualHubFirewallPolicy 'br/public:avm/res/network/firewall-policy:0.3.6' = if (securedHub) {
  scope: resourceGroup('rg-${vwanName}')
  name: 'afwp-${vwanName}'
  dependsOn: [
    vwanResourceGroup
  ]
  params: {
    name: 'afwp-${vwanName}'
    location: location
    tier: virtualHubFirewallSkuTier
    threatIntelMode: virtualHubFirewallSkuTier == 'Basic' ? 'Alert' : 'Deny'
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

module virtualWan 'br/public:avm/ptn/network/virtual-wan:0.2.0' = if (deployVirtualWan) {
  scope: resourceGroup('rg-${vwanName}')
  name: 'vwan-${vwanName}'
  dependsOn: [
    vwanResourceGroup
  ]
  params: {
    location: location
    virtualWanParameters: {
      virtualWanName: 'vwan-${vwanName}'
      location: location
      type: 'Standard' // Basic has no firewall, VNet-to-VNet or inter-hub transit
    }
    virtualHubParameters: [
      {
        hubName: 'vhub-${vwanName}'
        hubLocation: location
        hubAddressPrefix: virtualHubAddressPrefix
        s2sVpnParameters: {
          deployS2SVpnGateway: false
        }
        p2sVpnParameters: {
          deployP2SVpnGateway: false
        }
        expressRouteParameters: {
          deployExpressRouteGateway: false
        }
        secureHubParameters: securedHub
          ? {
              deploySecureHub: true
              azureFirewallName: 'afw-${vwanName}'
              azureFirewallSku: virtualHubFirewallSkuTier
              azureFirewallPublicIPCount: 1
              availabilityZones: availabilityZones
              firewallPolicyResourceId: virtualHubFirewallPolicy!.outputs.resourceId
              // Routing intent: internet (0.0.0.0/0) and private (RFC 1918)
              // traffic from every connection goes through this firewall.
              routingIntent: routingIntent
                ? {
                    internetToFirewall: true
                    privateToFirewall: true
                  }
                : null
            }
          : {
              deploySecureHub: false
            }
      }
    ]
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

// ---------- Outputs ----------

@description('Name of the DNS resource group.')
output dnsResourceGroupName string = 'rg-${dnsName}'

@description('Resource ID of the DNS resource group that holds the private DNS zones.')
output privateDnsZonesResourceGroupId string = privateDnsZones.outputs.resourceGroupResourceId

@description('Static IP of the DNS Private Resolver inbound endpoint (empty when deployDnsResolver is false).')
output dnsResolverInboundIp string = deployDnsResolver ? dnsInboundIpAddress : ''

@description('Resource ID of the Virtual WAN (empty when deployVirtualWan is false).')
output virtualWanId string = deployVirtualWan ? virtualWan!.outputs.resourceId : ''
