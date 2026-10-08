# Chapter 14: Workload landing zones

Companion code for the "Build it" section of chapter 14.

A data workload landing zone: one workload's spoke, ready for Azure Databricks with VNet injection, secure cluster connectivity and Private Link, and an ADLS Gen2 lake behind private endpoints. It goes in a workload subscription (one vended by chapter 7, under the Corp management group) and can peer to chapter 8's hub. The network is free and always deployed; everything that bills sits behind one switch, `deploy_databricks`, which is off by default.

```
terraform/   Terraform root module (AVM resource modules)
bicep/       Bicep template at resource group scope + main.bicepparam (AVM resource modules)
```

Tested: 8 October 2026 (Terraform 1.13.4, Bicep CLI 0.48.1, Azure CLI 2.91.0 with the databricks extension 1.3.2): Terraform apply with the defaults, then `deploy_databricks = true` (workspace about 9 minutes), the README destroy (force deletion 5 min 37 s, then `terraform destroy`, 70 resources); Bicep with the defaults and with `deployDatabricks=true` (workspace 11 min 24 s), and the one-command clean-up, in a test tenant. A second Bicep deployment once the workspace exists fails (see Known issue). Not tested: hub peering (no hub deployed), `workspace_public_network_access_enabled = false` and the `browser_authentication` endpoint, `nat_gateway_enabled = false`, `private_endpoints_enabled = false`, existing DNS zones, the keep-the-spoke clean-up path, and clusters (no DBUs were run).

## What it builds

| Item | Name or range (defaults) | Created |
|---|---|---|
| Workload resource group | `rg-alz-data-uksouth` | Terraform: always. Bicep: you create it with `az group create` |
| Spoke VNet `10.12.0.0/22` | `vnet-alz-data-uksouth` | Always |
| Databricks host ("public") subnet, delegated to `Microsoft.Databricks/workspaces` | `snet-dbw-host`, `10.12.0.0/24` | Always |
| Databricks container ("private") subnet, delegated the same way | `snet-dbw-container`, `10.12.1.0/24` | Always |
| Private endpoint subnet | `snet-pe`, `10.12.2.0/27` | Always |
| NSG on both Databricks subnets (empty; Databricks adds its rules) | `nsg-alz-data-uksouth-dbw` | Always |
| Peering to the chapter 8 hub, both directions | `peer-alz-data-uksouth-to-hub`, `peer-hub-to-alz-data-uksouth` | `hub_peering_enabled` |
| NAT gateway **StandardV2** with one StandardV2 public IP, on both Databricks subnets | `ng-alz-data-uksouth`, `pip-alz-data-uksouth-ng` | `deploy_databricks` (and `nat_gateway_enabled`, default true) |
| Azure Databricks workspace, **Premium**, VNet injection, no public IP on cluster nodes | `dbw-alz-data-uksouth` | `deploy_databricks` |
| Databricks managed resource group (created and owned by Databricks) | `rg-alz-data-uksouth-dbw-managed` | With the workspace |
| Private endpoint `databricks_ui_api` (back-end and front-end Private Link) | `pep-alz-data-uksouth-dbw-ui-api` | `deploy_databricks` and `private_endpoints_enabled` (default true) |
| Private endpoint `browser_authentication` (browser SSO over Private Link) | `pep-alz-data-uksouth-dbw-auth` | Also `workspace_public_network_access_enabled = false` |
| Private DNS zones `privatelink.azuredatabricks.net`, `privatelink.blob.core.windows.net`, `privatelink.dfs.core.windows.net`, linked to the spoke | in the workload resource group | With the private endpoints, unless you pass existing zones in `private_dns_zone_ids` |
| Access connector for Azure Databricks (system-assigned identity) | `dbac-alz-data-uksouth` | `deploy_databricks` |
| ADLS Gen2 storage account (hierarchical namespace, LRS, public network access disabled, shared keys off), container `raw`, private endpoints `dfs` and `blob`, Storage Blob Data Contributor for the access connector | `stalzlake<6 characters>` | `deploy_databricks` |

The two Databricks subnets are created even while the workspace is off: subnets are free, the address plan is settled once, and a workspace's subnet ranges can't be changed after it's created anyway.

### The Databricks network settings, as Learn describes them now

