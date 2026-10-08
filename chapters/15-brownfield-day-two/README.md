# Chapter 15: Brownfield and day two

Companion code for the "Build it" section of chapter 15. It takes three resources that were built by hand (a resource group, an NSG and a VNet), brings them under code with Terraform `import` blocks or a Bicep deployment stack, and then watches them for drift on a schedule.

| Folder | What it is |
| --- | --- |
| `import/` | `create-unmanaged.sh` builds the "brownfield" resources with the Azure CLI only; `simulate-drift.sh` makes portal-style changes to them afterwards (and `--undo` reverses them). |
| `terraform/` | `imports.tf`: three `import` blocks. `main.tf`: the configuration `terraform plan -generate-config-out` produced for them, cleaned up. |
| `bicep/` | `main.bicep` (subscription scope: the resource group) and `modules/network.bicep` (NSG and VNet): the exported, decompiled and cleaned template, deployed as a **deployment stack** to adopt the resources. |
| `drift/github/drift-terraform.yml` | GitHub Actions: scheduled `terraform plan -detailed-exitcode` with OIDC (chapter 13's plan identity); opens or updates an issue on drift (exit code 2) and closes it when the drift is gone. |
| `drift/github/drift-bicep.yml` | The same for Bicep: scheduled `az deployment sub what-if`, issue on any Create, Delete or Modify. |
| `drift/whatif-reader-role.json` | Custom role the what-if check needs (Reader can't run what-if). |

Everything here is free: resource groups, VNets, NSGs, deployment stacks and role definitions have no charge. The workflows use GitHub Actions minutes.

Tested: not yet

## The brownfield transition this code supports

CAF's transition guidance for an existing estate (*Transition an existing Azure environment to the Azure landing zone reference architecture*) runs, in outline:

1. **Assess** what exists: subscriptions, management groups, policy and role assignments, networks.
2. **Deploy the landing zone alongside it** in the same tenant (chapters 6-13), so nothing existing changes yet. Learn's recommended approach duplicates the landing zone management groups with every policy assignment in **audit only** mode (`enforcementMode: DoNotEnforce`), so workload teams can see their compliance without being blocked.
3. **Move subscriptions** under the right management group (a subscription move keeps resource IDs; a resource move changes them, so Learn favours moving subscriptions), first into the audit-only copy, then, once compliant, into Corp or Online with policy enforced.
4. **Remediate** what the audit shows.
5. **Bring the resources under code**, so the platform team and the workload team can change them through pull requests and see drift. This is the step this chapter's code covers.
6. **Keep it there**: drift detection on a schedule, and, for Bicep, deny settings on the stack.

## Prerequisites

- Azure CLI signed in (`az login`; 2.61 or later for deployment stacks). Terraform 1.13 or later; Bicep CLI 0.48 or later.
- A test subscription. **Contributor** is enough for the resources and for a deployment stack with `--deny-settings-mode none`; a stack with deny settings needs the **Azure Deployment Stack Owner** role (or Owner) at the stack's scope.
- For the drift workflows: chapter 13's identities and state storage (`state_storage_enabled = true`), and the GitHub repository variables chapter 13 set up. The plan identity must be able to read the brownfield subscription: it inherits Reader if the subscription sits under the management group chapter 13 granted Reader on; otherwise add Reader on the subscription.
- For the Bicep drift workflow: permission to create a custom role and assign it (Owner or User Access Administrator on the subscription).

Do the Terraform path and the Bicep path one at a time: destroy (or detach) after one before adopting the same resources with the other.

## 1. Create the brownfield

```bash
cd chapters/15-brownfield-day-two
bash import/create-unmanaged.sh <subscription-id>            # optional: [prefix] [location]
```

It creates `rg-alz-brownfield-uksouth`, `nsg-alz-brownfield-uksouth` (one rule, `allow-https-from-vnet`) and `vnet-alz-brownfield-uksouth` (`10.20.0.0/24`, subnet `snet-app` `10.20.0.0/26` using the NSG, no default outbound access), and prints their resource IDs.

## 2a. Adopt with Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # subscription_id (and prefix/location if you changed them)
terraform init
```

**See what Terraform generates.** `main.tf` is already the cleaned-up result. To see the raw output, move it aside so the three import targets have no configuration, and let Terraform write it:

```bash
mv main.tf main.tf.cleaned
terraform plan -generate-config-out=generated.tf
```

`generated.tf` has one resource block per import, with every argument the provider read from Azure, including empty and default values, literal names, and the NSG's full resource ID as a string in the subnet. HashiCorp marks configuration generation as experimental; the file must not exist beforehand, and Terraform may write arguments that conflict, in which case it reports an error and you remove one of them. Compare it with `main.tf.cleaned` (`diff generated.tf main.tf.cleaned`), then put the cleaned file back:

```bash
rm generated.tf
mv main.tf.cleaned main.tf
```

The clean-up, as done in `main.tf`: literal values replaced with locals and references (the subnet's `security_group = azurerm_network_security_group.app.id`), arguments at their defaults or empty removed, read-only values (`id`, `guid`) removed, and the inline security rule and subnet written as blocks. Whatever is left must describe exactly what's in Azure.

**Import:**

```bash
terraform plan -out tfplan      # expect: Plan: 3 to import, 0 to add, 0 to change, 0 to destroy.
terraform apply tfplan
terraform plan                  # expect: No changes.
```

If the second plan shows changes, the cleaned configuration doesn't match Azure; fix the code (not Azure) until the plan is clean. After the apply, the import blocks have done their job: delete `imports.tf`, or keep it as a record of where the resources came from.

**Moving into AVM modules later.** The adopted resources are plain `azurerm` resources. To move them into AVM modules (which use other resource types, mostly `azapi_resource`), `moved` blocks can't help: they only move between addresses of the same resource type. Instead, add a `removed` block (`lifecycle { destroy = false }`) for each old address, so Terraform forgets it without deleting it, and an `import` block for each new module address, and apply both in one plan.

**Destroy:**

```bash
terraform destroy
```

This deletes the resource group, the VNet and the NSG: once adopted, they're Terraform's. To stop managing them without deleting them, use `removed` blocks (`lifecycle { destroy = false }`) or `terraform state rm` instead.

## 2b. Adopt with Bicep and a deployment stack

**Export and decompile** (what produced `bicep/modules/network.bicep` before clean-up):

```bash
az group export --name rg-alz-brownfield-uksouth > exported.json
az bicep decompile --file exported.json      # writes exported.bicep
```

The portal can export Bicep directly (resource group > Export template > Bicep). Learn's Bicep export page says Bicep can only be exported from the portal; the Azure CLI 2.91 used here also has `az group export --export-format bicep`. Either way, Learn is clear that an export is a starting point, not a production template: it's generated from the published schemas, includes properties you wouldn't set, parameterises names without defaults and hard-codes most values.

The clean-up, as done in `modules/network.bicep`: generated parameter names (in the style `virtualNetworks_vnet_alz_brownfield_uksouth_name`) and hard-coded IDs replaced with parameters and symbolic references (`networkSecurityGroup: { id: nsg.id }`), read-only properties (`provisioningState`, `resourceGuid`, `etag`) removed, any child resources that repeat an inline array removed so each subnet and rule is declared once, and default values dropped. The export covers the resources *in* the group, not the group itself, so `main.bicep` adds the resource group at subscription scope and calls the module.

**Adopt into a stack.** Creating a deployment stack from a template that describes existing resources deploys the same definitions over them (nothing changes) and records each one as **managed** by the stack:

```bash
cd bicep
az deployment sub what-if --location uksouth --name ch15-check --parameters main.bicepparam
# expect: three resources, "NoChange" (or only noise; see the drift section)

az stack sub create --name ch15-brownfield --location uksouth \
  --template-file main.bicep --parameters main.bicepparam \
  --action-on-unmanage detachAll --deny-settings-mode none --yes

az stack sub show --name ch15-brownfield --query "resources[].{id:id, status:status}" -o table
```

`--action-on-unmanage` decides what happens to a resource the stack stops managing (removed from the template, or the stack deleted):

| Value | Effect |
| --- | --- |
| `detachAll` | Resources and resource groups are left in Azure, no longer managed. **Use this while adopting**: a mistake in the template detaches rather than deletes. |
| `deleteResources` | Resources are deleted; resource groups are detached. |
| `deleteAll` | Resources and resource groups are deleted. Use it once the template is the source of truth and removing a resource from code should remove it from Azure. |

**Stop drift at the source** with deny settings: `--deny-settings-mode denyWriteAndDelete` (or `denyDelete`) puts a deny assignment on the managed resources, so changes made outside the stack fail. Exclude the pipeline identity and a break-glass group with `--deny-settings-excluded-principals` (at most five principals; use groups for more). Deny settings apply to control-plane operations only, and need the Azure Deployment Stack Owner role.

**Clean up:**

```bash
az stack sub delete --name ch15-brownfield --action-on-unmanage deleteAll --yes
```

`deleteAll` deletes the managed resource group with the VNet and NSG. With `detachAll` instead, the stack goes and the resources stay (then `az group delete --name rg-alz-brownfield-uksouth --yes`).

## 3. Drift detection

### Terraform (`drift/github/drift-terraform.yml`)

1. **State in the shared backend.** The workflow uses chapter 13's state storage with the key `ch15-brownfield.tfstate`. Do the import against that backend, or move local state there:

   ```bash
   printf 'terraform {\n  backend "azurerm" {}\n}\n' > ci_backend.tf
   terraform init -migrate-state \
     -backend-config="resource_group_name=<BACKEND_RESOURCE_GROUP>" \
     -backend-config="storage_account_name=<BACKEND_STORAGE_ACCOUNT>" \
     -backend-config="container_name=tfstate" \
     -backend-config="key=ch15-brownfield.tfstate" \
     -backend-config="use_azuread_auth=true"
   ```

2. Copy the workflow to `.github/workflows/drift-terraform.yml`. It uses the same repository variables as chapter 13 (`AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_CLIENT_ID_PLAN`, `BACKEND_*`), plus `BROWNFIELD_SUBSCRIPTION_ID` if the resources are in a different subscription.
3. Scheduled workflows run on the default branch, so the OIDC subject is `repo:<org>/<repo>:ref:refs/heads/main`, which chapter 13's plan identity (Reader) already trusts. No new identity or credential.
4. Test it: `bash ../import/simulate-drift.sh <subscription-id>`, then run the workflow (Actions > drift-terraform > Run workflow, or `gh workflow run drift-terraform.yml`). The plan exits 2 and an issue **Drift detected: chapters/15-brownfield-day-two/terraform** opens with the plan: the extra NSG rule to be removed and the tag to be set back. Revert (`terraform apply`, or `simulate-drift.sh ... --undo`), run the workflow again, and it closes the issue.

### Bicep (`drift/github/drift-bicep.yml`)

What-if needs `Microsoft.Resources/deployments/*` as well as read access (Learn: what-if has the same permission requirements as a deployment), and Reader doesn't have it. With `--validation-level ProviderNoRbac`, what-if checks only *read* access to the resources, so a small custom role is enough:

```bash
SUB=<subscription-id>
sed "s/00000000-0000-0000-0000-000000000000/$SUB/" drift/whatif-reader-role.json > /tmp/whatif-role.json
az role definition create --role-definition @/tmp/whatif-role.json
az role assignment create --assignee-object-id <plan identity principal ID> --assignee-principal-type ServicePrincipal \
  --role "Deployment What-If Reader" --scope /subscriptions/$SUB
```

Copy the workflow to `.github/workflows/drift-bicep.yml` and test it the same way. It runs `az deployment sub what-if --result-format FullResourcePayloads --no-pretty-print`, keeps changes that aren't `NoChange` or `Ignore` (ignoring a `Modify` whose property changes are all `NoEffect`), and opens, updates or closes the issue **Drift detected: chapters/15-brownfield-day-two/bicep**.

Why not `--result-format ResourceIdOnly`? With it, what-if reports a resource that exists and is in the template as **Deploy**, because it doesn't compare properties: every run would look the same, drift or not.

**Noise.** Deployment what-if compares the template with the resources as Azure returns them, and resource providers add defaults and computed values the template doesn't set, so some `Modify` results aren't real changes. The cleaned template states the values the brownfield script set, to keep noise down; the deploy test shows whether any remains. **Deployment stacks** have a what-if of their own that filters noise against a baseline recorded at each stack deployment (stacks created or updated on or after 13 August 2026):

```bash
az stack-whatif sub create --name ch15-drift --location uksouth \
  --stack-id $(az stack sub show --name ch15-brownfield --query id -o tsv) \
  --template-file main.bicep --parameters main.bicepparam \
  --action-on-unmanage detachAll --deny-settings-mode none --retention-interval PT3H
```

It creates a what-if *result resource* (`Microsoft.Resources/deploymentStacksWhatIfResults`) rather than returning an operation result, and needs `Microsoft.Resources/deploymentStacksWhatIfResults/write`. The retention interval is documented inconsistently: Learn says `PT1H` to `PT3H` (and uses `PT3H`, as above), while the Azure CLI 2.91 help says between 1 and 30 days; if the CLI rejects `PT3H`, use `P1D`. The workflow uses deployment what-if because its JSON output is documented; switch to the stack what-if when you've confirmed its output format in your tenant.

## Inputs

| Terraform variable | Bicep parameter | Script argument | Default | Meaning |
| --- | --- | --- | --- | --- |
| `subscription_id` | (the `az account set` subscription) | 1st | none | Subscription with the brownfield resources |
| `prefix` | `prefix` | 2nd | `alz` | Name prefix |
| `location` | `location` | 3rd | `uksouth` | Region |

The workflows take repository variables (listed at the top of each file).

## Cost

Nothing billable: resource groups, VNets, subnets, NSGs, deployment stacks, custom roles and role assignments have no charge. The workflows run on GitHub-hosted runners and use your plan's Actions minutes (two short jobs per weekday as scheduled). The state file lives in chapter 13's storage account.

## How it works

The chapter's Build it text is written from these points.

1. **An import block is a plan-time instruction** (`import { to = azurerm_virtual_network.brownfield, id = "/subscriptions/.../virtualNetworks/vnet-..." }`). The ID is the Azure resource ID, built from variables; Terraform reads the resource during plan and shows "to import" next to any change it would make. Unlike the old `terraform import` command, it's code: reviewed in a pull request, planned before anything happens, applied with everything else.
2. **Generated configuration is a draft** (`terraform plan -generate-config-out=generated.tf`). It's exact (every attribute Azure returned) and therefore noisy; the useful work is turning literals into references and deleting defaults, while keeping the plan at "0 to change".
3. **"No changes" after import is the test** (`terraform plan` after `apply`). Any difference means the code doesn't describe what's in Azure, and the next apply would change production. Fix the code, not Azure.
4. **Inline collections make the code the whole truth** (`security_rule` blocks in the NSG, `subnet` blocks in the VNet). A rule or subnet added in the portal is then something Terraform would remove, so it shows up as drift. The cost: never mix inline subnets with separate `azurerm_subnet` resources for the same VNet.
5. **Export and decompile are the Bicep equivalent of generated config** (`az group export`, `az bicep decompile`), with the same clean-up job and the same test: what-if should show no changes.
6. **A deployment stack is Bicep's state** (`az stack sub create ... --action-on-unmanage detachAll --deny-settings-mode none`). Deploying the template as a stack records the resources as managed; `detachAll` keeps adoption safe; `deleteAll` and deny settings come once the template is trusted.
7. **Drift is a plan that isn't empty** (`terraform plan -detailed-exitcode`: 0 no changes, 1 error, 2 changes). The workflow keeps Terraform's exit code (`terraform_wrapper: false`, `set +e`), fails the run on 1 and turns 2 into an issue, so drift becomes a tracked piece of work instead of a red build nobody reads.
8. **Read-only identity, schedule subject** (`on: schedule`, `permissions: id-token: write, issues: write`). The scheduled run's token subject is the main branch, which chapter 13's Reader identity already trusts; detecting drift needs no write access to Azure. Fixing it goes through the normal pull request and apply.
9. **What-if needs more than Reader, and the right result format** (`--validation-level ProviderNoRbac`, `--result-format FullResourcePayloads`). The custom role adds `Microsoft.Resources/deployments/*` to read access; full payloads are what let what-if report `Modify` instead of an uninformative `Deploy`.

## Versions

| Component | Version |
| --- | --- |
| Terraform | `~> 1.13` (validated with 1.13.4) |
| `hashicorp/azurerm` provider | `~> 5.8` (locked 5.8.0) |
| Resources (Terraform) | `azurerm_resource_group`, `azurerm_network_security_group`, `azurerm_virtual_network` (plain resources; see `main.tf` for why) |
| Bicep CLI | 0.48.1 |
| Resource API versions (Bicep) | `Microsoft.Resources/resourceGroups@2025-04-01`, `Microsoft.Network/networkSecurityGroups@2025-05-01`, `Microsoft.Network/virtualNetworks@2025-05-01` |
| Azure CLI | 2.91.0 (deployment stacks need 2.61.0 or later) |
| GitHub Actions | `actions/checkout@v7`, `azure/login@v3`, `hashicorp/setup-terraform@v4`, `actions/upload-artifact@v7`, `actions/github-script@v9` (workflows checked with actionlint 1.7.12) |

## References

- Transition an existing Azure environment to the Azure landing zone reference architecture (moving resources and subscriptions, policy effects): https://learn.microsoft.com/azure/cloud-adoption-framework/ready/enterprise-scale/transition
- Transition by duplicating a landing zone management group with policies in audit only mode: https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/align-approach-duplicate-brownfield-audit-only
- Brownfield on-ramp and alignment scenarios: https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/landing-zone-journey
- Export a template with the Azure CLI (limitations, parameter options): https://learn.microsoft.com/azure/azure-resource-manager/templates/export-template-cli
- Export Bicep from the portal (limitations): https://learn.microsoft.com/azure/azure-resource-manager/bicep/export-bicep-portal
- Decompile ARM JSON to Bicep (`az bicep decompile`, export and convert): https://learn.microsoft.com/azure/azure-resource-manager/bicep/decompile
- Deployment stacks (`az stack sub create`, `--action-on-unmanage`, deny settings, excluded principals, built-in roles): https://learn.microsoft.com/azure/azure-resource-manager/bicep/deployment-stacks
- Deployment stack what-if and noise reduction: https://learn.microsoft.com/azure/azure-resource-manager/bicep/deployment-stacks-what-if and https://learn.microsoft.com/azure/azure-resource-manager/bicep/deployment-stacks-what-if-noise-reduction
- Bicep what-if (permissions, `--validation-level`, result formats, `Deploy` with ResourceIdOnly, noise): https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-what-if
- Terraform import blocks: https://developer.hashicorp.com/terraform/language/block/import
- Terraform generated configuration (experimental, conflicting arguments): https://developer.hashicorp.com/terraform/language/import/generating-configuration
- Chapter 13 (identities, OIDC subjects, state storage): `../13-platform-automation/README.md`
