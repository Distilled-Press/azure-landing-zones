# The Azure Landing Zones IaC Accelerator: inputs for a minimal run

These files are the inputs for the Azure Landing Zones IaC Accelerator, Microsoft's tool that bootstraps a version control system, pipelines and Azure identities and then deploys a platform landing zone from them. **Nothing here has been run**: the accelerator creates real repositories, identities and (for most scenarios) billable networking, so this folder documents the run rather than performing it.

| File | Use |
| --- | --- |
| `inputs-github.yaml` | Bootstrap inputs for Terraform with GitHub (`bootstrap_module_name: alz_github`). |
| `inputs-local.yaml` | Bootstrap inputs for Terraform with the local file system (`alz_local`): for another version control system, or to inspect the generated code first. |

Both are based on the accelerator's own examples (`templates/platform_landing_zone/examples/bootstrap/` in `Azure/alz-terraform-accelerator`) with placeholders in `<angle brackets>` and all-zero GUIDs. The second configuration file the accelerator needs, the platform landing zone file (`platform-landing-zone.tfvars`), is generated for you in step 2 below.

Versions checked on 7 October 2026: ALZ PowerShell module 7.1.5 (PowerShell Gallery), bootstrap modules `Azure/accelerator-bootstrap-modules` v7.3.1, Terraform starter `Azure/alz-terraform-accelerator` v9.1.3. The accelerator downloads the bootstrap and starter modules itself when it runs.

## Phase 0: planning

Optional, but it's where the decisions are made. The accelerator's planning page numbers them, and the YAML files use the same numbers:

| Decision | Setting | This example |
| --- | --- | --- |
| 1 IaC tool | `iac_type` | `terraform` (Bicep is also supported; the bootstrap itself is always Terraform) |
| 2 Version control | `bootstrap_module_name` | `alz_github` or `alz_local` (`alz_azuredevops` for Azure DevOps) |
| 3 Starter module | `starter_module_name` | `platform_landing_zone` |
| 4 Bootstrap region | `bootstrap_location` | `uksouth` |
| 5 Platform regions | `starter_locations` (in the platform landing zone file, not the bootstrap file) | your region(s) |
| 6 Parent management group | `root_parent_management_group_id` | a test management group; empty means the Tenant Root Group |
| 7 Platform subscriptions | `subscription_ids` | management, identity, connectivity, security (four recommended; two for the SMB scenarios) |
| 8 Bootstrap subscription | `bootstrap_subscription_id` | empty = the Azure CLI subscription (the management subscription is recommended) |
| 9 Naming | `service_name`, `environment_name`, `postfix_number` | `alz`, `mgmt`, `1` |
| 10 Runners and networking | `use_self_hosted_runners`, `use_private_networking` | `false`, `false` |
| 11 VCS settings | `github_organization_name`, `apply_approvers`, tokens | placeholders |

For the platform landing zone itself, the Terraform starter offers scenarios. For a first run in a test tenant, **scenario 5, "Management Groups, Policy and Management Resources Only"**, deploys no connectivity resources; the accelerator's cost table lists its fixed infrastructure cost as zero (the management resources still bill for what they ingest). The hub-and-spoke and Virtual WAN scenarios include Azure Firewall, gateways and DDoS protection and cost thousands of dollars a month on the same table.

The accelerator also provides a `checklist.xlsx` on its planning page to record the decisions.

## Phase 1: prerequisites