- **VNet injection** needs a VNet of /16 to /24 in the same region and subscription as the workspace, and two subnets that only this workspace uses, delegated to `Microsoft.Databricks/workspaces`, each with an NSG. Learn recommends /26 or larger and matching sizes; each cluster node takes one IP in each subnet.
- **Secure cluster connectivity** (no public IP) is on: `no_public_ip = true` (Terraform), `disablePublicIp: true` (Bicep; the AVM Bicep module defaults to `false`). Cluster nodes get no public IPs and open a connection out to the control plane's relay instead. Databricks plans to make it mandatory for classic workspaces.
- **Egress.** Since 31 March 2026 new VNets have no default outbound internet access, and Learn says new Databricks workspaces need an explicit outbound method such as a NAT gateway on both subnets. The NAT gateway is part of the billed switch; set `nat_gateway_enabled = false` only if you route egress through a hub firewall with your own routes and rules (not built here; chapter 8's example rules don't allow Databricks traffic).
- **Private Link comes in three kinds.** Back-end (classic compute plane to control plane), inbound or front-end (users to the workspace) and outbound (serverless compute to your resources, configured in the Databricks account's network connectivity configurations, not here). This code builds the **back-end** connection: a `databricks_ui_api` endpoint in the workspace's own VNet. Learn's table for "Classic compute plane (back-end) only": Premium, VNet injection, SCC, **public network access enabled**, required NSG rules `NoAzureDatabricksRules`. So the code sets `NoAzureDatabricksRules` whenever the endpoint exists, and `AllRules` otherwise.
- **Public network access** stays **enabled** by default, so you can open the workspace in a browser to test it. `workspace_public_network_access_enabled = false` gives Learn's "complete private isolation" shape: it needs the private endpoints (the code refuses the combination otherwise) and adds a `browser_authentication` endpoint for SSO. Users then need a network path and DNS to the endpoints: in a real landing zone the front-end endpoints sit in a transit VNet (the hub) with chapter 9's central zones and DNS Private Resolver. Learn recommends one `browser_authentication` endpoint per region, hosted on a dedicated "private web auth workspace", because deleting its host workspace breaks SSO for every workspace in that region; the endpoint here is only for a test.

## Prerequisites

- Azure CLI signed in (`az login`). Terraform 1.13 or later; Bicep CLI 0.48 or later.
- A workload subscription. In ALZ this sits under Landing zones > Corp (chapter 6), vended by chapter 7. Policy assigned there applies to this deployment, and the Corp archetype's public-endpoint and public-IP denials can block the defaults here (the NAT gateway's public IP, a workspace with public network access enabled). Check chapter 6's assignments, use a test subscription, and don't move production subscriptions under a test hierarchy.
- Resource providers registered: `Microsoft.Network`, `Microsoft.Storage` and `Microsoft.Databricks` (`az provider register --namespace Microsoft.Databricks` if chapter 7 didn't).
- An address plan that doesn't overlap the hub (`10.10.0.0/22`), chapter 8's spoke (`10.11.0.0/24`) or chapter 7's spokes (`10.100.0.0/16`).
- The **Azure CLI `databricks` extension** for the force-delete clean-up step (the CLI offers to install it on first use).

### Permissions

| Action | Needs |
|---|---|
| Network, NAT gateway, DNS zones, storage, workspace, access connector | **Contributor** on the subscription. Learn: the workspace creator needs Network Contributor on the VNet, or `subnets/join/action` and `subnets/write` |
| Role assignment for the access connector on the lake | **Owner**, User Access Administrator or Role Based Access Control Administrator on the storage account (in practice Owner on the subscription, or Contributor plus an RBAC administrator role) |
| Hub peering (`hub_peering_enabled`) | Network Contributor, or the peering permissions, on the hub VNet too (it's in the connectivity subscription) |

No licence is needed in Azure or Microsoft Entra ID. Premium is an Azure Databricks pricing tier billed through Azure; Private Link needs it.

## Deploy and destroy: Terraform

```bash
cd chapters/14-workload-landing-zones/terraform
cp terraform.tfvars.example terraform.tfvars    # then set subscription_id
terraform init
terraform plan -out tfplan
terraform apply tfplan                          # the free spoke
```

Peer to chapter 8's hub (free):

```bash
terraform apply -var hub_peering_enabled=true \
  -var hub_virtual_network_id=$(terraform -chdir=../../08-hub-spoke/terraform output -raw hub_virtual_network_id)
```

Switch on the billable parts (the workspace takes about 10 minutes):

```bash
terraform apply -var deploy_databricks=true
terraform output databricks_workspace_url
```

Destroy. **Force-delete the workspace first.** Learn: when a Unity Catalog-enabled workspace is deleted normally, Azure Databricks keeps the default workspace catalog's data by converting the managed resource group into an ordinary resource group, with the storage container and access connector still in it (and still billed). The AVM module deletes the workspace without force deletion, so do it yourself, then destroy:

```bash
RG=$(terraform output -raw resource_group_name)
WS=$(terraform output -raw databricks_workspace_name)
az databricks workspace delete --force-deletion --name "$WS" --resource-group "$RG" --yes
terraform destroy
```

The force deletion takes about 5 minutes and removes the managed resource group (with Unity Catalog's `unity-catalog-access-connector` and workspace storage account) as well. Terraform finds the workspace gone, drops it from state and removes everything else, including both sides of the peering. Check that the managed resource group has gone, and delete it if it's still there (it can be, if the workspace was deleted without `--force-deletion`):

```bash
az group show --name rg-alz-data-uksouth-dbw-managed 2>/dev/null && \
  az group delete --name rg-alz-data-uksouth-dbw-managed --yes
```

To go back to the free spoke without destroying it, force-delete the workspace the same way and then `terraform apply` with `deploy_databricks=false`.

Learn's other clean-up notes: deleted workspaces are soft-deleted for 7 days (workspace metadata only; Azure resources go at once), and serverless model serving and vector search endpoints keep billing through those 7 days unless deleted first. This code creates neither. `NetworkWatcherRG` is created by Azure the first time a VNet is created in a region; delete it if it didn't exist before.

## Deploy and destroy: Bicep

```bash
cd chapters/14-workload-landing-zones/bicep
az account set --subscription <subscription-id>
az group create --name rg-alz-data-uksouth --location uksouth --tags environment=test managedBy=bicep

az deployment group what-if --resource-group rg-alz-data-uksouth --name ch14-data --parameters main.bicepparam
az deployment group create  --resource-group rg-alz-data-uksouth --name ch14-data --parameters main.bicepparam

# Hub peering and the billable parts
az deployment group create --resource-group rg-alz-data-uksouth --name ch14-data --parameters main.bicepparam \
  hubPeeringEnabled=true hubVirtualNetworkId=<hub VNet resource ID> deployDatabricks=true
```

Bicep deployments are incremental: deploying again with `deployDatabricks=false` removes nothing. **Once the workspace exists, a second deployment of this template fails** (see Known issue below), so deploy the network and the billable parts in the order shown, and change anything else before `deployDatabricks=true`.

Clean up with one command (about 10 minutes with a workspace), which deletes the workspace with force deletion (so the managed resource group and the workspace catalog go too) and everything else in the group:

```bash
az group delete --name rg-alz-data-uksouth --force-deletion-types Microsoft.Databricks/workspaces --yes
```

Learn notes that deleting the resource group in the portal doesn't force-delete the workspace catalog; use the CLI (or PowerShell's `-ForceDeletionType`). Then:

```bash
# If hubPeeringEnabled was true: the hub side of the peering stays on the hub VNet, disconnected
az network vnet peering delete --subscription <connectivity-subscription-id> \
  -g rg-alz-hub-uksouth --vnet-name vnet-alz-hub-uksouth -n peer-hub-to-alz-data-uksouth
# If the managed resource group is still there
az group delete --name rg-alz-data-uksouth-dbw-managed --yes
# Optional: NetworkWatcherRG, if it didn't exist before
```

To remove only the billable parts and keep the spoke (not tested): force-delete the workspace (`az databricks workspace delete --force-deletion ...` as above), redeploy with `deployDatabricks=false` (this detaches the NAT gateway from the subnets; do it **before** deleting the NAT gateway, which can't be deleted while subnets use it), then delete the NAT gateway, its public IP, the private endpoints, the DNS zones, the lake and the access connector.

### Known issue: the Bicep NSG can't be redeployed while the workspace exists

The NSG is declared with no properties so that a redeployment wouldn't remove Databricks' rules. Tested on 8 October 2026, it doesn't work that way: a resource with no `properties` is sent as an NSG with no security rules, which asks Azure to remove the rules Databricks added. Azure refuses, because the workspace puts a network intent policy on its subnets that requires them, and the whole deployment fails:

```
ConflictWithNetworkIntentPolicy: Network Security Group cannot have resources which conflict with its subnets' network intent policies.
... conflicts with Network Intent Policy: adb-uksouth-dp-to-cp-pl-<id>
Network Security Group doesn't have supporting Security Rule for Network Intent Policy Security Rule: Name: databricks-worker-to-sql ...
```

Nothing is changed (the rules stay as they were), but any redeployment of `main.bicep` with the workspace in place fails at the NSG, including one that only adds hub peering. Microsoft's quickstart template declares the NSG the same way, so it has the same limit. A PUT of the NSG that includes Databricks' current rules was accepted in the test, so declaring the rules explicitly (Learn's vnet-inject page lists them; the set depends on `requiredNsgRules`) is a likely fix, but it wasn't built or tested here. Terraform isn't affected: the AVM NSG module ignores changes to security rules, and `terraform plan` after the workspace was created showed no changes.

## Inputs

| Terraform variable | Bicep parameter | Default | Meaning |
|---|---|---|---|
| `subscription_id` | (the `az account set` subscription) | none | Workload subscription |
| `prefix` | `prefix` | `alz` | Name prefix, 2-6 lower-case letters or digits |
| `workload_name` | `workloadName` | `data` | Workload name in resource names |
| `location` | `location` | `uksouth` (Bicep: the resource group's region) | Region |
| `address_space` | `addressSpace` | `10.12.0.0/22` | Spoke VNet |
| `subnet_prefixes` | `subnetPrefixes` | host `10.12.0.0/24`, container `10.12.1.0/24`, private endpoints `10.12.2.0/27` | Subnets |
| `hub_peering_enabled`, `hub_virtual_network_id` | `hubPeeringEnabled`, `hubVirtualNetworkId` | `false`, none | Peering to the chapter 8 hub |
| `deploy_databricks` | `deployDatabricks` | `false` | Everything billed: workspace, NAT gateway, endpoints, DNS, access connector, lake |
| `nat_gateway_enabled` | `natGatewayEnabled` | `true` | NAT gateway for cluster egress (with `deploy_databricks`) |
| `private_endpoints_enabled` | `privateEndpointsEnabled` | `true` | Workspace and lake private endpoints and DNS zones (with `deploy_databricks`) |
| `workspace_public_network_access_enabled` | `workspacePublicNetworkAccessEnabled` | `true` | `false` needs the private endpoints and adds `browser_authentication` |
| `private_dns_zone_ids` | `privateDnsZoneIds` | `{}` | Existing zones (chapter 9) by key `databricks`, `blob`, `dfs`; missing ones are created here |
| `databricks_managed_resource_group_name` | `databricksManagedResourceGroupName` | `rg-<prefix>-<workload>-<location>-dbw-managed` | Must not exist beforehand |
| `tags` | `tags` | `{}` | Tags |
| `enable_telemetry` | `enableTelemetry` | `true` | AVM telemetry |

With `private_endpoints_enabled = false` the lake still has public network access disabled, so nothing can reach its data: it shows the shape but isn't usable without the endpoints.

## Cost

With the defaults this costs nothing to leave running: the resource group, VNet, subnets, NSG and peering have no charge of their own (traffic across a peering is charged per GB in each direction).

With `deploy_databricks = true`:

| Component | Billing |
|---|---|
| Databricks workspace | No DBUs until compute runs: Databricks bills DBUs per hour of compute by VM type, plus the VMs, disks and networking of classic clusters. A workspace with no clusters, pools or SQL warehouses running costs little, but not nothing: its managed resource group holds a workspace storage account that bills for what it stores |
| NAT gateway (StandardV2) | **Per hour** while it exists, plus per GB processed (StandardV2 costs the same as Standard) |
| NAT gateway public IP (StandardV2) | Per hour |
| Private endpoints (one for the workspace, two for the lake; one more with public access off) | Per hour each, plus per GB in and out |
| Private DNS zones (three) | Per zone per month, plus queries |
| ADLS Gen2 storage account | Capacity and transactions; pence for an empty account |
| Access connector | No separate charge was found for the connector itself |

The hourly items (NAT gateway, its IP, the private endpoints) are what an idle test costs; destroy it when you've finished. Pricing pages (rates load in the browser and weren't confirmed when this was written):

- Azure Databricks: https://azure.microsoft.com/pricing/details/databricks/
- NAT Gateway: https://azure.microsoft.com/pricing/details/azure-nat-gateway/
- Private Link: https://azure.microsoft.com/pricing/details/private-link/
- Azure DNS: https://azure.microsoft.com/pricing/details/dns/
- Public IP addresses: https://azure.microsoft.com/pricing/details/ip-addresses/
- Data Lake Storage: https://azure.microsoft.com/pricing/details/storage/data-lake/

## How it works

The chapter's Build it text is written from these points.

1. **The landing zone is the spoke, not the workspace.** The resource group, VNet, delegated subnets and NSG are free and always there; the workload's billed resources hang off one switch (`count = var.deploy_databricks ? 1 : 0`; Bicep `= if (deployDatabricks)`). That's the shape of a vended workload landing zone: the platform provides the address space and connectivity, the workload team adds the service.
2. **Two subnets, delegated, with an NSG** (`delegations = local.databricks_delegation` and `network_security_group = { id = ... }` on `host` and `container`; Bicep `delegation: 'Microsoft.Databricks/workspaces'`). The delegation lets Databricks manage the subnets' network policy and add its required NSG rules itself.
3. **The NSG starts empty and must stay out of Databricks' way.** Databricks writes its rules into the NSG (with back-end Private Link, five rules: worker-to-worker in and out, and outbound to `Sql` 3306, `Storage` 443 and `EventHub` 9093). The Terraform AVM NSG module ignores changes to security rules, so it never removes them. The Bicep AVM NSG module always sends `securityRules: []`, so the Bicep version declares the NSG as a plain resource with no properties, as Microsoft's Databricks VNet-injection quickstart template does. That works for the first deployment, but a redeployment still sends an NSG with no rules, and Azure rejects it (see Known issue).
4. **VNet injection and SCC are four parameters** (`custom_parameters.virtual_network_id`, `public_subnet_name`, `private_subnet_name`, `no_public_ip = true`; Bicep `customVirtualNetworkResourceId`, `customPublicSubnetName`, `customPrivateSubnetName`, `disablePublicIp: true`). Without `no_public_ip`, every cluster node would get a public IP and the control plane would connect in; with it, nodes connect out to the relay on 443.
5. **Egress is explicit** (`module "nat_gateway"`, and `nat_gateway = { id = ... }` on both subnets). New VNets have no default outbound access, so without the NAT gateway (or routes to a firewall) clusters can't reach the relay and fail to start. StandardV2 is zone-redundant and needs a StandardV2 public IP; that IP is the clusters' stable egress address for allow lists.
6. **Back-end Private Link changes the NSG rules** (`subresource_name = "databricks_ui_api"` in the spoke's `snet-pe`, and `network_security_group_rules_required = local.required_nsg_rules`). With the endpoint, cluster-to-control-plane traffic uses Private Link and Databricks drops its outbound `AzureDatabricks` rule (`NoAzureDatabricksRules`); without it, `AllRules`. Public network access stays on so users can still reach the UI.
7. **Private endpoints only work with DNS** (`private_dns_zone_resource_ids` on each endpoint; Bicep `privateDnsZoneGroup`). The zone group writes the workspace's A record (`adb-<id>.<n>`) into `privatelink.azuredatabricks.net`, and the zone must be linked to every VNet whose clients resolve the name. In a landing zone those zones are central (chapter 9) and policy creates the zone groups; `private_dns_zone_ids` takes them, and the code only creates the zones you don't pass.
8. **The lake is private and identity-only** (`is_hns_enabled = true`, `public_network_access_enabled = false`, `shared_access_key_enabled = false`, `dfs` and `blob` endpoints). Clusters reach it through the endpoints; Unity Catalog reaches it as the access connector's managed identity, which has Storage Blob Data Contributor. Register the connector (`access_connector_id` output) as a storage credential in Unity Catalog to use it.
9. **Destroy has a Databricks-specific step.** The workspace owns a managed resource group with a deny assignment, so you can't delete that group yourself while the workspace exists, and a normal workspace delete keeps the Unity Catalog workspace catalog. `az databricks workspace delete --force-deletion` (or `az group delete --force-deletion-types Microsoft.Databricks/workspaces`) removes both.

### AVM choices

- Terraform: `avm-res-databricks-workspace` (0.5.0) deploys the workspace through `azapi` (API version 2026-01-01) and creates the private endpoints and the access connector. Two quirks are handled in `main.tf`. It reads the resource group with a data source, so the module call has `depends_on`; otherwise the first apply fails because the group doesn't exist at plan time. And it insists on NSG association IDs, though the AVM VNet module sets the NSG as a subnet property with no separate association resource, so the subnet IDs are passed in their place (the module only checks they're set).
- Bicep: `avm/res/databricks/workspace` (0.12.0) uses API version 2024-05-01 and defaults `disablePublicIp` to `false`, so it's set explicitly. The access connector is its own module (`avm/res/databricks/access-connector`). The NSG is a plain resource (point 3).
- There is no AVM pattern module for a Databricks workload landing zone, so resource modules are composed here.

## Versions

| Component | Version |
|---|---|
| Terraform | `~> 1.13` (validated with 1.13.4) |
| `Azure/avm-res-resources-resourcegroup/azurerm` | `0.4.0` |
| `Azure/avm-res-network-virtualnetwork/azurerm` (and `//modules/peering`) | `0.22.2` |
| `Azure/avm-res-network-networksecuritygroup/azurerm` | `0.6.0` |
| `Azure/avm-res-network-natgateway/azurerm` | `0.3.2` |
| `Azure/avm-res-network-privatednszone/azurerm` | `0.5.0` |
| `Azure/avm-res-databricks-workspace/azurerm` | `0.5.0` |
| `Azure/avm-res-storage-storageaccount/azurerm` | `0.10.0` |
| `hashicorp/azurerm` provider | `~> 4.81` (locked 4.81.0; the Databricks module requires < 5.0) |
| `Azure/azapi` provider | `~> 2.13` (locked 2.13.0) |
| `Azure/modtm`, `hashicorp/random`, `hashicorp/time` providers | locked 0.4.0, 3.9.1, 0.14.2 |
| Bicep CLI | 0.48.1 |
| `br/public:avm/res/network/virtual-network` | `0.10.2` |
| `br/public:avm/res/network/nat-gateway` | `2.1.1` |
| `br/public:avm/res/network/private-dns-zone` | `0.8.1` |
| `br/public:avm/res/databricks/workspace` | `0.12.0` |
| `br/public:avm/res/databricks/access-connector` | `0.4.3` |
| `br/public:avm/res/storage/storage-account` | `0.33.1` |
| `Microsoft.Network/networkSecurityGroups` (plain resource) | API `2025-05-01` |

## References

- VNet injection (VNet and subnet requirements, delegation, NSG rules, permissions, explicit outbound after 31 March 2026): https://learn.microsoft.com/azure/databricks/security/network/classic/vnet-inject
- Secure cluster connectivity (`enableNoPublicIp`, NAT gateway for egress, SCC to become mandatory): https://learn.microsoft.com/azure/databricks/security/network/classic/secure-cluster-connectivity
- Private Link concepts (front-end, back-end, serverless; required NSG rules and public access per option; `browser_authentication`): https://learn.microsoft.com/azure/databricks/security/network/concepts/privatelink-concepts
- Classic compute plane (back-end) Private Link: https://learn.microsoft.com/azure/databricks/security/network/classic/private-link-standard
- Inbound (front-end) Private Link and the private web auth workspace: https://learn.microsoft.com/azure/databricks/security/network/front-end/front-end-private-connect
- Delete a workspace (soft delete, workspace catalog retention, `--force-deletion`, `--force-deletion-types`): https://learn.microsoft.com/azure/databricks/admin/workspace/delete-workspace
- Access connector and Unity Catalog storage access: https://learn.microsoft.com/azure/databricks/connect/unity-catalog/cloud-storage/azure-managed-identities
- Databricks units and billing: https://learn.microsoft.com/azure/databricks/getting-started/concepts and https://learn.microsoft.com/azure/databricks/lakehouse-architecture/cost-optimization/best-practices
- NAT Gateway SKUs (StandardV2 needs StandardV2 public IPs, same price as Standard, regions without StandardV2): https://learn.microsoft.com/azure/nat-gateway/nat-sku and https://learn.microsoft.com/azure/nat-gateway/manage-nat-gateway-v2
- Default outbound access: https://learn.microsoft.com/azure/virtual-network/ip-services/default-outbound-access
- Microsoft's quickstart template (NSG declared with no properties): https://github.com/Azure/azure-quickstart-templates/tree/master/quickstarts/microsoft.databricks/databricks-all-in-one-template-for-vnet-injection-with-nat-gateway
- Terraform modules: https://registry.terraform.io/modules/Azure/avm-res-databricks-workspace/azurerm/0.5.0 (and the other `avm-res-*` pages)
- Bicep modules: https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/databricks
