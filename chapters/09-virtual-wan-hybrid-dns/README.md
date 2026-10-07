# Chapter 9: Virtual WAN, hybrid connectivity and DNS

Companion code for the "Build it" section of chapter 9.

Three additions to chapter 8's connectivity subscription:

- **(a)** central private DNS zones for three common Private Link services, linked to chapter 8's hub VNet (always built; no hourly charge);
- **(b)** an Azure DNS Private Resolver with inbound and outbound endpoints and a forwarding ruleset for an on-premises domain (opt-in, billed by the hour);
- **(c)** a Virtual WAN variant: a Standard virtual WAN with one virtual hub, optionally secured with Azure Firewall and routing intent (opt-in, billed by the hour).

```
terraform/   Terraform root module (AVM pattern and resource modules)
bicep/       Bicep template at subscription scope + main.bicepparam
```

Tested: not yet

## What it builds

| Item | Name (defaults) | Created |
|---|---|---|
| DNS resource group | `rg-alz-dns-uksouth` | Always |
| Private DNS zones `privatelink.blob.core.windows.net` (Storage blob), `privatelink.vaultcore.azure.net` (Key Vault), `privatelink.database.windows.net` (Azure SQL Database) | in `rg-alz-dns-uksouth` | Always |
| A virtual network link from each zone to chapter 8's hub VNet (no auto-registration) | | Always |
| DNS Private Resolver in the hub VNet | `dnspr-alz-dns-uksouth` | `deploy_dns_resolver` |
| Inbound endpoint in `snet-dns-inbound`, static IP `10.10.0.164` | `in-alz-dns-uksouth` | `deploy_dns_resolver` |
| Outbound endpoint in `snet-dns-outbound` | `out-alz-dns-uksouth` | `deploy_dns_resolver` |
| Forwarding ruleset on the outbound endpoint, linked to the hub VNet, with one rule: `corp.example.com.` to `10.0.0.4:53` | `dnsfrs-alz-dns-uksouth`, rule `rule-corp-example-com` | `deploy_dns_resolver` |
| Virtual WAN resource group | `rg-alz-vwan-uksouth` | `deploy_virtual_wan` |
| Standard virtual WAN | `vwan-alz-vwan-uksouth` | `deploy_virtual_wan` |
| Virtual hub `10.20.0.0/22`, no gateways | `vhub-alz-vwan-uksouth` | `deploy_virtual_wan` |
| Azure Firewall in the hub (secured virtual hub), **Standard** by default, with a firewall policy (no rules: everything denied) | `afw-alz-vwan-uksouth`, `afwp-alz-vwan-uksouth` | `deploy_virtual_wan` and `deploy_secured_hub` |
| Routing intent: an Internet traffic policy and a Private traffic policy, both to the hub's firewall | `ri-alz-vwan-uksouth` (Terraform) | `deploy_routing_intent` (needs `deploy_secured_hub`) |

### Where the resolver goes, and why

The resolver is in **chapter 8's hub VNet**, in the two subnets chapter 8 already created and delegated to `Microsoft.Network/dnsResolvers` (`snet-dns-inbound` `10.10.0.160/28`, `snet-dns-outbound` `10.10.0.176/28`). Not a separate resolver VNet, because:

- Microsoft's Private Link and DNS integration guidance for Azure landing zones puts the resolver in the hub: on-premises DNS servers forward to the resolver's inbound endpoint, which on-premises reaches through the hub's VPN or ExpressRoute gateway, and the hub VNet is the one linked to the private DNS zones.
- A resolver serves exactly one VNet, in its own region, and each endpoint needs its own dedicated subnet of /28 to /24, delegated to `Microsoft.Network/dnsResolvers`. The hub already has them, so this code never changes chapter 8's VNet; it only places endpoints in existing subnets (chapter 8's Terraform state and this one don't fight over the VNet).

