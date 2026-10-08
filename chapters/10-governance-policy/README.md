# Chapter 10: Governance at scale with Azure Policy

Companion code for the "Build it" section of chapter 10. It's a small, complete policy-as-code example at a test management group of its own, so it can be deployed and removed without chapter 6's hierarchy.

```
<parent> (tenant root group by default)
└── alz-policytest                  test management group
      ├── alz-require-rg-tag        custom definition: resource groups need a costCentre tag (Audit/Deny)
      ├── alz-guardrails            custom initiative: the custom definition + built-in "Allowed locations"
      ├── alz-guardrails            assignment of the initiative, DoNotEnforce, with non-compliance messages
      ├── alz-loc-waiver            exemption (Waiver, expires) from the allowed-locations member only
      ├── alz-inherit-tag           assignment of the built-in Modify policy "Inherit a tag from the
      │                             resource group if missing", system-assigned managed identity
      ├── role assignment           Contributor for that identity at alz-policytest
      └── remediation task          optional (off by default)
```

The names start with the `prefix` input (default `alz`).

| Folder | What it is |
| --- | --- |
| `lib/require-rg-tag.policy.json` | The custom policy definition as data. Both versions load this one file. |
| `terraform/` | Terraform root module with plain `azurerm` policy resources. It also creates the test management group. |
| `bicep/` | Bicep deployment at management group scope: raw resources for the definition and initiative, AVM modules for the assignments, exemption and remediation. It deploys **into an existing** management group (create it with the CLI first, below). |

Tested: 8 October 2026 (Terraform 1.13.4, Bicep CLI 0.48.1, Azure CLI 2.91.0): Terraform apply with the defaults under the tenant root group (8 resources), then with `create_remediation_task = true`, and destroy; Bicep deployment (also with `createRemediationTask = true`) and every clean-up command below, in a test tenant. The remediation task was created and completed with nothing to remediate (no subscriptions under the group); remediation of real resources and `Default` enforcement weren't tested, because no subscription was placed under the test group.

## Prerequisites

- **A test tenant, or a parent management group you can experiment under.** Nothing here moves a subscription. Don't move production subscriptions under `alz-policytest`: with `enforcement_mode = "Default"` the initiative can deny deployments (if you also choose `Deny`), and the Modify assignment adds tags to resources in every subscription below it.
- **Azure CLI**, signed in with `az login` to the target tenant. Terraform: the `azurerm` provider needs a subscription to start, and takes the CLI's default (`az account set --subscription <id>`); nothing is deployed into it.
- **Permissions** on the parent management group (for Bicep, on `alz-policytest` once it exists):
  - create the management group: Management Group Contributor (or Owner) on the parent;
  - definitions, initiative, assignments, exemption and remediation: Resource Policy Contributor (or Owner);
  - the policy identity's role assignment: Owner, User Access Administrator or Role Based Access Control Administrator, because it writes a role assignment;
  - Bicep: permission to create deployments at the management group (Owner covers it).

  Owner on the parent covers everything. On a brand-new tenant see chapter 6's README for elevating access and getting a role at the tenant root group.
- **Licences:** none. Azure Policy and management groups need no licence.
- **Tools:** Terraform 1.13 or later; Bicep CLI 0.48 or later (or Azure CLI with Bicep); Azure CLI 2.53.0 or later to deploy a `.bicepparam` file.

## Deploy and destroy: Terraform

```bash
cd chapters/10-governance-policy/terraform
cp terraform.tfvars.example terraform.tfvars   # optional: every input has a default
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

To test under chapter 6's hierarchy instead of the tenant root group, set `parent_management_group_id = "alz"`.

If the first apply stops with a transient error such as `CheckAccessPrincipalTokenInvalid` on the exemption or a reset connection on the role assignment, run `terraform apply` again (without the saved plan); it creates only what is missing.

Destroy:

```bash
terraform destroy
```

This removes, in dependency order: the remediation task (if created), the role assignment, the exemption, both assignments, the initiative, the definition and finally the management group. If the management group delete fails because Azure still reports a child for a few seconds, run `terraform destroy` again.

## Deploy and destroy: Bicep

Creating a management group is a tenant-level operation, and a tenant-scope deployment needs permissions at `/` (chapter 6's README explains). So the Bicep version takes an existing management group and the CLI creates it:

```bash
cd chapters/10-governance-policy/bicep

# 1. The test management group (omit --parent for the tenant root group; --parent alz for chapter 6's hierarchy)
az account management-group create --name alz-policytest --display-name "Policy test (alz)" --parent <parent-mg-id>

