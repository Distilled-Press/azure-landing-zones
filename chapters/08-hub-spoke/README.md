# Chapter 8: Hub-spoke network topology

Companion code for the "Build it" section of chapter 8.

A connectivity hub in one resource group and one spoke peered to it, in the connectivity subscription. The hub VNet gets all its platform subnets up front; the billable parts (Azure Firewall and a VPN gateway) are switches that are off by default.

```
terraform/   Terraform root module (AVM resource modules)
bicep/       Bicep template at subscription scope + main.bicepparam (AVM resource modules)
```

Tested: 8 October 2026 (Terraform 1.13.4, Bicep CLI 0.48.1, Azure CLI 2.91.0): Terraform apply with the defaults, with `deploy_firewall=true` (Basic), back to the defaults (firewall removed) and destroy; Bicep deployment with the defaults and the clean-up commands, in a test tenant. The VPN gateway was planned (`terraform plan` with `deploy_vpn_gateway=true`) but not applied (30-45 minutes each way, billed per hour); the Bicep firewall and gateway were not deployed.

## What it builds

| Item | Name or range (defaults) | Created |
|---|---|---|
| Hub resource group | `rg-alz-hub-uksouth` | Always |
| Hub VNet `10.10.0.0/22` | `vnet-alz-hub-uksouth` | Always |
| `AzureFirewallSubnet` | `10.10.0.0/26` | Always |
| `AzureFirewallManagementSubnet` | `10.10.0.64/26` | When the firewall tier is Basic (Basic needs it), whether or not the firewall is deployed |
| `GatewaySubnet` | `10.10.0.128/27` | Always |
| `snet-dns-inbound`, `snet-dns-outbound`, delegated to `Microsoft.Network/dnsResolvers` | `10.10.0.160/28`, `10.10.0.176/28` | Always (chapter 9's DNS Private Resolver uses them) |
| `AzureBastionSubnet` | `10.10.1.0/26` | Always, reserved; no Bastion host is deployed |
| Spoke resource group | `rg-alz-spoke1-uksouth` | Always |
| Spoke VNet `10.11.0.0/24` with `snet-workload` `10.11.0.0/26` | `vnet-alz-spoke1-uksouth` | Always |
| Spoke route table on `snet-workload` | `rt-alz-spoke1-uksouth` | Always (no routes until the firewall exists) |
| Peering in both directions | `peer-alz-spoke1-uksouth-to-alz-hub-uksouth` and the reverse | Always |
| Firewall policy (tier matches the firewall) with rule collection group `rcg-spoke-to-spoke`: network rule collection `allow-spoke-to-spoke`, TCP 22, 443 and 3389 between all spoke ranges | `afwp-alz-hub-uksouth` | `deploy_firewall` |
| Azure Firewall, **Basic** by default, zones 1-3, public IP (plus a management public IP for Basic) | `afw-alz-hub-uksouth`, `pip-alz-hub-uksouth-afw`, `pip-alz-hub-uksouth-afw-mgmt` | `deploy_firewall` |
| Spoke routes: `0.0.0.0/0` and each other spoke range (`10.100.0.0/16`, chapter 7's spokes) to the firewall's private IP | in `rt-alz-spoke1-uksouth` | `deploy_firewall` |
| VPN gateway **VpnGw1AZ**: route-based, active-passive, no BGP, zone-redundant public IP | `vgw-alz-hub-uksouth`, `pip-alz-hub-uksouth-vgw` | `deploy_vpn_gateway` |
| Gateway transit: `allowGatewayTransit` on the hub side, `useRemoteGateways` on the spoke side | on the two peerings | `deploy_vpn_gateway` |

Every platform subnet is created even when its service is off: subnets cost nothing, the address plan is decided once, and switching a service on later adds a resource instead of reshaping the VNet. Chapter 9 relies on this: its resolver goes into the two DNS subnets without changing this VNet.

### VPN gateway SKU

New VPN gateways must use an availability-zone SKU. Since 1 November 2025 the non-AZ VpnGw1-5 SKUs can't be created, and existing ones were scheduled to move to AZ SKUs by 30 September 2026. The smallest production SKU is **VpnGw1AZ** (Generation1, 650 Mbps aggregate, BGP supported). The Basic SKU is cheaper, but Microsoft lists it for dev-test and proof of concept only (no BGP, no IKEv2 point-to-site, configurable only with PowerShell or the Azure CLI), so it isn't offered here. Creating a gateway can take **45 minutes or more**, and deleting one is slow too.

## Prerequisites

- Azure CLI signed in (`az login`). Terraform 1.13 or later; Bicep CLI 0.48 or later (or the Azure CLI with Bicep).
- A connectivity subscription. Chapter 6 places it under the `alz-connectivity` management group. If chapter 6's policy assignments there are enforced, they apply to this deployment (for example, a deny on public IPs would block the firewall and the gateway). Use a test subscription, and don't move production subscriptions under a test hierarchy.
- An address plan that doesn't overlap anything you'll connect. The defaults use `10.10.0.0/22` (hub) and `10.11.0.0/24` (spoke), and treat `10.100.0.0/16` as chapter 7's spokes.

### Permissions

| Action | Needs |
|---|---|
| Create the resource groups, VNets, peering, route table, firewall, policy, public IPs and gateway | **Contributor** on the subscription (or Network Contributor plus permission to create resource groups) |
| Bicep: deploy at subscription scope | `Microsoft.Resources/deployments/write` at the subscription (Contributor has it) |
| Peer a spoke in a different subscription (chapter 7) | Network Contributor, or the peering permissions, on both VNets |

No Microsoft Entra ID licence is involved.

## Deploy and destroy: Terraform

```bash
cd chapters/08-hub-spoke/terraform
cp terraform.tfvars.example terraform.tfvars    # then set subscription_id
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

Switch the billable parts on when you need them, and off again afterwards:

```bash
terraform apply -var deploy_firewall=true                                # about 7 minutes (removing it takes about 8)
terraform apply -var deploy_firewall=true -var deploy_vpn_gateway=true   # the gateway takes 45+ minutes
terraform apply                                                          # back to the free defaults: removes both
```

Destroy:

```bash
terraform destroy
```

`destroy` removes both resource groups and everything in them. It leaves `NetworkWatcherRG`, which Azure creates the first time a VNet is created in a region; delete it if it didn't exist before:

```bash
az group delete --subscription <subscription-id> --name NetworkWatcherRG --yes
```

If chapter 9 is deployed, destroy chapter 9 first: its resolver sits in the hub's delegated subnets and its DNS zones are linked to the hub VNet. If chapter 7 peered a spoke to this hub, remove that peering first (chapter 7 with `hub_peering_enabled = false`).

## Deploy and destroy: Bicep

```bash
cd chapters/08-hub-spoke/bicep
az account set --subscription <subscription-id>

az deployment sub what-if --location uksouth --name hubspoke-alz --parameters main.bicepparam
az deployment sub create  --location uksouth --name hubspoke-alz --parameters main.bicepparam

# Billable parts on:
az deployment sub create --location uksouth --name hubspoke-alz \
  --parameters main.bicepparam deployFirewall=true deployVpnGateway=true
```

Bicep deployments are incremental. Deploying again with `deployFirewall=false` empties the spoke route table but **doesn't delete the firewall**, and `deployVpnGateway=false` turns gateway transit off but leaves the gateway. Delete billable resources yourself (the `az network firewall` commands come from the Azure CLI `azure-firewall` extension, which the CLI offers to install on first use):

```bash
RG=rg-alz-hub-uksouth
# Firewall first, then its policy and public IPs
az network firewall delete        -g $RG -n afw-alz-hub-uksouth
az network firewall policy delete -g $RG -n afwp-alz-hub-uksouth
az network public-ip delete       -g $RG -n pip-alz-hub-uksouth-afw
az network public-ip delete       -g $RG -n pip-alz-hub-uksouth-afw-mgmt     # Basic only
# Gateway: redeploy with deployVpnGateway=false first (turns off useRemoteGateways),
# then delete the gateway and its public IP
az network vnet-gateway delete    -g $RG -n vgw-alz-hub-uksouth
az network public-ip delete       -g $RG -n pip-alz-hub-uksouth-vgw
```

Full clean-up, in this order:

```bash
SUB=<subscription-id>
# 1. Chapter 9, if deployed (see its README).
# 2. The spoke (its side of the peering goes with it)
az group delete --subscription $SUB --name rg-alz-spoke1-uksouth --yes
# 3. The hub: VNet, hub-side peering, firewall, policy, gateway, public IPs
az group delete --subscription $SUB --name rg-alz-hub-uksouth --yes
# 4. Network Watcher's resource group, if it didn't exist before
az group delete --subscription $SUB --name NetworkWatcherRG --yes
# 5. Optional: the deployment record
az deployment sub delete --name hubspoke-alz
```

## Inputs

| Terraform variable | Bicep parameter | Default | Meaning |
|---|---|---|---|
| `subscription_id` | (the `az account set` subscription) | none | Connectivity subscription |
| `prefix` | `prefix` | `alz` | Name prefix |
| `location` | `location` | `uksouth` | Region |
| `hub_address_space` | `hubAddressSpace` | `10.10.0.0/22` | Hub VNet |
| `hub_subnet_prefixes` | `hubSubnetPrefixes` | see the table above | Platform subnet prefixes |
| `spoke_address_space`, `spoke_subnet_prefix` | `spokeAddressSpace`, `spokeSubnetPrefix` | `10.11.0.0/24`, `10.11.0.0/26` | Example spoke |
| `other_spoke_address_prefixes` | `otherSpokeAddressPrefixes` | `["10.100.0.0/16"]` | Other spokes: routed to the firewall and allowed by the example rule |
| `deploy_firewall` | `deployFirewall` | `false` | Azure Firewall, policy, public IPs and spoke routes |
| `firewall_sku_tier` | `firewallSkuTier` | `Basic` | Basic, Standard or Premium; the policy tier matches. Change it only while the firewall is off (Basic adds `AzureFirewallManagementSubnet`) |
| `spoke_to_spoke_ports` | `spokeToSpokePorts` | `22`, `443`, `3389` | TCP ports the example rule allows |
| `deploy_vpn_gateway` | `deployVpnGateway` | `false` | VPN gateway and gateway transit |
| `vpn_gateway_sku` | `vpnGatewaySku` | `VpnGw1AZ` | VpnGw1AZ to VpnGw5AZ |
| `availability_zones` | `availabilityZones` | `[1, 2, 3]` | Zones for the firewall and public IPs (`[]` in a region without zones) |
| `tags` | `tags` | `{}` | Tags |
| `enable_telemetry` | `enableTelemetry` | `true` | AVM telemetry |

## Cost

With the defaults this costs nothing to leave running: resource groups, VNets, subnets, route tables and peerings have no charge of their own. Traffic that crosses a peering is charged per GB in each direction.

Billed **per hour** while they exist, all off by default:

| Component | Switch | Billing |
|---|---|---|
| Azure Firewall (Basic by default) | `deploy_firewall` | Per deployment hour, plus per GB processed |
| Firewall public IP (Standard, static); Basic adds a second, management public IP | `deploy_firewall` | Per hour each |
| VPN gateway (VpnGw1AZ) | `deploy_vpn_gateway` | Per hour, plus data transfer |
| Gateway public IP (Standard, static) | `deploy_vpn_gateway` | Per hour |

Cost of a one-hour test: billed per hour; see the pricing pages for the current rate in your region and currency. (The rates on these pages load in the browser and couldn't be confirmed when this was written, so no figure is given.)

- Azure Firewall: https://azure.microsoft.com/pricing/details/azure-firewall/
- VPN Gateway: https://azure.microsoft.com/pricing/details/vpn-gateway/
- Public IP addresses: https://azure.microsoft.com/pricing/details/ip-addresses/
- Virtual network peering: https://azure.microsoft.com/pricing/details/virtual-network/

Allow for the VPN gateway's 45+ minutes to create and its time to delete: a "one-hour test" with a gateway bills for nearer two hours.

## How it works

The chapter's Build it text is written from these points.

1. **The hub VNet carries every platform subnet from day one.** `AzureFirewallSubnet`, `GatewaySubnet` and `AzureBastionSubnet` are names Azure requires; the firewall and Bastion subnets must be at least /26, and the gateway subnet should be /27 or larger. `AzureFirewallManagementSubnet` is added only when `firewall_sku_tier` is Basic, because Basic always has a management NIC (Standard and Premium need one only for forced tunnelling). The two DNS subnets are delegated to `Microsoft.Network/dnsResolvers`, ready for chapter 9.
2. **Billable resources hang off two booleans.** Terraform: `count = var.deploy_firewall ? 1 : 0` on the policy, rules, public IPs and firewall, and `count = var.deploy_vpn_gateway ? 1 : 0` on the gateway. Bicep: `module firewall ... = if (deployFirewall)`. Nothing else changes when they're switched.
3. **Firewall and policy tiers must match**, and Basic supports threat intelligence in alert mode only, so the threat intelligence mode is derived from the tier (`Alert` for Basic, `Deny` otherwise). The firewall points at the policy (`firewall_policy_id` / `firewallPolicyId`); the rules live in the policy, not on the firewall.
4. **One rule collection group, one network rule collection, one rule**: `rcg-spoke-to-spoke` (priority 200) contains `allow-spoke-to-spoke` (priority 100, Allow), which allows TCP on `spoke_to_spoke_ports` from any spoke range to any spoke range. Traffic no rule allows is denied, so spoke-to-spoke traffic needs this rule as soon as it's routed through the firewall.
5. **The spoke route table always exists; its routes arrive with the firewall.** `routes = var.deploy_firewall ? {...} : {}` (Bicep `deployFirewall ? [...] : []`). `0.0.0.0/0` and each entry of `other_spoke_address_prefixes` get next hop type `VirtualAppliance` at the firewall's private IP (`module.firewall[0].resource.ip_configuration[0].private_ip_address`; Bicep `firewall!.outputs.privateIp`). Peering isn't transitive, so without these routes one spoke can't reach another at all; with them, the firewall forwards the traffic. Each other spoke needs a matching route table for the return path (chapter 7's vended spokes don't create one).
6. **Gateway route propagation is deliberately left on.** With a VPN gateway, on-premises prefixes learned by the gateway are more specific than `0.0.0.0/0`, so spoke-to-on-premises traffic goes straight through the gateway: not inspected, but symmetric. Microsoft's pattern for inspecting hybrid traffic too is to turn propagation **off** on the spoke route table and add a route table on `GatewaySubnet` that sends each spoke's exact prefix to the firewall (with propagation on). It's a two-sided change: doing only one side makes routing asymmetric, and the stateful firewall drops the flows. The chapter text covers it; the code keeps the simple default.
7. **Peering is two resources with matching flags.** Spoke side: `allow_forwarded_traffic = true` and `use_remote_gateways = var.deploy_vpn_gateway`. Hub side (Terraform `reverse_*`, Bicep `remotePeering*`): `allow_forwarded_traffic = true` and `allow_gateway_transit = var.deploy_vpn_gateway`. `use_remote_gateways` fails if the hub has no gateway, so it's true only when the gateway is deployed, and the peering depends on the gateway so that it's created afterwards.
8. **The VPN gateway reuses the hub's `GatewaySubnet`** (Terraform `subnet_creation_enabled = false` with `virtual_network_gateway_subnet_id`; the Bicep module finds `GatewaySubnet` in the VNet it's given). It's active-passive with one public IP (`vpn_active_active_enabled = false`, Bicep `clusterMode: 'activePassiveNoBgp'`); the Terraform module defaults to active-active, which needs two public IPs.

### Why AVM resource modules rather than the hub-and-spoke pattern modules

AVM pattern modules for this job exist: Terraform `Azure/avm-ptn-alz-connectivity-hub-and-spoke-vnet/azurerm` (0.17.7, which the ALZ IaC accelerator uses in chapter 13) and Bicep `avm/ptn/network/hub-networking` (0.5.0). They aren't a good fit for this build:

- They build hubs, not spokes, so the spoke, its route table and the peering would still be separate code.
- The Terraform pattern creates a platform subnet only when its service is enabled, so the firewall, gateway and Bastion subnets can't be reserved while the billable service is off. Several of its services also default to on (DDoS protection plan, Bastion, both gateway types, the full private DNS zone set, the resolver), and each would need switching off.
- They generate the route tables and peering flags internally, and those are the lines this chapter teaches.

The resource modules (`avm-res-network-virtualnetwork`, `-azurefirewall`, `-firewallpolicy`, `-routetable`, `-publicipaddress` and `avm-ptn-vnetgateway`; Bicep `avm/res/network/...`) keep each of those lines visible.

## Versions

| Component | Version |
|---|---|
| Terraform | `~> 1.13` (validated with 1.13.4) |
| `Azure/avm-res-resources-resourcegroup/azurerm` | `0.4.0` |
| `Azure/avm-res-network-virtualnetwork/azurerm` (and `//modules/peering`) | `0.22.2` |
| `Azure/avm-res-network-firewallpolicy/azurerm` (and `//modules/rule_collection_groups`) | `0.3.4` |
| `Azure/avm-res-network-azurefirewall/azurerm` | `0.4.0` |
| `Azure/avm-res-network-publicipaddress/azurerm` | `0.2.1` |
| `Azure/avm-res-network-routetable/azurerm` | `0.5.0` |
| `Azure/avm-ptn-vnetgateway/azurerm` | `0.10.3` |
| `hashicorp/azurerm` provider | `~> 4.81` (locked 4.81.0; the firewall and route table modules don't accept azurerm 5.x yet) |
| `Azure/azapi` provider | `~> 2.13` (locked 2.13.0) |
| `Azure/modtm` provider | `~> 0.4` (locked 0.4.0) |
| `hashicorp/random` provider | `~> 3.9` (locked 3.9.1) |
| Bicep CLI | 0.48.1 |
| `br/public:avm/res/resources/resource-group` | `0.4.4` |
| `br/public:avm/res/network/virtual-network` | `0.10.2` |
| `br/public:avm/res/network/firewall-policy` | `0.3.6` |
| `br/public:avm/res/network/azure-firewall` | `0.11.1` |
| `br/public:avm/res/network/route-table` | `0.5.0` |
| `br/public:avm/res/network/virtual-network-gateway` | `0.12.0` |

## References

- Azure Firewall features by SKU (Basic: alert-only threat intelligence, 250 Mbps, no DNS proxy): https://learn.microsoft.com/azure/firewall/features-by-sku
- Azure Firewall management NIC (always on for Basic; `AzureFirewallManagementSubnet` /26 minimum): https://learn.microsoft.com/azure/firewall/management-nic
- Deploy Azure Firewall Basic and a policy: https://learn.microsoft.com/azure/firewall/deploy-firewall-basic-portal-policy
- Azure Firewall SKU choice and subnets: https://learn.microsoft.com/azure/networking/design-guide/azure-firewall
- Dedicated subnet names and minimum sizes: https://learn.microsoft.com/azure/networking/design-guide/vnets-subnets
- Azure Bastion subnet (/26 or larger): https://learn.microsoft.com/azure/bastion/configuration-settings
- Spoke-to-spoke routing through the hub firewall: https://learn.microsoft.com/azure/networking/design-guide/hub-spoke
- GatewaySubnet route table, gateway route propagation and hybrid traffic through the firewall: https://learn.microsoft.com/azure/firewall/firewall-multi-hub-spoke
- Gateway transit flags on peering: https://learn.microsoft.com/azure/vpn-gateway/vpn-gateway-different-region
- VPN gateway SKUs (AZ SKUs for new gateways; Basic for dev-test only): https://learn.microsoft.com/azure/vpn-gateway/about-gateway-skus
- VPN gateway SKU consolidation (no new non-AZ VpnGw1-5 since 1 November 2025): https://learn.microsoft.com/azure/vpn-gateway/gateway-sku-consolidation
- Gateway creation time (45 minutes or more) and GatewaySubnet sizing: https://learn.microsoft.com/azure/vpn-gateway/tutorial-create-gateway-portal and https://learn.microsoft.com/azure/vpn-gateway/create-routebased-vpn-gateway-cli
- Default outbound access and private subnets: https://learn.microsoft.com/azure/virtual-network/ip-services/default-outbound-access
- Terraform modules: https://registry.terraform.io/modules/Azure/avm-res-network-virtualnetwork/azurerm/0.22.2 (and the other `avm-res-network-*` and `avm-ptn-vnetgateway` pages)
- Bicep modules: https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/network
- Pricing: https://azure.microsoft.com/pricing/details/azure-firewall/, https://azure.microsoft.com/pricing/details/vpn-gateway/, https://azure.microsoft.com/pricing/details/ip-addresses/, https://azure.microsoft.com/pricing/details/virtual-network/