A separate "shared services" VNet peered to the hub also works (Microsoft's hybrid DNS architecture uses one); it costs an extra VNet, peering and address space and gains nothing here.

### What this doesn't do

- It doesn't set the hub's or spokes' DNS servers to the inbound endpoint. In Microsoft's landing zone design every VNet uses the resolver in the hub (or a ruleset link); changing a VNet's DNS servers belongs with the VNet's own code (chapter 8, chapter 7 vending).
- It doesn't create private endpoints or the policy that creates their DNS records. Chapter 10 assigns the ALZ `Deploy-Private-DNS-Zones` initiative, which needs the zone IDs this code outputs.
- The Virtual WAN variant isn't connected to anything: no VNet connections, no gateways. It's there to show the hub, the secured hub and routing intent as resources. Its address space (`10.20.0.0/22`) doesn't overlap chapter 8's.

## Prerequisites

- Chapter 8 deployed in the same subscription and region (its `hub_virtual_network_id` output). Its VNet must have `snet-dns-inbound` and `snet-dns-outbound`.
- Azure CLI signed in (`az login`). Terraform 1.13 or later; Bicep CLI 0.48 or later.
- The Bicep clean-up uses the Azure CLI `dns-resolver` and `azure-firewall` extensions (the CLI offers to install them on first use, or `az extension add --name dns-resolver`).
- Chapter 6's policies, if assigned with enforcement on at `alz-connectivity`, apply here too. Use a test subscription.

### Permissions

| Action | Needs |
|---|---|
| Resource groups, private DNS zones, resolver, ruleset, virtual WAN, hub, firewall | **Contributor** on the subscription |
| Link zones to the hub VNet and put resolver endpoints in its subnets | `Microsoft.Network/virtualNetworks/join/action` and `.../subnets/join/action` on the hub VNet (Contributor or Network Contributor on the hub resource group) |
| Bicep: deploy at subscription scope | `Microsoft.Resources/deployments/write` at the subscription |

If you split the duties, Microsoft's DNS design guidance gives a DNS zone contributor role for the zones (the built-in role for private zones is Private DNS Zone Contributor) and **Network Contributor** for the resolver. No Microsoft Entra ID licence is involved.

## Deploy and destroy: Terraform

```bash
cd chapters/09-virtual-wan-hybrid-dns/terraform
cp terraform.tfvars.example terraform.tfvars
# set subscription_id, and hub_virtual_network_id from chapter 8:
#   terraform -chdir=../../08-hub-spoke/terraform output -raw hub_virtual_network_id
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

The billable parts:

```bash
terraform apply -var deploy_dns_resolver=true                                 # a few minutes
terraform apply -var deploy_virtual_wan=true                                  # hub: up to about 30 minutes
terraform apply -var deploy_virtual_wan=true -var deploy_secured_hub=true \
                -var deploy_routing_intent=true                               # adds the firewall and routing intent
terraform apply                                                               # back to the free defaults
```

Destroy (before destroying chapter 8):

```bash
terraform destroy
```

Terraform deletes in dependency order: forwarding rule, ruleset link and ruleset before the outbound endpoint (Azure refuses the other order), routing intent before the hub firewall, the firewall before the hub, and the hub before the virtual WAN. Removing a virtual hub takes a while.

## Deploy and destroy: Bicep

```bash
cd chapters/09-virtual-wan-hybrid-dns/bicep
az account set --subscription <subscription-id>
export ALZ_HUB_VNET_ID=$(az deployment sub show --name hubspoke-alz --query properties.outputs.hubVirtualNetworkId.value -o tsv)

az deployment sub what-if --location uksouth --name dns-vwan-alz --parameters main.bicepparam
az deployment sub create  --location uksouth --name dns-vwan-alz --parameters main.bicepparam

# Billable parts:
az deployment sub create --location uksouth --name dns-vwan-alz --parameters main.bicepparam \
  deployDnsResolver=true deployVirtualWan=true deploySecuredHub=true deployRoutingIntent=true
```

Bicep deployments are incremental: deploying again with a switch set to `false` stops managing those resources but doesn't delete them. Clean up in this order:

```bash
SUB=<subscription-id>
DNS_RG=rg-alz-dns-uksouth
VWAN_RG=rg-alz-vwan-uksouth

# 1. Resolver: the ruleset and its VNet links must go before the outbound endpoint
az dns-resolver vnet-link delete          --subscription $SUB -g $DNS_RG --ruleset-name dnsfrs-alz-dns-uksouth -n link-hub --yes
az dns-resolver forwarding-ruleset delete --subscription $SUB -g $DNS_RG -n dnsfrs-alz-dns-uksouth --yes
az dns-resolver delete                    --subscription $SUB -g $DNS_RG -n dnspr-alz-dns-uksouth --yes
# 2. The DNS resource group: private DNS zones and their links to the hub
az group delete --subscription $SUB --name $DNS_RG --yes

# 3. Virtual WAN, if deployed: routing intent, firewall, hub, then the WAN
#    (az group delete alone may fail while the hub still has a firewall)
az network vhub routing-intent list --subscription $SUB -g $VWAN_RG --vhub vhub-alz-vwan-uksouth -o table
az network vhub routing-intent delete --subscription $SUB -g $VWAN_RG --vhub vhub-alz-vwan-uksouth -n <name-from-list> --yes
az network firewall delete        --subscription $SUB -g $VWAN_RG -n afw-alz-vwan-uksouth   # azure-firewall CLI extension
az network firewall policy delete --subscription $SUB -g $VWAN_RG -n afwp-alz-vwan-uksouth
az network vhub delete            --subscription $SUB -g $VWAN_RG -n vhub-alz-vwan-uksouth --yes
az network vwan delete            --subscription $SUB -g $VWAN_RG -n vwan-alz-vwan-uksouth
az group delete --subscription $SUB --name $VWAN_RG --yes

# 4. Optional: the deployment record
az deployment sub delete --name dns-vwan-alz
```

## Inputs

| Terraform variable | Bicep parameter | Default | Meaning |
|---|---|---|---|
| `subscription_id` | (the `az account set` subscription) | none | Connectivity subscription |
| `prefix` | `prefix` | `alz` | Name prefix |
| `location` | `location` | `uksouth` | Region; must be the hub VNet's region for the resolver |
| `hub_virtual_network_id` | `hubVirtualNetworkResourceId` (env `ALZ_HUB_VNET_ID`) | none | Chapter 8's hub VNet |
| `private_dns_zones` (map) | `privateDnsZoneNames` (array) | blob, Key Vault, SQL | Private Link zones to create |
| `deploy_dns_resolver` | `deployDnsResolver` | `false` | Resolver, endpoints, ruleset |
| `dns_inbound_subnet_name`, `dns_outbound_subnet_name` | `dnsInboundSubnetName`, `dnsOutboundSubnetName` | `snet-dns-inbound`, `snet-dns-outbound` | Chapter 8's delegated subnets |
| `dns_inbound_ip_address` | `dnsInboundIpAddress` | `10.10.0.164` | Static inbound endpoint IP (inside the inbound subnet) |
| `onprem_domain_name` | `onpremDomainName` | `corp.example.com.` | Domain the example rule forwards (trailing dot) |
| `onprem_dns_servers` | `onpremDnsServers` | `["10.0.0.4"]` | Targets of the rule, port 53 |
| `deploy_virtual_wan` | `deployVirtualWan` | `false` | Standard virtual WAN and one hub |
| `virtual_hub_address_prefix` | `virtualHubAddressPrefix` | `10.20.0.0/22` | Hub address space (fixed after creation) |
| `deploy_secured_hub` | `deploySecuredHub` | `false` | Azure Firewall in the hub |
| `virtual_hub_firewall_sku_tier` | `virtualHubFirewallSkuTier` | `Standard` | Basic, Standard or Premium |
| `deploy_routing_intent` | `deployRoutingIntent` | `false` | Internet and private routing policies to the hub firewall |
| `availability_zones` | `availabilityZones` | `[1, 2, 3]` | Zones for the hub firewall |
| `tags` | `tags` | `{}` | Tags |
| `enable_telemetry` | `enableTelemetry` | `true` | AVM telemetry |

## Cost

**Always on (small, monthly):** each private DNS zone is billed per zone per month (calculated daily, pro-rated), plus DNS queries per million. Three zones for a test cost very little, but they aren't free.

Billed **by the hour** while they exist, all off by default:

| Component | Switch | Billing |
|---|---|---|
| DNS Private Resolver inbound endpoint | `deploy_dns_resolver` | Per endpoint per month, pro-rated to hours |
| DNS Private Resolver outbound endpoint | `deploy_dns_resolver` | Per endpoint per month, pro-rated to hours |
| DNS forwarding ruleset | `deploy_dns_resolver` | Per ruleset per month, pro-rated to hours |
| Standard virtual hub | `deploy_virtual_wan` | Per deployment hour from creation (even with nothing connected), plus routing infrastructure units per hour and data processed per GB |
| Azure Firewall in the secured hub | `deploy_secured_hub` | Per deployment hour (secured virtual hub rate), plus per GB processed |

Microsoft's Virtual WAN cost model lists the hub (per hour), routing infrastructure units, gateway scale units and data processing; this build has no gateways.

Cost of a one-hour test: billed per hour; see the pricing pages for the current rate in your region and currency. (The rates on these pages load in the browser and couldn't be confirmed when this was written, so no figure is given.)

- Azure DNS, private zones and DNS Private Resolver: https://azure.microsoft.com/pricing/details/dns/
- Virtual WAN: https://azure.microsoft.com/pricing/details/virtual-wan/
- Azure Firewall (secured virtual hub): https://azure.microsoft.com/pricing/details/azure-firewall/

A secured hub can take up to about 30 minutes to create, and its removal takes a while too; budget for more than one billed hour.

## How it works

The chapter's Build it text is written from these points.

1. **Zone names come from Microsoft's table, not from the service's public name.** Blob is `privatelink.blob.core.windows.net`, Key Vault `privatelink.vaultcore.azure.net`, Azure SQL Database `privatelink.database.windows.net`. Private endpoints only write their DNS records automatically into zones that use these names, and one zone holds one service's records.
2. **The zones live once, centrally, and are linked to the hub.** Terraform: `virtual_network_link_default_virtual_networks = { hub = { virtual_network_resource_id = var.hub_virtual_network_id } }`; Bicep: `virtualNetworkLinks: [{ virtualNetworkResourceId: hubVirtualNetworkResourceId }]`. Anything that resolves through the hub (the resolver's inbound endpoint, Azure-provided DNS in the hub) then gets the private endpoint IPs. Auto-registration stays off: these zones hold private endpoint records, not VM names. The AVM pattern module knows every documented zone (more than 100); here it's given a short list.
3. **The resolver is two endpoints in two dedicated subnets of one VNet.** `virtual_network_resource_id = var.hub_virtual_network_id`, with `subnet_name = "snet-dns-inbound"` and `"snet-dns-outbound"` (Bicep: full subnet resource IDs). Each subnet is /28 to /24, delegated to `Microsoft.Network/dnsResolvers`, and used by nothing else. The resolver must be in the VNet's region.
4. **Inbound means on-premises to Azure.** The inbound endpoint gets a fixed address (`private_ip_allocation_method = "Static"`, `10.10.0.164`), because on-premises DNS servers hold it in their conditional forwarders for `blob.core.windows.net`, `vaultcore.azure.net` and so on. Queries arriving there are answered by Azure DNS, which sees the zones linked to the hub.
5. **Outbound means Azure to on-premises, and only through a ruleset.** The forwarding ruleset is attached to the outbound endpoint and holds the rule `corp.example.com.` to `10.0.0.4:53` (Terraform `destination_ip_addresses = { "10.0.0.4" = "53" }`; Bicep `targetDnsServers: [{ ipAddress: '10.0.0.4', port: 53 }]`). The rule only applies to VNets linked to the ruleset: here the hub (`link_with_outbound_endpoint_virtual_network = true`); spokes using Azure-provided DNS would need their own links. The domain name ends with a dot.
6. **Everything billable is behind a switch.** `count = var.deploy_dns_resolver ? 1 : 0`, `count = var.deploy_virtual_wan ? 1 : 0`; Bicep `= if (...)`. The secured hub needs a hub (`local.deploy_secured_hub = var.deploy_virtual_wan && var.deploy_secured_hub`), and routing intent needs the firewall (a variable validation stops `deploy_routing_intent` without `deploy_secured_hub`).
7. **The Virtual WAN is Standard, and its hub address space is sized for a firewall.** Basic virtual WANs have no Azure Firewall, VNet-to-VNet or inter-hub transit. A hub needs at least /24, Microsoft recommends /23, and a hub with Azure Firewall needs /22; it can't be changed after creation. Hence `virtual_hub_address_prefix = "10.20.0.0/22"`.
8. **The ALZ Virtual WAN pattern module is switched down to the hub.** Its `enabled_resources` default to on for the firewall, Bastion, both gateway types, private DNS zones, the resolver and a sidecar VNet, and `virtual_wan_settings.enabled_resources.ddos_protection_plan` defaults to on (DDoS Network Protection is billed monthly). The code turns them all off except the firewall and its policy, which follow `deploy_secured_hub`.
9. **Routing intent is two policies with the hub's firewall as next hop.** Terraform: `routing_policies = [{ name = "InternetTraffic", destinations = ["Internet"], next_hop_firewall_key = "primary" }, { name = "PrivateTraffic", destinations = ["PrivateTraffic"], ... }]`; Bicep: `routingIntent: { internetToFirewall: true, privateToFirewall: true }`. With both, every connection's internet-bound traffic and all private traffic (VNet, branch and inter-hub) go through the firewall, and the hub advertises `0.0.0.0/0` to its connections; no UDRs are needed in spokes. Compare chapter 8, where the same effect takes a route table per spoke subnet.

### Modules used, and why

- **Private DNS zones**: the AVM pattern modules (Terraform `avm-ptn-network-private-link-private-dns-zones`, Bicep `avm/ptn/network/private-link-private-dns-zones`), given a short zone list. They're the same modules the ALZ accelerator uses for the full set.
- **Resolver**: Terraform `avm-res-network-dnsresolver` creates the resolver, endpoints, ruleset, rule and link in one module. Bicep splits it: `avm/res/network/dns-resolver` (resolver and endpoints) and `avm/res/network/dns-forwarding-ruleset` (ruleset, rule and link).
- **Virtual WAN**: Terraform uses the ALZ pattern `avm-ptn-alz-connectivity-virtual-wan` (it fits once its defaults are switched off). Bicep uses `avm/ptn/network/virtual-wan`, which builds the WAN, hub, hub firewall and routing intent from one parameter object, with the firewall policy from `avm/res/network/firewall-policy` (the pattern needs an existing policy). There's no Bicep equivalent of the ALZ Virtual WAN pattern module in the public registry.

## Versions

| Component | Version |
|---|---|
| Terraform | `~> 1.13` (validated with 1.13.4) |
| `Azure/avm-res-resources-resourcegroup/azurerm` | `0.4.0` |
| `Azure/avm-ptn-network-private-link-private-dns-zones/azurerm` | `0.23.2` |
| `Azure/avm-res-network-dnsresolver/azurerm` | `0.8.0` |
| `Azure/avm-ptn-alz-connectivity-virtual-wan/azurerm` | `0.18.0` |
| `hashicorp/azurerm` provider | `~> 4.81` (locked 4.81.0) |
| `Azure/azapi` provider | `~> 2.13` (locked 2.13.0) |
| `Azure/modtm` provider | `~> 0.4` (locked 0.4.0) |
| `hashicorp/random` provider | `~> 3.9` (locked 3.9.1) |
| Bicep CLI | 0.48.1 |
| `br/public:avm/res/resources/resource-group` | `0.4.4` |
| `br/public:avm/ptn/network/private-link-private-dns-zones` | `0.7.3` |
| `br/public:avm/res/network/dns-resolver` | `0.5.8` |
| `br/public:avm/res/network/dns-forwarding-ruleset` | `0.5.4` |
| `br/public:avm/res/network/firewall-policy` | `0.3.6` |
| `br/public:avm/ptn/network/virtual-wan` | `0.2.0` |

## References

- Azure Private Endpoint private DNS zone values: https://learn.microsoft.com/azure/private-link/private-endpoint-dns
- Private Link and DNS integration at scale (zones in the connectivity subscription, resolver in the hub): https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/private-link-and-dns-integration-at-scale
- What is Azure DNS Private Resolver (endpoints, rulesets, subnet and VNet restrictions, limits): https://learn.microsoft.com/azure/dns/dns-private-resolver-overview
- Resolver endpoints and rulesets (ruleset links, static inbound IPs): https://learn.microsoft.com/azure/dns/private-resolver-endpoints-rulesets
- Private resolver architecture (centralised and distributed): https://learn.microsoft.com/azure/dns/private-resolver-architecture
- Azure DNS Private Resolver reference architecture (resolver in the hub): https://learn.microsoft.com/azure/architecture/networking/architecture/azure-dns-private-resolver
- Hybrid DNS design (resolver in a shared services VNet, subnet sizing): https://learn.microsoft.com/azure/architecture/hybrid/hybrid-dns-infra
- DNS security and private name resolution (roles, dedicated subnets): https://learn.microsoft.com/azure/networking/design-guide/dns-security
- Virtual hub settings (address space: /24 minimum, /23 recommended, /22 with Azure Firewall): https://learn.microsoft.com/azure/virtual-wan/hub-settings
- Basic and Standard virtual WANs, cost model: https://learn.microsoft.com/azure/networking/design-guide/virtual-wan
- Hub billed once created: https://learn.microsoft.com/azure/virtual-wan/virtual-wan-site-to-site-portal
- Routing intent and routing policies: https://learn.microsoft.com/azure/virtual-wan/how-to-routing-policies
- Secured virtual hub with Azure Firewall Manager (up to 30 minutes to create): https://learn.microsoft.com/azure/firewall-manager/secure-cloud-network
- Terraform modules: https://registry.terraform.io/modules/Azure/avm-ptn-alz-connectivity-virtual-wan/azurerm/0.18.0, https://registry.terraform.io/modules/Azure/avm-res-network-dnsresolver/azurerm/0.8.0, https://registry.terraform.io/modules/Azure/avm-ptn-network-private-link-private-dns-zones/azurerm/0.23.2
- Bicep modules: https://github.com/Azure/bicep-registry-modules/tree/main/avm/ptn/network and https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/network
- Pricing: https://azure.microsoft.com/pricing/details/dns/, https://azure.microsoft.com/pricing/details/virtual-wan/, https://azure.microsoft.com/pricing/details/azure-firewall/