# 2. Everything else, deployed at that management group
az deployment mg what-if --management-group-id alz-policytest --location uksouth --name ch10-policy --parameters main.bicepparam
az deployment mg create  --management-group-id alz-policytest --location uksouth --name ch10-policy --parameters main.bicepparam
```

`--location` is where the deployment record is stored and the default for the policy identity's region. If the first deployment fails because the new management group or definitions aren't visible yet ("out of scope", "not found"), wait a few minutes and run the same `create` again; it is idempotent. If a re-run then fails on the Modify assignment's role assignment with `RoleAssignmentUpdateNotPermitted`, the assignment got a new managed identity in between (this can happen straight after a failed first run) and the AVM module's role assignment name doesn't change with the principal: delete the Contributor role assignment whose principal no longer matches `az policy assignment show --name alz-inherit-tag --scope /providers/Microsoft.Management/managementGroups/alz-policytest --query identity.principalId` (list them with `az role assignment list --scope /providers/Microsoft.Management/managementGroups/alz-policytest`) and run `create` again.

**`exemptionExpiresOn` defaults to 30 days after the deployment runs, so every redeployment with the default moves the expiry.** Set it in `main.bicepparam` for a fixed date.

Bicep has no destroy. Remove things in this order (Bash):

```bash
PREFIX=alz
MG=$PREFIX-policytest
SCOPE=/providers/Microsoft.Management/managementGroups/$MG

# 1. Remediation task, only if you set createRemediationTask = true
az policy remediation delete --name $PREFIX-inherit-tag-remediation --management-group $MG

# 2. Exemption
az policy exemption delete --name $PREFIX-loc-waiver --scope $SCOPE

# 3. The Modify identity's role assignment (before its assignment, while the principal ID can be read)
PRINCIPAL=$(az policy assignment show --name $PREFIX-inherit-tag --scope $SCOPE --query identity.principalId -o tsv)
IDS=$(az role assignment list --scope $SCOPE --query "[?principalId=='$PRINCIPAL'].id" -o tsv)
[ -n "$IDS" ] && az role assignment delete --ids $IDS

# 4. Assignments
az policy assignment delete --name $PREFIX-inherit-tag --scope $SCOPE
az policy assignment delete --name $PREFIX-guardrails --scope $SCOPE

# 5. Initiative, then definition
az policy set-definition delete --name $PREFIX-guardrails --management-group $MG
az policy definition delete --name $PREFIX-require-rg-tag --management-group $MG

# 6. The management group (it must have no children or subscriptions)
az account management-group delete --name $MG
```

An initiative can't be deleted while an assignment uses it, and a definition can't be deleted while an initiative references it, hence the order. If you delete the assignment first by mistake, the role assignment is left behind with a principal that no longer exists: find it with `az role assignment list --scope $SCOPE` and delete it by ID.

## Remediation task

The Modify assignment only changes resources when they're created or updated, and only in `Default` enforcement mode. Existing resources are fixed by a **remediation task**, which runs the Modify operations with the assignment's managed identity. Remediation tasks can be started even when the assignment is `DoNotEnforce`.

Both versions can create one (`create_remediation_task` / `createRemediationTask`), but it's **off by default**:

- Learn's guidance for an assignment at **management group** scope is to create the remediation task after compliance has been evaluated, not together with the assignment (that shortcut is for subscription-scope assignments).
- With no subscriptions under `alz-policytest` there is nothing to remediate.
- Azure deletes remediation tasks 60 days after their last change, so a task kept in Terraform state later shows up as needing to be created again.

Run it by hand once the assignment has been evaluated (the Terraform output `remediation_command` prints this with the real IDs):

```bash
az policy remediation create \
  --name alz-inherit-tag-remediation \
  --management-group alz-policytest \
  --policy-assignment /providers/Microsoft.Management/managementGroups/alz-policytest/providers/Microsoft.Authorization/policyAssignments/alz-inherit-tag