- **Tools:** PowerShell 7.4 or later, Azure CLI 2.55.0 or later, Git. The accelerator doesn't support running behind a corporate proxy or in Azure Cloud Shell.
- **Subscriptions** for the platform (see decision 7), created through your billing agreement (chapter 4).
- **Permissions for the person running the bootstrap:** Owner on the parent management group and Owner on each platform subscription. Bicep additionally needs User Access Administrator at root scope `/`. A user account is recommended over a service principal, as this is a one-off.
- **GitHub:** an organisation (a personal account isn't supported). On a free organisation the bootstrap makes the repositories public. A fine-grained personal access token (`token-1`), scoped to the organisation, short-lived, with repository permissions Actions, Administration, Contents, Environments, Secrets, Variables and Workflows (read and write) and organisation permission Members (read and write). A second token (`token-2`) only if you use self-hosted runners.
- **Local file system:** only a folder you can write to.

## Phase 2: bootstrap

Interactive mode is `Deploy-Accelerator` with no parameters: a wizard that writes the same `inputs.yaml`. The advanced mode below uses these files.

```powershell
# 1. Install or update the ALZ PowerShell module
$alzModule = Get-InstalledPSResource -Name ALZ 2>$null
if (-not $alzModule) { Install-PSResource -Name ALZ } else { Update-PSResource -Name ALZ }

# 2. Create the folder structure for Terraform + GitHub, scenario 5 (management only)
$targetFolderPath = "~/accelerator"
New-AcceleratorFolderStructure -iacType "terraform" -versionControl "github" `
  -scenarioNumber 5 -targetFolderPath $targetFolderPath
#    (-versionControl "local" for the file-system run)

# 3. Replace the generated bootstrap file with this folder's, then edit it
Copy-Item ./inputs-github.yaml "$targetFolderPath/config/inputs.yaml"

# 4. Edit $targetFolderPath/config/platform-landing-zone.tfvars:
#    - starter_locations: replace the <region-#> placeholders
#    - defender_email_security_contact: a real address

# 5. Sign in and select the bootstrap subscription
az login --tenant "<tenant-id>" --use-device-code
az account set --subscription "<bootstrap-subscription-id>"

# 6. Supply the GitHub token without writing it to a file
$env:TF_VAR_github_personal_access_token = "<token-1>"

# 7. Run the bootstrap: it shows a Terraform plan and waits for confirmation
Deploy-Accelerator `
  -inputs "$targetFolderPath/config/inputs.yaml", "$targetFolderPath/config/platform-landing-zone.tfvars" `
  -starterAdditionalFiles "$targetFolderPath/config/lib" `
  -output "$targetFolderPath/output"
```

### What the bootstrap creates (Terraform + GitHub)

With the default names from `service_name: alz`, `environment_name: mgmt`, `postfix_number: 1`:

**In Azure**

| Resource | Default name | Purpose |
| --- | --- | --- |
| Resource group for state | `rg-alz-mgmt-state-<region>-1` | Holds the state storage account. |
| Storage account and container | `sto` + the first three letters of the service, environment and region names + `1` + a random string (for example `stoalzmgmuks1...`), container `mgmt-tfstate` | Terraform state for the platform landing zone. |
| Resource group for identity | `rg-alz-mgmt-identity-<region>-1` | Holds the two identities. |
| User-assigned managed identity for plan | `id-alz-mgmt-<region>-plan-1` | Runs `terraform plan`. Default role: **Reader** on the parent management group. |
| User-assigned managed identity for apply | `id-alz-mgmt-<region>-apply-1` | Runs `terraform apply`. Default role: **Owner** on the parent management group. |
| Federated credentials on both identities | prefix `alz-mgmt-<region>-1` | Trust the GitHub workflows (see below). |
| Role assignments | | The roles above, plus **Storage Blob Data Contributor** on the state container. |
| Optional (`use_self_hosted_runners`, `use_private_networking`) | `rg-alz-mgmt-agents-...`, `rg-alz-mgmt-network-...` | Container registry for the runner image, container instances running the runners, virtual network, subnets, NAT gateway, public IP, private DNS zone and private endpoints. Billed while they exist. |

**In GitHub**

| Item | Default name |
| --- | --- |
| Repository for the platform code (starter module plus `terraform.tfvars.json` with your bootstrap inputs) | `alz-mgmt` |
| Repository for the reusable workflow templates | `alz-mgmt-templates` |
| Workflows | `01 Azure Landing Zones Continuous Integration` (fmt, validate and plan on pull requests, with a comment on the PR) and `02 Azure Landing Zones Continuous Delivery` (plan, then apply), calling reusable templates in the templates repository |
| Environments | `alz-mgmt-plan` and `alz-mgmt-apply` (the apply environment requires approval) |
| Team for approvers | `alz-mgmt-approvers` (members from `apply_approvers`) |
| Branch policy | on `main` |
| Action variables | backend storage details and the identities' client IDs |
| OIDC subject claim customisation | the repository's token subject is built from `repository`, `environment` and `job_workflow_ref`, so only the template repository's workflows, in the right environment, can get a token |
| Optional | runner group (enterprise organisations with self-hosted runners) |

That last point is the main difference from this chapter's own pipeline: the accelerator customises GitHub's OIDC subject claim, so its federated credentials look like `repo:<org>@<org-id>/alz-mgmt@<repo-id>:environment:alz-mgmt-apply:job_workflow_ref:<org>/alz-mgmt-templates/.github/workflows/cd-template.yaml@refs/heads/main` (one per workflow and environment: CI and CD for the plan identity, CD for the apply identity), tying the token to the reviewed workflow template as well as the repository and environment. This chapter's `pipelines/` and identity code use GitHub's default subjects (`repo:<org>/<repo>:environment:<name>` and so on), which is simpler to read but trusts any workflow in the repository that uses that environment.

**With `alz_local`** there is no version control system: the bootstrap creates (if `create_bootstrap_resources_in_azure: true`) the state resource group, storage account and container, the identity resource group, and plan and apply identities with their role assignments, and writes the starter module with your variables into the output folder.

**With `alz_azuredevops`**, the same Azure resources plus a project (supplied or created), the two repositories, CI and CD pipelines, plan and apply environments, a variable group for the backend, **service connections using workload identity federation** for plan and apply, approvals, template validation and concurrency checks on the service connections, an approvers group, and optionally an agent pool.

## Phase 3: run

- **GitHub:** Actions > `02 Azure Landing Zones Continuous Delivery` > Run workflow. It plans, waits for an approver on the apply environment, then applies.
- **Azure DevOps:** Pipelines > `02 Azure Landing Zones Continuous Delivery` > Run pipeline; same flow.
- **Local:** in the output folder, run `./scripts/deploy-local.ps1`; it plans, asks you to type `yes`, then applies.

After that, changes go through pull requests: the CI workflow plans on the PR, and merging to `main` triggers the CD workflow.

## Clean-up

The accelerator's clean-up FAQ recommends its PowerShell cmdlet over the pipeline's destroy option for test environments:

```powershell
# Preview, then run without -PlanMode
Remove-PlatformLandingZone `
  -ManagementGroups "<root-parent-management-group-id>" `
  -Subscriptions "<management-subscription-id>", "<connectivity-subscription-id>", "<identity-subscription-id>", "<security-subscription-id>" `
  -AdditionalSubscriptions "<bootstrap-subscription-id>" `
  -PlanMode

# Then remove the bootstrap (repositories, identities, state storage), with the
# same arguments as the bootstrap run plus -destroy
Deploy-Accelerator `
  -inputs "$targetFolderPath/config/inputs.yaml", "$targetFolderPath/config/platform-landing-zone.tfvars" `
  -starterAdditionalFiles "$targetFolderPath/config/lib" `
  -output "$targetFolderPath/output" `
  -destroy
```

`Remove-GitHubAccelerator` and `Remove-AzureDevOpsAccelerator` remove the version control resources if you no longer have the folder structure.

## References

- IaC Accelerator overview and what the bootstrap creates: https://azure.github.io/Azure-Landing-Zones/accelerator/
- Phase 0, planning: https://azure.github.io/Azure-Landing-Zones/accelerator/0_planning/
- Phase 1, prerequisites (tools, permissions, GitHub): https://azure.github.io/Azure-Landing-Zones/accelerator/1_prerequisites/, https://azure.github.io/Azure-Landing-Zones/accelerator/1_prerequisites/platform-subscriptions/, https://azure.github.io/Azure-Landing-Zones/accelerator/1_prerequisites/github/
- Phase 2, bootstrap and advanced mode: https://azure.github.io/Azure-Landing-Zones/accelerator/2_bootstrap/ and https://azure.github.io/Azure-Landing-Zones/accelerator/2_bootstrap/advanced/
- Phase 3, run: https://azure.github.io/Azure-Landing-Zones/accelerator/3_run/
- Configuration files: https://azure.github.io/Azure-Landing-Zones/accelerator/configuration-files/
- Terraform scenarios and their estimated costs: https://azure.github.io/Azure-Landing-Zones/accelerator/starter-terraform/scenarios/
- Clean-up: https://azure.github.io/Azure-Landing-Zones/accelerator/faq/cleanup/
- Example inputs: https://github.com/Azure/alz-terraform-accelerator/tree/main/templates/platform_landing_zone/examples/bootstrap
- Bootstrap module (resource names, roles, OIDC subjects): https://github.com/Azure/accelerator-bootstrap-modules
- ALZ PowerShell module: https://www.powershellgallery.com/packages/ALZ
- Deploy Azure landing zones (Learn): https://learn.microsoft.com/azure/architecture/landing-zones/landing-zone-deploy
