using 'main.bicep'

param prefix = 'alz'
param location = 'uksouth' // same region as the hub VNet

// Chapter 8's output hubVirtualNetworkId. Set it in the environment:
//   export ALZ_HUB_VNET_ID=/subscriptions/<sub>/resourceGroups/rg-alz-hub-uksouth/providers/Microsoft.Network/virtualNetworks/vnet-alz-hub-uksouth
param hubVirtualNetworkResourceId = readEnvironmentVariable('ALZ_HUB_VNET_ID', '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-alz-hub-uksouth/providers/Microsoft.Network/virtualNetworks/vnet-alz-hub-uksouth')

// (a) Private DNS zones: always created (defaults in main.bicep).

// (b) DNS Private Resolver: billed per endpoint per hour.
// Override on the command line: --parameters deployDnsResolver=true
param deployDnsResolver = false
param dnsInboundIpAddress = '10.10.0.164'
param onpremDomainName = 'corp.example.com.'
param onpremDnsServers = [
  '10.0.0.4'
]

// (c) Virtual WAN: the hub is billed per hour; the secured hub adds Azure Firewall.
param deployVirtualWan = false
param virtualHubAddressPrefix = '10.20.0.0/22'
param deploySecuredHub = false
param virtualHubFirewallSkuTier = 'Standard'
param deployRoutingIntent = false

param tags = {
  environment: 'test'
  managedBy: 'bicep'
}