# Progress and result
az policy remediation show --name alz-inherit-tag-remediation --management-group alz-policytest
```

To see it change something, place a test subscription under `alz-policytest`, create a resource group with a `costCentre` tag and a resource in it without one, wait for a compliance scan (or start one in that subscription with `az policy state trigger-scan`), then run the command above. For an initiative assignment you'd add `--definition-reference-id <referenceId>`, because a remediation task works on one policy at a time.

## Inputs

| Terraform | Bicep | Default | Notes |
| --- | --- | --- | --- |
| `prefix` | `prefix` | `alz` | 1-10 characters. Assignment and exemption names at management group scope are limited to 24 characters. |
| `parent_management_group_id` | n/a (CLI `--parent`) | tenant root group | ID, not resource ID. |
| `location` | `location` | `uksouth` / deployment location | Region recorded for the Modify assignment's managed identity. |
| `enforcement_mode` | `enforcementMode` | `DoNotEnforce` | Applies to both assignments. |
| `required_tag_name` | `requiredTagName` | `costCentre` | The tag resource groups must have, and the tag resources inherit. |
| `guardrail_effect` | `guardrailEffect` | `Audit` | `Audit` or `Deny`, for both policies in the initiative. |
| `allowed_locations` | `allowedLocations` | `uksouth`, `ukwest` | Allowed locations built-in. It ignores resource groups and resources in `global`. |
| `exemption_expires_on` | `exemptionExpiresOn` | 30 days ahead | UTC ISO 8601. Terraform fixes the default at the first apply (`time_offset`). |
| `create_remediation_task` | `createRemediationTask` | `false` | See above. |
| n/a | `enableTelemetry` | `true` | AVM usage telemetry. No cost. |

### Enforcement mode

`DoNotEnforce` (the default here) still evaluates every resource and reports compliance, but Deny doesn't block, Modify doesn't change anything on create or update, and no Activity log entries are written for the effect. Manual remediation tasks still work. Learn's safe deployment practice is to assign in `DoNotEnforce`, check the compliance results, then switch to `Default`. Azure Policy also has an `Enroll` mode (the effect is enforced only for resources enrolled in the assignment); the `azurerm` resource here exposes enforcement as a true/false switch, so this example uses only `Default` and `DoNotEnforce`.

## Cost

Nothing here is billed: management groups, policy definitions, initiatives, assignments, exemptions, remediation tasks, role assignments and the system-assigned managed identity carry no charge, and Azure Policy is free for Azure resources. The Modify policy only edits tags. Cost could only come from subscriptions you place under the test management group, and from what you deploy in them.

## How it works

The lines the chapter's Build it text is written from:

1. **The definition is data** (`lib/require-rg-tag.policy.json`, loaded with `jsondecode(file(...))` in Terraform and `loadJsonContent(...)` in Bicep). The rule matches `type == Microsoft.Resources/subscriptions/resourceGroups` and `tags[<tagName>]` not existing, and its effect is `"[parameters('effect')]"`, so one definition serves Audit and Deny. Keeping definitions as JSON files in the repository is the "policy as code" part: they're reviewed in pull requests like any other code.
2. **Where it's stored.** `management_group_id = azurerm_management_group.test.id` (Bicep: the deployment's management group). A custom definition can be assigned at or below the management group it's stored on. Here it lives on the test group so it's removed with it; in a real hierarchy it goes on the intermediate root (chapter 6).
3. **The initiative wires parameters through.** It declares its own `tagName`, `effect` and `listOfAllowedLocations` parameters, and each `policy_definition_reference` passes them on with `"[parameters('...')]"`. The built-in is referenced by its fixed ID, `/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c` (from Learn's built-in list), and the `reference_id` values (`requireRgTag`, `allowedLocations`) are what messages, exemptions and remediation tasks point at.
4. **The assignment sets values and messages.** `parameters` fills the initiative parameters; `enforce = var.enforcement_mode == "Default"` (Bicep `enforcementMode`) controls the effect; `non_compliance_message` without a reference ID is the default text, and the ones with `policy_definition_reference_id` replace it for one member. That message is what a developer sees in a Deny error.
5. **The exemption is narrow and temporary.** `exemption_category = "Waiver"`, `expires_on`, and `policy_definition_reference_ids = ["allowedLocations"]`: only the location rule is waived, the tag rule still applies. An expired exemption isn't deleted, it just stops being honoured, which keeps the record for audit. In real use the exemption sits on a child scope (a subscription or resource group); here it's on the assignment's own scope so it can be tested with no subscriptions.
6. **Modify needs an identity and a role.** `identity { type = "SystemAssigned" }` plus `location`, then `azurerm_role_assignment` for each ID in `data.azurerm_policy_definition_built_in.inherit_tag.role_definition_ids` (the definition's `then.details.roleDefinitionIds`, Contributor for this policy). Only the portal grants these roles automatically; from code you must. Bicep can't read the definition at build time, so `main.bicep` lists the role and the AVM module (`roleDefinitionIds`) creates the role assignment.
7. **Remediation is a separate, later action** (`azurerm_management_group_policy_remediation` / `avm/ptn/policy-insights/remediation`, both behind a switch, or `az policy remediation create`). It runs once over existing non-compliant resources, one policy at a time.

### Why plain resources in Terraform

The Terraform AVM module for this, `Azure/avm-ptn-policyassignment/azurerm` (0.2.0, December 2024), requires `azurerm ~> 3.74`, which can't be combined with the current `azurerm` 5.x provider, and it covers only assignments. There's no AVM Terraform module for definitions or initiatives. The `azurerm` policy resources are short enough that showing them teaches the structure directly. In Bicep there's no AVM module for policy definitions or initiatives either, so those two are raw resources; the assignments, exemption and remediation use the AVM pattern modules.

## Versions

Checked against the Terraform registry and the Microsoft Container Registry on 7 October 2026.

| Component | Version |
| --- | --- |
| Terraform | `~> 1.13` (validated with 1.13.4) |
| Provider `hashicorp/azurerm` | `~> 5.8` (locked 5.8.0) |
| Provider `hashicorp/time` | `~> 0.14` (locked 0.14.2) |
| Bicep CLI | 0.48.1 |
| `br/public:avm/ptn/authorization/policy-assignment` | 0.5.3 |
| `br/public:avm/ptn/authorization/policy-exemption` | 0.2.0 |
| `br/public:avm/ptn/policy-insights/remediation` | 0.1.0 |
| Resource API versions (Bicep raw resources) | `Microsoft.Authorization/policyDefinitions` and `policySetDefinitions` 2025-01-01 |
| Built-in definitions | Allowed locations 1.1.0 (`e56962a6-4747-49cd-b67b-bf8b01975c4c`); Inherit a tag from the resource group if missing 1.0.0 (`ea3f2387-9b95-492a-a190-fcdc54f7b070`) |

## References

- Built-in policy definitions (IDs and versions): https://learn.microsoft.com/azure/governance/policy/samples/built-in-policies
- Policy definition structure: https://learn.microsoft.com/azure/governance/policy/concepts/definition-structure-basics
- Initiative definition structure: https://learn.microsoft.com/azure/governance/policy/concepts/initiative-definition-structure
- Assignment structure (enforcement mode, non-compliance messages): https://learn.microsoft.com/azure/governance/policy/concepts/assignment-structure
- Exemption structure (categories, expiry, reference IDs): https://learn.microsoft.com/azure/governance/policy/concepts/exemption-structure
- Remediate non-compliant resources (identity roles, management group remediation timing): https://learn.microsoft.com/azure/governance/policy/how-to/remediate-resources
- Remediation task structure (60-day deletion, one definition per task): https://learn.microsoft.com/azure/governance/policy/concepts/remediation-structure
- `az policy remediation`: https://learn.microsoft.com/cli/azure/policy/remediation
- Tag policies: https://learn.microsoft.com/azure/azure-resource-manager/management/tag-policies
- Safe deployment of Azure Policy assignments: https://learn.microsoft.com/azure/governance/policy/how-to/policy-safe-deployment-practices
- Adopt policy-driven guardrails (enforcement mode and remediation by effect): https://learn.microsoft.com/azure/cloud-adoption-framework/ready/enterprise-scale/dine-guidance
- Design Azure Policy as Code workflows: https://learn.microsoft.com/azure/governance/policy/concepts/policy-as-code
- Built-in definition source files (linked from Learn's built-in list): https://github.com/Azure/azure-policy/blob/master/built-in-policies/policyDefinitions/General/AllowedLocations_Deny.json and https://github.com/Azure/azure-policy/blob/master/built-in-policies/policyDefinitions/Tags/InheritTag_Add_Modify.json
- `azurerm` provider 5.8.0 docs: https://registry.terraform.io/providers/hashicorp/azurerm/5.8.0/docs
- `Azure/avm-ptn-policyassignment/azurerm`: https://registry.terraform.io/modules/Azure/avm-ptn-policyassignment/azurerm/0.2.0
- Bicep modules: https://github.com/Azure/bicep-registry-modules/tree/main/avm/ptn/authorization/policy-assignment, https://github.com/Azure/bicep-registry-modules/tree/main/avm/ptn/authorization/policy-exemption, https://github.com/Azure/bicep-registry-modules/tree/main/avm/ptn/policy-insights/remediation
