# Chapter 7: Subscription vending

Companion code for the "Build it" section of chapter 7.

A workload team's request is a YAML file in `requests/`. The platform reviews it as a pull request, and the code here turns it into a configured subscription with the Azure Verified Modules (AVM) subscription vending pattern module. Both versions read the same request file.

```
requests/example-payments-prod.yaml   the request (placeholder values)
terraform/                            Terraform root module (Azure/avm-ptn-alz-sub-vending/azure)
bicep/                                Bicep template + one .bicepparam per request (avm/ptn/lz/sub-vending)
```

Tested: not yet

## What it builds

From one request file:

| Item | Detail |
|---|---|
| Subscription | **Existing mode (default):** uses an existing subscription ID. **Alias mode:** creates a new subscription with a subscription alias against a billing scope. |
| Management group placement | Moves the subscription under `management_group_id` from the request (for example `alz-corp` from chapter 6). |
| Tags | The request's `tags` plus `managedBy` and `requestId`, on the subscription, the network resource group, the virtual network and (Terraform) the NSGs. |
| Budget | `budget-<prefix>-<workload>-<env>`, monthly, for `budget.amount`, one email notification per threshold to `budget.contact_emails`. |
| Spoke network | Resource group `rg-<prefix>-<workload>-<env>-network-<region>`, virtual network `vnet-<prefix>-<workload>-<env>-<region>` with the request's address space, one subnet per request entry, and an empty NSG on each subnet. |
| Hub peering | Off by default. Optional input for when chapter 8's hub exists. |
| Role assignments | Each `role_assignments` entry at subscription scope. |
| Resource providers | Registers the request's `resource_providers`. On by default in Terraform (free); off by default in Bicep (see Cost). |

### The two subscription modes

- **Existing subscription (default).** You already have a subscription, perhaps created by hand, by chapter 4's code or by a partner. The code configures it: management group, tags, budget, network, roles, providers. This is the mode the deploy test uses, and the right one when you have no Enterprise Agreement, Microsoft Customer Agreement or Microsoft Partner Agreement: Microsoft's guidance is that without a commercial agreement you create the subscription manually but can still automate everything else.
- **New subscription (alias mode).** The code creates the subscription with a `Microsoft.Subscription/aliases` resource against a billing scope, then configures it. You need a billing role that can create subscriptions on that scope. For an MCA that's owner, contributor or Azure subscription creator on the invoice section (owner or contributor also works on the billing profile or billing account); chapter 4 covers EA and MPA. **In Terraform, `terraform destroy` in alias mode cancels the subscription.**

## Prerequisites

- Azure CLI signed in (`az login`) as an identity with the permissions below. Terraform 1.13 or later; Bicep CLI 0.48 or later (or Azure CLI with Bicep).
- The target management group exists (chapter 6 builds `alz-corp` and the rest of the hierarchy).
- Real Entra ID object IDs in `role_assignments` (for example `az ad group show --group <name> --query id -o tsv`). The placeholder GUIDs in the example will fail.
- An address space that doesn't overlap the hub or other spokes.

### Permissions

| Action | Needs |
|---|---|
| Move the subscription to the management group | On the subscription: management group write and role assignment write and delete (built-in example: Owner). On the target **and** the current parent management group: management group write (Owner, Contributor or Management Group Contributor). No permission is needed on the tenant root group when it's the source or target. If your Owner role on the subscription is inherited from the current management group, you can only move it to a management group where you're also Owner. |
| Role assignments, resource group, virtual network, budget, provider registration | Owner on the subscription covers all of them. |
| Bicep deployment at management group scope | Permission to create deployments at the management group you deploy to (for example Owner on the intermediate root `alz`). |
| Alias mode only | A billing role that can create subscriptions on the billing scope (see above), plus everything in this table. |

In a test tenant the simplest set-up is Owner on the intermediate root management group plus Owner on the subscription. No Entra ID P1/P2 licence is needed: these are ordinary role assignments, not PIM.

## Deploy and destroy: Terraform

