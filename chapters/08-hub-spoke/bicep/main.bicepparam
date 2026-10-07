using 'main.bicep'

param prefix = 'alz'
param location = 'uksouth'

// Address plan (defaults shown in main.bicep):
// hub 10.10.0.0/22, spoke 10.11.0.0/24, other spokes 10.100.0.0/16 (chapter 7).
param otherSpokeAddressPrefixes = [
  '10.100.0.0/16'
]

// Azure Firewall: billed per hour. Destroy when you've finished testing.
// Override on the command line: --parameters deployFirewall=true
param deployFirewall = false
param firewallSkuTier = 'Basic'

// VPN gateway: billed per hour, 45+ minutes to create and to delete.
param deployVpnGateway = false
param vpnGatewaySku = 'VpnGw1AZ'

param tags = {
  environment: 'test'
  managedBy: 'bicep'
}
