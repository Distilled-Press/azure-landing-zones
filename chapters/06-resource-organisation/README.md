# Chapter 6: Resource organisation

Companion code for the "Build it" section of chapter 6. It builds the Azure landing zone management group hierarchy and assigns the ALZ archetype policies to it.

```
Tenant root group (or the parent you choose)
└── alz                      Azure Landing Zones (intermediate root)
    ├── alz-platform         Platform
    │   ├── alz-security     Security
    │   ├── alz-management   Management
    │   ├── alz-identity     Identity
    │   └── alz-connectivity Connectivity
    ├── alz-landingzones     Landing zones
    │   ├── alz-corp         Corp
    │   ├── alz-online       Online
    │   └── alz-local        Local
    ├── alz-sandbox          Sandbox
    └── alz-decommissioned   Decommissioned
```

The IDs start with the `prefix` input (default `alz`). Local is included because the current ALZ library (platform/alz 2026.10.0) has it in its reference architecture.

No subscriptions are moved into the hierarchy. Subscription placement is chapter 7.

| Folder | What it deploys |
| --- | --- |
| `terraform/` | The hierarchy plus the **full** ALZ policy set from the library: 149 custom policy definitions, 43 custom initiatives and 5 custom role definitions on the intermediate root, 123 policy assignments across the archetypes, and the role assignments their managed identities need. |
| `bicep/` | The same hierarchy plus a **subset** of the ALZ policies (12 assignments, 3 custom definitions, 2 custom initiatives), copied unchanged from the same library release. See [Bicep and the full policy set](#bicep-and-the-full-policy-set). |

Tested: 7 October 2026 (Terraform 1.13.4): Terraform apply (533 resources, enforcement DoNotEnforce) and destroy in a test tenant. Bicep: not yet.

## Prerequisites

- **A test tenant, or a parent management group you can experiment under.** Both versions create management groups and policy at management group scope. Don't move production subscriptions under the test hierarchy: in `Default` enforcement mode the deny policies block deployments, and deployIfNotExists/modify policies deploy resources into the subscriptions in their scope.
- **Azure CLI**, signed in with `az login` to the target tenant, with a subscription selected (`az account set --subscription <id>`). The Terraform providers and the Bicep deployment use that sign-in; there are no secrets in the code.
- **Permissions.** Owner on the parent management group (creating management groups, policy and the role assignments for policy managed identities needs Owner, or a combination such as Management Group Contributor, Resource Policy Contributor and User Access Administrator). On a new tenant nobody has a role on the tenant root group until a Global Administrator elevates access, which grants User Access Administrator at root scope `/`, and then assigns one:
  ```bash
  # after "Access management for Azure resources" is turned on in Microsoft Entra ID > Properties
  az role assignment create --assignee "<your-user-or-service-principal-object-id>" --scope "/" --role "Owner"
  ```
  The Bicep version is a **tenant-scope** deployment, which needs permission at `/` itself (Learn: *Tenant deployments with Bicep file*, "Required access"). Remove the elevated access when you've finished.
- **Licences:** none. Management groups and Azure Policy need no licence.
- **Tools:** Terraform 1.12 or later (validated with 1.13.4). Bicep CLI 0.48.1 or later, and Azure CLI 2.53.0 or later to deploy a `.bicepparam` file.

## Terraform

Built on the AVM pattern module `Azure/avm-ptn-alz/azurerm` and the `Azure/alz` provider, the pair the ALZ Terraform accelerator's platform landing zone template uses.

```bash
cd chapters/06-resource-organisation/terraform
cp terraform.tfvars.example terraform.tfvars   # optional: every input has a default
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

At plan time the ALZ provider downloads the library into `.alzlib/` (git-ignored) and reads the built-in policy definitions from Azure to work out which roles each policy identity needs, so the first plan is slower than usual.

### Changing the prefix

The management group IDs come from `lib/architecture_definitions/alz_custom.alz_architecture_definition.json`. The ALZ provider reads that file before Terraform plans anything, so it can't be generated in the same run. A small helper rewrites it:

```bash
terraform -chdir=set-prefix init
terraform -chdir=set-prefix apply -var prefix=mylz
terraform plan -var prefix=mylz -out tfplan
```

The helper only writes a local file. Don't run `terraform destroy` in `set-prefix/` (it would delete the architecture file); run the helper again with `-var prefix=alz` to go back. If `var.prefix` and the file disagree, the plan stops with an error that says so.

### Destroy

```bash
terraform destroy
```

This removes the policy role assignments, policy assignments, custom role definitions, initiatives, definitions and finally the management groups, in dependency order. If a delete fails on Azure's eventual consistency (for example a management group that still reports children a few seconds after they were deleted), run `terraform destroy` again.

## Bicep

Built on the AVM pattern module `br/public:avm/ptn/alz/empty`, which the ALZ Bicep accelerator calls once per management group. `main.bicep` calls it twelve times: the intermediate root at the parent's scope, and each child at its parent's scope with a `dependsOn` on the parent.

```bash
cd chapters/06-resource-organisation/bicep
az deployment tenant what-if --name ch06-alz --location uksouth --parameters main.bicepparam
az deployment tenant create  --name ch06-alz --location uksouth --parameters main.bicepparam
```

`--location` is where the deployment record is stored, not where anything is deployed. To override one value without editing the file, add `--parameters prefix=mylz` after the `.bicepparam` file. The AVM module adds short "wait" deployments before each step to ride out ARM eventual consistency, so the deployment takes a while.

### Destroy (Bicep)

Bicep has no destroy. Remove things in this order: the policy assignments (and the role assignments held by their managed identities), then the custom initiatives, then the custom definitions, then the management groups from the bottom up. A management group can only be deleted when it has no child management groups or subscriptions. Bash:

```bash
PREFIX=alz
CHILDREN_FIRST="$PREFIX-corp $PREFIX-online $PREFIX-local \
  $PREFIX-security $PREFIX-management $PREFIX-identity $PREFIX-connectivity \
  $PREFIX-landingzones $PREFIX-platform $PREFIX-sandbox $PREFIX-decommissioned $PREFIX"

# 1. Policy assignments, and the role assignments held by their managed identities
for MG in $CHILDREN_FIRST; do
  SCOPE="/providers/Microsoft.Management/managementGroups/$MG"
  for PA in $(az policy assignment list --scope "$SCOPE" --query "[].name" -o tsv); do
    PRINCIPAL=$(az policy assignment show --name "$PA" --scope "$SCOPE" --query "identity.principalId" -o tsv)
    if [ -n "$PRINCIPAL" ]; then
      IDS=$(az role assignment list --scope "$SCOPE" --query "[?principalId=='$PRINCIPAL'].id" -o tsv)
      [ -n "$IDS" ] && az role assignment delete --ids $IDS
    fi
    az policy assignment delete --name "$PA" --scope "$SCOPE"
  done
done

# 2. Custom initiatives, then custom definitions (all on the intermediate root)
for SET in Enforce-ALZ-Sandbox Enforce-ALZ-Decomm; do
  az policy set-definition delete --name "$SET" --management-group "$PREFIX"
done
for DEF in Deny-Subnet-Without-Nsg Deny-VNET-Peer-Cross-Sub Deploy-Vm-autoShutdown; do
  az policy definition delete --name "$DEF" --management-group "$PREFIX"
done

# 3. Management groups, children first
for MG in $CHILDREN_FIRST; do
  az account management-group delete --name "$MG"
done

# 4. Optional: the tenant-level deployment record
az deployment tenant delete --name ch06-alz
```

The commands are the same if you deployed under a parent other than the tenant root group.

### Bicep and the full policy set

There's no single AVM Bicep module that deploys the whole ALZ architecture from the library the way `avm-ptn-alz` does in Terraform. The AVM Bicep pattern modules for ALZ are `avm/ptn/alz/empty` (one management group with its definitions, assignments and role assignments) and `avm/ptn/alz/ama`. **The full ALZ policy set in Bicep comes from the ALZ Bicep accelerator** (`Azure/alz-bicep-accelerator`, `templates/core/governance`), which ships the whole library as JSON files and loads them per management group with `loadJsonContent()`.

This chapter takes the same approach on a small scale. `bicep/lib/` holds 17 files copied unchanged from platform/alz 2026.10.0, at least one for each archetype that has assignments:

| Management group | Assignments (library name) |
| --- | --- |
| Intermediate root | Audit-ResourceRGLocation, Deny-Classic-Resources, Deploy-AzActivity-Log (deployIfNotExists) |
| Identity | Deny-Public-IP, Deny-Subnet-Without-Nsg |
| Landing zones | Deny-IP-forwarding, Deny-Storage-http, Deny-Subnet-Without-Nsg |
| Corp | Deny-HybridNetworking, Deny-Public-IP-On-NIC |
| Local | Enforce-ALDO-Services |
| Sandbox | Enforce-ALZ-Sandbox (custom initiative) |
| Decommissioned | Enforce-ALZ-Decomm (custom initiative, includes deployIfNotExists) |

Platform, Security, Management, Connectivity and Online get no assignments in this subset (in the library itself Security, Management and Online have none). For the complete set use the accelerator, or the Terraform version here.

## Inputs

| Terraform | Bicep | Default | Notes |
| --- | --- | --- | --- |
| `prefix` | `prefix` | `alz` | Management group ID prefix. Terraform: run the `set-prefix` helper too. |
| `parent_management_group_id` | `parentManagementGroupId` | tenant root group | ID only, not the resource ID. |
| `location` | `location` | `uksouth` | Region of the policy assignments' managed identities. The hierarchy itself has no region. |
| `policy_assignment_enforcement_mode` | `policyAssignmentEnforcementMode` | `DoNotEnforce` | See below. |
| `policy_default_values` | `logAnalyticsWorkspaceResourceId` | library placeholders | See below. |
| `enable_telemetry` | `enableTelemetry` | `true` | AVM usage telemetry. No cost. |

### Enforcement mode

`DoNotEnforce` is the default because this is a test-friendly example. In that mode Azure Policy still evaluates and reports compliance, but doesn't deny anything, doesn't write Activity log entries for the effect and doesn't run deployIfNotExists/modify deployments when resources are created or updated. Remediation tasks can still be started by hand.

`Default` keeps whatever enforcement mode each library assignment ships with: most enforce, but the library itself ships the `Enforce-GR-*` guardrail initiatives and a few others as `DoNotEnforce`. In Terraform, `Enable-DDoS-VNET` stays `DoNotEnforce` unless you supply `ddos_protection_plan_id`, because the library's own note says to do that when you don't use DDoS Network Protection.

A real rollout usually goes the same way round: assign in `DoNotEnforce`, check the compliance results, then switch to `Default` (Learn: *Safe deployment of Azure Policy assignments*).

### Parameters that need platform resources

Some ALZ assignments take resource IDs: a Log Analytics workspace (Deploy-AzActivity-Log, Deploy-Diag-LogsCat, Deploy-MDFC-Config-H224, Deploy-AzSqlDb-Auditing), data collection rules and a user-assigned identity for the Azure Monitor Agent policies, private DNS zones (Deploy-Private-DNS-Zones), a DDoS protection plan (Enable-DDoS-VNET) and a security contact email.

This example deploys **none** of those resources. The library ships every such parameter with a placeholder in subscription `00000000-0000-0000-0000-000000000000`, and the assignments are created with those values. The Terraform module skips any policy role assignment whose scope contains the all-zero subscription ID, so nothing tries to grant a role on a resource that doesn't exist, and with `DoNotEnforce` nothing tries to deploy to them.

In a real deployment the management resources (chapter 12) and connectivity resources (chapter 8) are deployed first and their IDs passed in:

- **Terraform:** `policy_default_values`, keyed by the library's default names (`log_analytics_workspace_id`, `ama_user_assigned_managed_identity_id`, `ama_user_assigned_managed_identity_name`, `ama_vm_insights_data_collection_rule_id`, `ama_change_tracking_data_collection_rule_id`, `ama_mdfc_sql_data_collection_rule_id`, `ddos_protection_plan_id`, `private_dns_zone_subscription_id`, `private_dns_zone_resource_group_name`, `private_dns_zone_region`, `email_security_contact` and the rest of `alz_policy_default_values.json`). One value fills every assignment that uses it. The resources must exist before you apply, because the module grants the policy identities roles on them. The module's own examples build these IDs with `provider::azapi::resource_group_resource_id(...)` from literal names, so the ALZ data source can read them at plan time.
- **Bicep:** `logAnalyticsWorkspaceResourceId` for the one assignment in the subset that needs it. The policy identity gets its roles at the assignment's management group, which covers a workspace whose subscription sits under that management group. The accelerator uses a `parPolicyAssignmentParameterOverrides` object per management group for the rest.

## Cost

Nothing in this chapter is billed. Management groups, policy definitions, initiatives, assignments, custom role definitions and role assignments carry no charge, and Azure Policy is free for Azure resources. The managed identities created for policy assignments are free.

Cost can come later from the policies acting on subscriptions placed under the hierarchy: in `Default` mode the root archetype's `Deploy-MDFC-Config-H224` configures Microsoft Defender for Cloud plans, and the deployIfNotExists policies deploy diagnostic settings, agents and backup configuration that bill through the services they target. This example places no subscriptions, and its default is `DoNotEnforce`.

## How it works

The lines a reader needs to understand, and why:

1. **`provider "alz" { library_references = [{ custom_url = "${path.root}/lib" }] }`** (`terraform/terraform.tf`) with **`"dependencies": [{ "path": "platform/alz", "ref": "2026.10.0" }]`** (`terraform/lib/alz_library_metadata.json`). The policy content isn't in this repo. It comes from a versioned release of the Azure landing zones library; the local library adds only an architecture definition and names the release it builds on. Upgrading the ALZ policies is a change to one `ref`.
2. **The architecture definition** (`terraform/lib/architecture_definitions/alz_custom.alz_architecture_definition.json`). Twelve entries, each with an `id`, a `parent_id` and a list of `archetypes` (`root`, `platform`, `landing_zones`, `corp` and so on). This file *is* the hierarchy: archetypes, not org charts or environments, decide where a management group sits and which policies it gets.
3. **`module "alz" { source = "Azure/avm-ptn-alz/azurerm" ... architecture_name = "alz_custom", parent_resource_id = ... }`** (`terraform/main.tf`). One module call creates every management group, deploys the custom definitions to the intermediate root, assigns each archetype's policies and creates the role assignments for policies that deploy or modify resources.
4. **`data "alz_architecture" "inventory"` and `local.enforcement_overrides`** (`terraform/main.tf`). Reads the same architecture to list every assignment name per management group, then builds `policy_assignments_to_modify` so one variable switches all of them to `DoNotEnforce`. It follows the library version automatically instead of hard-coding 123 names.
5. **`policy_default_values`** (`terraform/main.tf`). How platform resource IDs reach the policies: one named default fills the same parameter in every assignment that uses it.
6. **`targetScope = 'tenant'`** and **`module intRoot 'br/public:avm/ptn/alz/empty:0.3.6' = { scope: managementGroup(parentManagementGroupId) ... }`** (`bicep/main.bicep`). Management groups are tenant resources, so the deployment runs at tenant scope; each management group is created by a module deployed at its parent's scope, and children depend on their parent.
7. **`loadJsonContent('lib/...alz_policy_assignment.json')`** with **`fixScopes()`** and **`toPolicyAssignment()`** (`bicep/main.bicep`). The library files are used unchanged; the functions replace the library's placeholder management group name with the intermediate root and apply the enforcement mode, parameter overrides and policy identity roles.
8. **Custom definitions live on the intermediate root** (`managementGroupCustomPolicyDefinitions` on `intRoot` only in Bicep; the `root` archetype in the library). Every management group below can assign them, and nothing is put on the tenant root group.

## Versions

Checked against the Terraform registry, the Microsoft Container Registry and GitHub on 7 October 2026.

| Component | Version |
| --- | --- |
| Terraform module `Azure/avm-ptn-alz/azurerm` | 0.22.0 |
| Provider `Azure/alz` | 0.22.0 (`~> 0.22`) |
| Provider `Azure/azapi` | 2.13.0 (`~> 2.13`) |
| Providers pulled in by the module (lock file) | `Azure/modtm` 0.4.0, `hashicorp/random` 3.9.1, `hashicorp/time` 0.14.2 |
| Provider `hashicorp/local` (set-prefix helper only) | 2.9.1 (`~> 2.9`) |
| Azure landing zones library | platform/alz 2026.10.0 |
| Bicep module `br/public:avm/ptn/alz/empty` | 0.3.6 |
| Terraform / Bicep CLI used to validate | 1.13.4 / 0.48.1 |

## References

- Management groups (ALZ resource organisation design area): https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/resource-org-management-groups
- What is an Azure landing zone? (hierarchy diagram): https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/
- Platform landing zone implementation options: https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/implementation-options
- Deploy Azure landing zones: https://learn.microsoft.com/azure/architecture/landing-zones/landing-zone-deploy
- Root management group: https://learn.microsoft.com/azure/governance/management-groups/overview
- Elevate access: https://learn.microsoft.com/azure/role-based-access-control/elevate-access-global-admin
- Delete a management group: https://learn.microsoft.com/azure/governance/management-groups/manage#delete-a-management-group
- Policy assignment enforcement mode: https://learn.microsoft.com/azure/governance/policy/concepts/assignment-structure#enforcement-mode
- Safe deployment of Azure Policy assignments: https://learn.microsoft.com/azure/governance/policy/how-to/policy-safe-deployment-practices
- Tenant deployments with Bicep: https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-to-tenant
- Bicep parameters files: https://learn.microsoft.com/azure/azure-resource-manager/bicep/parameter-files
- `avm-ptn-alz` module (registry docs and examples): https://registry.terraform.io/modules/Azure/avm-ptn-alz/azurerm/0.22.0
- ALZ provider: https://registry.terraform.io/providers/Azure/alz/0.22.0/docs
- `avm/ptn/alz/empty` module: https://github.com/Azure/bicep-registry-modules/tree/main/avm/ptn/alz/empty
- Azure landing zones library: https://github.com/Azure/Azure-Landing-Zones-Library (tag platform/alz/2026.10.0)
- ALZ Terraform accelerator platform landing zone template: https://github.com/Azure/alz-terraform-accelerator/tree/main/templates/platform_landing_zone
- ALZ Bicep accelerator governance templates: https://github.com/Azure/alz-bicep-accelerator/tree/main/templates/core/governance