```bash
cd chapters/07-subscription-vending/terraform
cp terraform.tfvars.example terraform.tfvars    # then edit
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

Existing mode (default) needs only `existing_subscription_id` (lower-case GUID). For alias mode set `subscription_alias_enabled = true` and `billing_scope`.

Use one Terraform state per request: Microsoft's implementation guidance recommends a dedicated state file for each workload landing zone subscription. With a remote backend, give each request its own key; locally, a workspace per request works:

```bash
terraform workspace new payments-prod
terraform apply -var request_file=../requests/example-payments-prod.yaml
```

Destroy:

```bash
terraform destroy
```

What `destroy` removes and what it leaves:

| | Existing mode | Alias mode |
|---|---|---|
| Network resource group, VNet, NSGs, peering | Deleted | Deleted |
| Budget, role assignments | Deleted | Deleted |
| Subscription | Left | **Cancelled** (the module first tries to delete `NetworkWatcherRG` with the Azure CLI) |
| Management group placement | **Left** in the target management group | n/a |
| Subscription tags and new display name (`existing_subscription_update = true`) | **Left** | n/a |
| Resource provider registrations | Left (registration is free) | n/a |
| `NetworkWatcherRG` (Azure creates it with the VNet) | **Left** | see above |

Finish clean-up in existing mode by hand:

```bash
SUB=00000000-0000-0000-0000-000000000000          # the subscription you used
# Move it back to where it was (the original parent management group ID)
az account management-group subscription add --name <original-parent-mg-id> --subscription $SUB
# Delete Network Watcher's resource group if it didn't exist before
az group delete --subscription $SUB --name NetworkWatcherRG --yes
# Rename the subscription back and remove the tags in the portal
# (Subscriptions > the subscription > Overview / Tags)
```

## Deploy and destroy: Bicep

The `.bicepparam` file loads the YAML with `loadYamlContent()`. That path has to be fixed at build time, so each request gets its own `.bicepparam` (copy `example-payments-prod.bicepparam` and change the path). Subscription-specific values come from environment variables, so the request file stays the same in both modes.

Deploy at a management group; the intermediate root (`alz`) works for everything below it.

```bash
cd chapters/07-subscription-vending/bicep

# Existing mode (default)
export ALZ_EXISTING_SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000

# Alias mode instead
# export ALZ_SUBSCRIPTION_ALIAS_ENABLED=true
# export ALZ_BILLING_SCOPE=/providers/Microsoft.Billing/billingAccounts/<account>/billingProfiles/<profile>/invoiceSections/<section>

az deployment mg what-if --management-group-id alz --location uksouth \
  --name vend-alz-payments-prod --parameters example-payments-prod.bicepparam
az deployment mg create  --management-group-id alz --location uksouth \
  --name vend-alz-payments-prod --parameters example-payments-prod.bicepparam
```

Removing a Bicep deployment doesn't delete what it created, so clean up in this order:

```bash
SUB=00000000-0000-0000-0000-000000000000
NAME=alz-payments-prod

# 1. Network (VNet, NSGs and the spoke side of any peering). If you enabled hub
#    peering, also delete the hub-side peering in the hub's resource group.
az group delete --subscription $SUB --name rg-$NAME-network-uksouth --yes

# 2. Budget
az consumption budget delete --subscription $SUB --budget-name budget-$NAME

# 3. Role assignments created from the request (repeat for each entry)
az role assignment delete --assignee <principal-object-id> --role Contributor --scope /subscriptions/$SUB

# 4. Network Watcher's resource group, if it didn't exist before
az group delete --subscription $SUB --name NetworkWatcherRG --yes

# 5. Only if you set registerResourceProviders = true: the deployment script resource group
az group delete --subscription $SUB --name rsg-uksouth-ds --yes

# 6. Move the subscription back to its original management group
az account management-group subscription add --name <original-parent-mg-id> --subscription $SUB

