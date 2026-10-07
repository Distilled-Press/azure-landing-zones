# Chapter 5: Identity and access

Companion code for the "Build it" section of chapter 5: the platform RBAC model at management group scope.

- `terraform/`: Terraform version (`azurerm` resources)
- `bicep/`: Bicep version (Azure Verified Modules)

Tested: 7 October 2026 (Terraform 1.13.4, Bicep CLI 0.48.1, Azure CLI 2.91.0): Terraform apply and destroy, Bicep deployment and the clean-up commands, in a test tenant. PIM-eligible assignments not tested (they need Microsoft Entra ID P2 or ID Governance).

## What it builds

Against the chapter 6 management group hierarchy (`alz` intermediate root, `alz-platform`, `alz-landingzones`, `alz-corp`; the IDs chapter 6 builds with the default `alz` prefix):

**(a) Two custom role definitions at the intermediate root**, assignable at `alz` and everything below it. Both reuse the custom roles the Azure landing zone reference architecture ships (the ALZ library's `Application-Owners` and `Network-Management`):

| Role | Actions | NotActions | Why a custom role |
| --- | --- | --- | --- |
| Landing Zone Application Owner (`alz`) | `*` | `Microsoft.Authorization/*/write`, `Microsoft.Network/publicIPAddresses/write`, `Microsoft.Network/virtualNetworks/write`, `Microsoft.KeyVault/locations/deletedVaults/purge/action` | Contributor lets a workload team create public IPs and change the spoke virtual network the platform team vended. No built-in role is "Contributor minus networking edges". Chapter 7 assigns this role at subscription scope. |
| Network Management (`alz`) | `*/read`, `Microsoft.Network/*`, `Microsoft.Resources/deployments/*`, `Microsoft.Support/*` | none | The built-in Network Contributor already has `Microsoft.Network/*`, deployments and support tickets, but it can't read resources of other providers. Network operations need to see the virtual machines, firewalls and private endpoints attached to the networks they run; `*/read` adds that view and nothing that changes them. |

**(b) Built-in and custom roles assigned to Microsoft Entra groups at management group scopes:**

| Group | Role | Scope |
| --- | --- | --- |
| Platform team | Owner | `alz-platform` (active, or PIM-eligible if PIM is on) |
| Workload team | Contributor | `alz-corp` |
| Security operations | Security Reader | `alz` |
| Network operations (optional) | Network Management (custom) | `alz` |

**(c) Optional PIM-eligible assignments**, behind `enable_pim_eligible_assignments` / `enablePimEligibleAssignments` (default `false`):

- the platform team's Owner at `alz-platform` becomes **eligible** instead of active;
- the platform team gets **eligible** Contributor at `alz-landingzones`, for troubleshooting workload landing zones without standing access.

Eligible assignments last 365 days by default (`pim_eligibility_duration_days` / `pimEligibilityDuration`).

### Why plain `azurerm` resources in the Terraform version

The Bicep version uses AVM modules (`avm/ptn/authorization/role-definition`, `avm/res/authorization/role-assignment/mg-scope`, `avm/ptn/authorization/pim-role-assignment`). The Terraform version uses `azurerm_role_definition`, `azurerm_role_assignment` and `azurerm_pim_eligible_role_assignment` directly, because the AVM Terraform option, `Azure/avm-res-authorization-roleassignment/azurerm` 0.3.1:

- doesn't create custom role definitions (it only references existing ones), so half this chapter would still be plain resources;
- looks groups up through the `azuread` provider (Microsoft Graph), which adds Graph read permissions to the deploying identity even when you pass object IDs;
- pins `azurerm` below 5.0, while this repository uses `azurerm` 5.x;
- has no PIM-eligible assignments.

Four resource types, each a few lines, also teach the model more plainly than a map-of-maps module input.

## Prerequisites

- **The management groups exist.** Chapter 6 builds them. To test this chapter on its own, create empty ones (management groups cost nothing) and delete them afterwards:

  ```bash
  az account management-group create --name alz --display-name "alz"
  az account management-group create --name alz-platform --display-name "Platform" --parent alz
  az account management-group create --name alz-landingzones --display-name "Landing zones" --parent alz
  az account management-group create --name alz-corp --display-name "Corp" --parent alz-landingzones
  ```

- **Microsoft Entra security groups** for the platform team, a workload team, security operations and (optionally) network operations. You need their **object IDs**: `az ad group show --group "<display name>" --query id -o tsv`.
- **Azure roles for the deploying identity at the intermediate root (`alz`):**
  - Terraform: **Owner** or **User Access Administrator** (custom roles need `Microsoft.Authorization/roleDefinitions/write`; assignments and PIM requests need `Microsoft.Authorization/roleAssignments/write` and `roleEligibilityScheduleRequests/write`).
  - Bicep: **Owner**, because the deployment also needs `Microsoft.Resources/deployments/*` at each management group it targets, which User Access Administrator doesn't have.
- **Licences:** none for (a) and (b). **PIM (c) needs Microsoft Entra ID P2 or Microsoft Entra ID Governance** licences for every user who is eligible (here, every member of the platform team group) and for anyone who approves activations. If the licence lapses, eligible assignments are removed.
- **PIM role settings:** the eligible assignments are time-bound (365 days) because Learn says permanent eligibility works only if the role management policy at that scope allows it. If your PIM settings cap eligible assignments at less than 365 days, lower the duration.
- Azure CLI signed in (`az login`); Terraform `~> 1.13` or the Bicep CLI.

## Deploy

### Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # then edit the group object IDs
terraform init
terraform plan
terraform apply
```

### Bicep

Deploy at the intermediate root; the custom roles are created there and the role assignment modules target the child management groups:

```bash
cd bicep
# edit main.bicepparam first
az deployment mg what-if \
  --management-group-id alz \
  --location uksouth \
  --name ch05-platform-rbac \
  --parameters main.bicepparam

az deployment mg create \
  --management-group-id alz \
  --location uksouth \
  --name ch05-platform-rbac \
  --parameters main.bicepparam
```

To turn PIM on, set `enable_pim_eligible_assignments = true` (Terraform) or `enablePimEligibleAssignments = true` (Bicep) and apply again. The active Owner assignment for the platform team is removed and the eligible one created; check the eligible assignment exists before you rely on it.

## Destroy

Role assignments must go before the custom roles they use: Azure won't delete a role definition that still has assignments.

### Terraform

```bash
cd terraform
terraform destroy
```

Terraform removes the assignments (PIM eligibility through an `AdminRemove` request) and then the role definitions.

### Bicep

Deleting the deployment record doesn't remove anything, so remove the pieces with the CLI, in this order:

```bash
MG=/providers/Microsoft.Management/managementGroups

# 1. Active role assignments
az role assignment delete --assignee <platform-team-object-id> --role "Owner"           --scope $MG/alz-platform
az role assignment delete --assignee <workload-team-object-id> --role "Contributor"     --scope $MG/alz-corp
az role assignment delete --assignee <security-ops-object-id>  --role "Security Reader" --scope $MG/alz
az role assignment delete --assignee <network-ops-object-id>   --role "Network Management (alz)" --scope $MG/alz

# 2. PIM-eligible assignments (only if you enabled them): one AdminRemove request each
az rest --method put \
  --url "https://management.azure.com$MG/alz-platform/providers/Microsoft.Authorization/roleEligibilityScheduleRequests/$(uuidgen)?api-version=2020-10-01" \
  --body "{\"properties\":{\"principalId\":\"<platform-team-object-id>\",\"roleDefinitionId\":\"$MG/alz-platform/providers/Microsoft.Authorization/roleDefinitions/8e3af657-a8ff-443c-a75c-2fe8c4bcb635\",\"requestType\":\"AdminRemove\"}}"
az rest --method put \
  --url "https://management.azure.com$MG/alz-landingzones/providers/Microsoft.Authorization/roleEligibilityScheduleRequests/$(uuidgen)?api-version=2020-10-01" \
  --body "{\"properties\":{\"principalId\":\"<platform-team-object-id>\",\"roleDefinitionId\":\"$MG/alz-landingzones/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c\",\"requestType\":\"AdminRemove\"}}"

# 3. Custom role definitions
# Role assignments take a minute or so to disappear everywhere. If a role definition
# is deleted too soon the command can report success and leave it in place, so
# wait, delete, then check with:
#   az role definition list --custom-role-only true --scope $MG/alz --query "[].roleName" -o tsv
# (and delete any survivor by its ID: az role definition delete --name <guid> --scope $MG/alz)
sleep 60
az role definition delete --name "Landing Zone Application Owner (alz)" --scope $MG/alz --custom-role-only true
az role definition delete --name "Network Management (alz)"             --scope $MG/alz --custom-role-only true

# 4. Optional: the deployment record
az deployment mg delete --management-group-id alz --name ch05-platform-rbac
```

In PowerShell, `New-AzRoleEligibilityScheduleRequest ... -RequestType AdminRemove` does step 2.

If you created test management groups, delete them last, children first:

```bash
az account management-group delete --name alz-corp
az account management-group delete --name alz-landingzones
az account management-group delete --name alz-platform
az account management-group delete --name alz
```

## Inputs

| Terraform | Bicep | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `prefix` | `prefix` | no | `alz` | Suffix in custom role names, which must be unique in the tenant |
| `intermediate_root_management_group_id` | (deployment scope) | no | `alz` | Intermediate root; custom roles live here. Bicep takes it from `--management-group-id` |
| `platform_management_group_id` | `platformManagementGroupId` | no | `alz-platform` | Platform management group |
| `landing_zones_management_group_id` | `landingZonesManagementGroupId` | no | `alz-landingzones` | Landing zones management group (PIM only) |
| `workload_management_group_id` | `workloadManagementGroupId` | no | `alz-corp` | Where the workload team gets Contributor |
| `platform_team_group_object_id` | `platformTeamGroupObjectId` | yes | none | Platform team group object ID |
| `workload_team_group_object_id` | `workloadTeamGroupObjectId` | yes | none | Workload team group object ID |
| `security_ops_group_object_id` | `securityOpsGroupObjectId` | yes | none | Security operations group object ID |
| `network_ops_group_object_id` | `networkOpsGroupObjectId` | no | `null` / `''` | Network operations group object ID; empty skips the assignment |
| `enable_pim_eligible_assignments` | `enablePimEligibleAssignments` | no | `false` | Use PIM-eligible assignments (Entra ID P2 or ID Governance) |
| `pim_eligibility_duration_days` | `pimEligibilityDuration` | no | `365` / `P365D` | Length of the eligibility |
| n/a | `pimStartTime` | no | `utcNow()` | Start of the eligibility window |
| `subscription_id` | n/a | no | `null` | Subscription the `azurerm` provider connects through (nothing is deployed in it) |
| n/a | `enableTelemetry` | no | `true` | AVM usage telemetry |

## What it costs to leave running

Nothing in Azure: role definitions, role assignments and management groups aren't billed. PIM is licensed per user through Microsoft Entra ID P2 or ID Governance, not billed by Azure.

## Versions

| Component | Version |
| --- | --- |
| Terraform | `~> 1.13` (validated with 1.13.4) |
| `hashicorp/azurerm` provider | `~> 5.8` (lock file: 5.8.0) |
| Bicep CLI | built with 0.48.1 |
| `br/public:avm/ptn/authorization/role-definition` | 0.1.1 |
| `br/public:avm/res/authorization/role-assignment/mg-scope` | 0.1.2 |
| `br/public:avm/ptn/authorization/pim-role-assignment` | 0.1.2 |

## How it works

These are the lines the chapter's Build it text explains.

1. **A custom role lives at the intermediate root, and that is also its only assignable scope.** A custom role can name only one management group in `assignableScopes`; putting it at `alz` makes it usable in every management group, subscription and resource group below.

   ```hcl
   scope             = local.intermediate_root_id
   assignable_scopes = [local.intermediate_root_id]
   ```

   Neither role has `DataActions`: custom roles with `DataActions` can't be assigned at management group scope.

2. **`not_actions` is subtraction, not deny.** Application Owner is `*` minus four operations. Learn is explicit that `NotActions` isn't a deny rule: if the same person also holds a role that grants one of those operations, they can perform it. Assign Application Owner *instead of* Contributor, not alongside it; enforcement that holds whatever the role comes from Azure Policy (chapter 10).

3. **The role definition ID is stable.** `uuidv5("url", "<intermediate root>/application-owner")` in Terraform, and the AVM module's `guid(name)` in Bicep, give the same GUID on every run, so a re-deploy updates the role rather than creating a duplicate.

4. **Assign to groups, set `principal_type = "Group"`.** People join and leave the Microsoft Entra group; the role assignment never changes. Setting the principal type explicitly is required when the deploying identity's own right to assign roles is constrained by a condition on principal type (delegated role assignment with conditions, which CAF recommends for workload teams).

5. **Scope decides the blast radius.** Owner at `alz-platform` covers the Security, Management, Identity and Connectivity subscriptions but not workload landing zones. Contributor at `alz-corp` covers every Corp landing zone. Security Reader at `alz` covers the whole estate, which is what a security operations team needs for a horizontal view.

6. **Eligible is a different resource type, not a flag.** An active assignment is `Microsoft.Authorization/roleAssignments`; an eligible one is a `Microsoft.Authorization/roleEligibilityScheduleRequests` request with `requestType: AdminAssign` and a schedule:

   ```hcl
   resource "azurerm_pim_eligible_role_assignment" "platform_team_owner" {
     scope              = local.platform_id
     role_definition_id = "${local.platform_id}${local.role_id.owner}"
     principal_id       = var.platform_team_group_object_id
     schedule {
       expiration { duration_days = var.pim_eligibility_duration_days }
     }
   }
   ```

   The same `count` switch turns off the active Owner assignment when PIM is on, so the platform team holds Owner only after activating it.

7. **No standing access to workload landing zones.** With PIM on, the platform team gets only *eligible* Contributor at `alz-landingzones`: they activate it to troubleshoot, which follows CAF's recommendation to use PIM when platform administrators need access to workload landing zones.

## Notes on the sources

- **Network operations scope.** CAF's example role assignment table puts Network Operations at "All subscriptions", while the ALZ library and CAF's custom role table describe the role as platform-wide. This code assigns it once at the intermediate root, which covers all subscriptions under the hierarchy.
- **Custom role names.** The ALZ library names its roles `Application-Owners` and `Network-Management`; CAF's table calls them "Application Owner" and "Network management (NetOps)". This code uses "Landing Zone Application Owner (alz)" and "Network Management (alz)" so that they don't collide with the copies the ALZ pattern module in chapter 6 can deploy. In a real estate, deploy these roles from one place only.

## References

- Landing zone identity and access management (custom roles and example assignments): https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/identity-access-landing-zones
- Management groups: custom role definition and assignment limits: https://learn.microsoft.com/azure/governance/management-groups/overview#azure-custom-role-definition-and-assignment
- Azure built-in roles (role IDs): https://learn.microsoft.com/azure/role-based-access-control/built-in-roles
- Network Contributor role permissions: https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/networking#network-contributor
- Understand Azure role definitions (NotActions isn't a deny rule): https://learn.microsoft.com/azure/role-based-access-control/role-definitions#notactions
- Eligible and time-bound role assignments in Azure RBAC: https://learn.microsoft.com/azure/role-based-access-control/pim-integration
- Assign Azure resource roles in PIM (ARM API, permanent eligibility note): https://learn.microsoft.com/entra/id-governance/privileged-identity-management/pim-resource-roles-assign-roles
- Configure Azure resource role settings in PIM: https://learn.microsoft.com/entra/id-governance/privileged-identity-management/pim-resource-roles-configure-role-settings
- Microsoft Entra ID Governance licensing fundamentals (PIM): https://learn.microsoft.com/entra/id-governance/licensing-fundamentals#privileged-identity-management
- Manage management groups (create, delete): https://learn.microsoft.com/azure/governance/management-groups/manage
- ALZ library custom roles (`platform/alz/role_definitions`): https://github.com/Azure/Azure-Landing-Zones-Library
- `azurerm_pim_eligible_role_assignment`: https://registry.terraform.io/providers/hashicorp/azurerm/5.8.0/docs/resources/pim_eligible_role_assignment
- `azurerm_role_definition`: https://registry.terraform.io/providers/hashicorp/azurerm/5.8.0/docs/resources/role_definition
- AVM Bicep modules: https://github.com/Azure/bicep-registry-modules/tree/main/avm/ptn/authorization
