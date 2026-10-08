# Azure Landing Zones: companion code

Companion repository for *Azure Landing Zones: Building an Azure Foundation with the Cloud Adoption Framework* by Tony Rough (Ultra Transcenders: Beyond the Exam, Distilled Press).

Each chapter's "Build it" section has a folder here with a Terraform version and a Bicep version, built on [Azure Verified Modules](https://aka.ms/avm).

## Layout

```
chapters/
  04-billing-and-tenant/        subscription aliases against a billing scope
  05-identity-and-access/       custom roles, platform role assignments, optional PIM
  06-resource-organisation/     management group hierarchy and ALZ archetype policies
  07-subscription-vending/      request file to subscription, spoke, budget and RBAC
  08-hub-spoke/                 hub and spoke VNets, Azure Firewall, optional VPN gateway
  09-virtual-wan-hybrid-dns/    private DNS zones, DNS Private Resolver, Virtual WAN variant
  10-governance-policy/         policy as code: definition, initiative, Modify, exemption
  11-security-baseline/         Defender for Cloud contacts and plans, optional Sentinel
  12-management-baseline/       Log Analytics, action group, Service Health, AMBA (opt-in)
  13-platform-automation/       pipeline identities (OIDC), pipelines, accelerator inputs
  14-workload-landing-zones/    a data workload landing zone
  15-brownfield-day-two/        importing existing resources, drift checks
```

## Before you deploy

- **Use a test tenant.** Several examples create management groups and policy assignments at tenant scope.
- **Watch the cost.** Azure Firewall, VPN and ExpressRoute gateways and Virtual WAN hubs are billed while they exist. Destroy test deployments when you've finished, and put a budget alert on the subscription.
- **Check the versions.** Module versions are pinned. Each chapter README records the versions and date it was last tested.

## Licence

Code is licensed under the MIT licence (see `LICENSE`). The book text is copyright and isn't part of this repository.

Microsoft, Azure and related marks are trademarks of the Microsoft group of companies. This project isn't affiliated with or endorsed by Microsoft.