# 7. Remove the tags in the portal. The Bicep module merges its tags with the
#    existing ones, so delete only the request's keys plus managedBy and requestId.
```

In alias mode, also cancel the new subscription (portal: Subscriptions > the subscription > Cancel). Billing stops on cancellation; you can delete the subscription after a waiting period, and Azure deletes it automatically 90 days after cancellation.

## Inputs

### The request file (`requests/*.yaml`)

| Key | Required | Meaning |
|---|---|---|
| `workload`, `environment` | yes | Used in names (`<prefix>-<workload>-<environment>`) |
| `location` | no (`uksouth`) | Region of the network resource group and VNet |
| `owner_email` | yes | Recorded owner contact |
| `management_group_id` | yes | Management group **ID** (not display name) to place the subscription under |
| `subscription_workload_type` | no (`Production`) | `Production` or `DevTest`; alias mode only |
| `budget.amount` | yes | Monthly amount in the billing currency |
| `budget.threshold_type` | no (`Actual`) | `Actual` or `Forecasted` |
| `budget.thresholds` | yes | Percentages (up to 5 in Bicep) |
| `budget.contact_emails` | yes | Who gets the alerts |
| `tags` | yes | Map of tags |
| `network.address_space` | yes | List of CIDR ranges |
| `network.subnets[]` | yes | `name` and `address_prefix` |
| `role_assignments[]` | yes | `principal_id`, `role` (built-in name or role definition GUID), optional `principal_type` |
| `resource_providers` | no | Namespaces to register |

Role names: Terraform resolves any built-in role name. Bicep resolves Owner, Contributor, Reader, User Access Administrator, Role Based Access Control Administrator and Network Contributor (the map in `main.bicep`); for any other role, give the role definition GUID.

### Platform inputs

| Terraform variable | Bicep parameter | Default | Meaning |
|---|---|---|---|
| `request_file` | path inside the `.bicepparam` | example request | Which request to deploy |
| `prefix` | `prefix` | `alz` | Name prefix |
| `subscription_alias_enabled` | `subscriptionAliasEnabled` (env `ALZ_SUBSCRIPTION_ALIAS_ENABLED`) | `false` | Create a new subscription |
| `billing_scope` | `billingScope` (env `ALZ_BILLING_SCOPE`) | none | Alias mode billing scope |
| `existing_subscription_id` | `existingSubscriptionId` (env `ALZ_EXISTING_SUBSCRIPTION_ID`) | none | Existing mode subscription |
| `existing_subscription_update` | n/a | `true` | Terraform: tag **and rename** the existing subscription. Bicep always merges the tags and never renames. |
| `hub_peering_enabled` | `hubPeeringEnabled` | `false` | Peer to a hub VNet |
| `hub_virtual_network_id` | `hubVirtualNetworkResourceId` | none | Hub VNet resource ID |
| `hub_use_remote_gateways` | `hubUseRemoteGateways` | `false` | Use the hub's gateway (only if the hub has one) |
| `register_resource_providers` | `registerResourceProviders` | `true` / `false` | Register the request's providers |
| `enable_telemetry` | `enableTelemetry` | `true` | AVM telemetry |

## Cost

With the defaults this costs nothing to leave running: the subscription itself, management group placement, tags, the budget, resource groups, the virtual network, subnets, NSGs and role assignments carry no charge. Network Watcher is enabled automatically in the region when the VNet is created, and Microsoft states this has no associated charge.

Things that can cost, all off by default:

- **Bicep `registerResourceProviders = true`.** The Bicep module registers providers with a deployment script. It creates a resource group (`rsg-<region>-ds`) with a storage account, user-assigned managed identity, virtual network, NSG and private DNS zone, and the deployment script service runs an Azure Container Instance. The storage account and container instance are billed until they're removed; check current pricing for the private DNS zone. Terraform registers providers with plain API calls at no cost, and so does `az provider register --namespace <name> --subscription <id>`.
- **Hub peering.** Chapter 8 covers the hub, peering and their costs.
- **Alias mode.** The new subscription is free, but anything later deployed in it is billed to the billing scope.

## How it works

The chapter's Build it text is written from these points.

1. **The request is data, not code.** Terraform: `local.request = yamldecode(file("${path.root}/${var.request_file}"))`. Bicep: `param request = loadYamlContent('../requests/example-payments-prod.yaml')` in the `.bicepparam`, into a parameter of the user-defined type `subscriptionRequest`, so a malformed request fails at build time. One file per subscription, approved by pull request, is the pattern Microsoft's implementation guidance describes.
2. **One switch decides new or existing.** `subscription_alias_enabled` / `subscriptionAliasEnabled`. True: the module creates a `Microsoft.Subscription/aliases` resource with the billing scope and workload type. False: it takes `subscription_id` / `existingSubscriptionId` and configures that subscription. Everything after this works the same in both modes.
3. **Management group placement comes from the request.** `subscription_management_group_association_enabled = true` with `subscription_management_group_id = local.request.management_group_id` (Bicep: `subscriptionManagementGroupAssociationEnabled` / `subscriptionManagementGroupId`). The subscription then inherits the policy and access of that management group, so chapter 6's archetype assignments apply on arrival.
4. **Names are derived, not requested.** `local.name = "${var.prefix}-${workload}-${environment}"` drives the alias, resource group, VNet, NSG and budget names, so a requester can't break the naming convention.
5. **The budget** maps each threshold to a notification with the request's emails (Terraform `budget_notifications`; Bicep `budgetThresholds` + `budgetContactEmails`). Budgets must start on the first of a month, and a past start date must fall within the current time-grain period: Terraform uses `time_static` so the start date is fixed when the budget is created and later plans don't move it; the Bicep module defaults to the current month.
6. **The spoke** is a resource group plus a VNet with the requested address space and an NSG on each subnet (Terraform `network_security_group = { key_reference = k }`; the Bicep module creates one per subnet itself). Peering sits behind `hub_peering_enabled`, off, because the hub doesn't exist until chapter 8; `use_remote_gateways` is exposed and off because peering fails if the hub has no gateway.
7. **Role assignments** turn `principal_id` + `role` into module input. Terraform accepts any built-in role name. The Bicep module only knows five names, so `main.bicep` maps common names to built-in role definition GUIDs.
8. **Some Bicep module defaults are overridden on purpose.** `virtualNetworkResourceGroupLockEnabled: false` (the module defaults to a CanNotDelete lock, which blocks clean-up) and `resourceProviders: {}` unless asked (the module's default list runs a billable deployment script).

## Versions

| Component | Version |
|---|---|
| Terraform | `~> 1.13` (validated with 1.13.4) |
| `Azure/avm-ptn-alz-sub-vending/azure` | `0.3.3` (uses `Azure/avm-utl-roledefinitions/azure` 0.1.0 internally) |
| `Azure/azapi` provider | `~> 2.13` (locked 2.13.0) |
| `Azure/modtm` provider | `~> 0.4` (locked 0.4.0) |
| `hashicorp/random` provider | `~> 3.9` (locked 3.9.1) |
| `hashicorp/time` provider | `~> 0.14` (locked 0.14.2) |
| Bicep CLI | 0.48.1 |
| `br/public:avm/ptn/lz/sub-vending` | `0.8.0` |

## References

- Subscription vending implementation guidance: https://learn.microsoft.com/azure/architecture/landing-zones/subscription-vending
- Subscription vending (CAF design area): https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/subscription-vending
- Programmatically create subscriptions for an MCA: https://learn.microsoft.com/azure/cost-management-billing/manage/programmatically-create-subscription-microsoft-customer-agreement
- Moving subscriptions between management groups, and the permissions needed: https://learn.microsoft.com/azure/governance/management-groups/overview#moving-management-groups-and-subscriptions and https://learn.microsoft.com/azure/governance/management-groups/manage#move-management-groups-and-subscriptions
- Budget time period and notification rules: https://learn.microsoft.com/azure/templates/microsoft.costmanagement/2024-08-01/budgets
- Azure built-in roles (role definition IDs): https://learn.microsoft.com/azure/role-based-access-control/built-in-roles
- Network Watcher automatic enablement: https://learn.microsoft.com/azure/network-watcher/network-watcher-create and https://learn.microsoft.com/azure/network-watcher/frequently-asked-questions#what-is-the-networkwatcherrg
- Deployment scripts and their billable helper resources: https://learn.microsoft.com/azure/azure-resource-manager/bicep/deployment-script-bicep
- Cancel and delete a subscription: https://learn.microsoft.com/azure/cost-management-billing/manage/cancel-azure-subscription
- Terraform module: https://registry.terraform.io/modules/Azure/avm-ptn-alz-sub-vending/azure/0.3.3
- Bicep module: https://github.com/Azure/bicep-registry-modules/tree/main/avm/ptn/lz/sub-vending
