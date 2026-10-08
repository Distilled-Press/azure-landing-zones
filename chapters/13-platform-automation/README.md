# Chapter 13: Platform automation

Companion code for the "Build it" section of chapter 13. It puts chapter 6's platform code behind a pipeline: plan on every pull request, apply after approval when the change merges, with no secret anywhere.

| Folder | What it is | Deployed? |
| --- | --- | --- |
| `terraform/`, `bicep/` | **The pipeline identities.** User-assigned managed identities with federated credentials for a GitHub repository (environment, branch and pull request subjects) and a role on a management group; optional Terraform state storage. | Yes: this is the deployable part. |
| `pipelines/github/alz-platform.yml` | GitHub Actions workflow for chapter 6's Terraform: plan on pull request (plan posted as a PR comment and an artefact), apply on push to `main` from the saved plan, behind an environment that requires approval. OIDC through `azure/login` and `ARM_USE_OIDC`. | Copy into `.github/workflows/` of your platform repository. |
| `pipelines/azure-devops/alz-platform.yml` | The same pipeline in Azure Pipelines YAML, using workload identity federation service connections. | Create a pipeline from it. |
| `accelerator/` | Inputs for the Azure Landing Zones IaC Accelerator (Terraform + GitHub, and the local file system) and a walk-through of its phases 0-3, including exactly what the bootstrap creates. | **Not run.** See [`accelerator/README.md`](accelerator/README.md). |

```
GitHub repository  ──OIDC token──►  Microsoft Entra ID  ──access token──►  Azure
  pull request job        sub = repo:org/repo:pull_request          ─► id-alz-platform-plan   (Reader on the management group)
  push to main, plan      sub = repo:org/repo:ref:refs/heads/main   ─► id-alz-platform-plan
  apply job (approved)    sub = repo:org/repo:environment:alz-apply ─► id-alz-platform-apply  (Owner on the management group)
```

Tested: 8 October 2026 (Terraform 1.13.4, Bicep CLI 0.48.1, Azure CLI 2.91.0): Terraform apply and destroy, Bicep deployment and the clean-up commands below, against a test management group, with placeholder GitHub subjects (no pipeline run, so no token exchange was tested). The pipelines and the accelerator weren't run; actionlint wasn't available in the test environment, so the workflow wasn't re-linted.

## The identities (`terraform/`, `bicep/`)

Two user-assigned managed identities in `rg-alz-platform-automation-uksouth`:

| Identity | Role on the management group | Federated credentials (GitHub subject) |
| --- | --- | --- |
| `id-alz-platform-plan-uksouth` | Reader | `repo:<org>/<repo>:pull_request` and `repo:<org>/<repo>:ref:refs/heads/main` |
| `id-alz-platform-apply-uksouth` | Owner | `repo:<org>/<repo>:environment:alz-apply` |

Both also get Reader on the subscription they live in (`subscription_reader_enabled`, see [Prerequisites](#prerequisites)) and, with `state_storage_enabled = true`, Storage Blob Data Contributor on the `tfstate` container of a new storage account.

The split follows Learn's guidance for Terraform with GitHub Actions: a read-only identity trusted for pull requests and the main branch, and a read/write identity trusted only for the protected environment. A pull request can run code from its branch, so it must never get a token that can change the platform. Only the `alz-apply` environment, which GitHub releases to a job after a required reviewer approves, can get the Owner identity's token. Owner (rather than Contributor) is needed because chapter 6 creates role assignments for the policy assignments' managed identities. It's the same pair of roles the IaC Accelerator's bootstrap gives its plan and apply identities.

### The subject formats

The federated credential's issuer, subject and audience must match the GitHub token exactly (case-sensitively); a typo still creates the credential and only fails at sign-in. GitHub's subject depends on the job:

| Job | Subject | `type` in the inputs |
| --- | --- | --- |
| Uses an environment | `repo:<org>/<repo>:environment:<environment>` | `environment` |
| No environment, branch push | `repo:<org>/<repo>:ref:refs/heads/<branch>` | `branch` |
| No environment, tag push | `repo:<org>/<repo>:ref:refs/tags/<tag>` | `tag` |
| No environment, pull request event | `repo:<org>/<repo>:pull_request` | `pull_request` |

Issuer `https://token.actions.githubusercontent.com`; audience `api://AzureADTokenExchange`. Note the underscore in `pull_request`: that is what GitHub puts in the token (GitHub's OIDC reference). One Learn page (*Configure an app to trust an external identity provider*, in its command-line "GitHub Actions example" sections) writes the pull request subject as `repo:<org>/<repo>:pull-request` with a hyphen; a credential with the hyphen never matches. An environment takes precedence: a pull request job that names an environment gets the environment subject, not `pull_request`. Branch and tag subjects can't use wildcards; use an environment when a job runs from many branches.

### Prerequisites

- **Azure CLI** signed in (`az login`) as a person: this is the one-off bootstrap that creates the pipeline's identities.
- **Permissions:** Owner on the management group (it creates role assignments there) and Owner on the subscription (resource group, identities, the subscription Reader assignment and, if enabled, storage and its container role assignments). User Access Administrator or Role Based Access Control Administrator plus Contributor also works.
- **The management group** exists: chapter 6's intermediate root `alz`, or a test management group.
- **Bicep only:** the deployment runs at the management group and reaches into the subscription through modules. Learn's page on management group deployments describes targeting subscriptions *within* the management group, and the account deploying needs access to both scopes. In a real platform the management subscription sits under the intermediate root anyway. In the test, a deployment at a test management group that did **not** contain the subscription also succeeded.
- **Sign-in subscription:** `azure/login` (with `subscription-id`) and the Azure DevOps `AzureCLI@2` task select a subscription when they sign in, so the identities must be able to read one. When the subscription sits under the management group, Reader is inherited and you can set `subscription_reader_enabled = false`; the default `true` adds an explicit Reader assignment so the test works anywhere.
- **Licences:** none in Azure. GitHub: OIDC works on every plan, but GitHub's documentation says that on the Free, Pro and Team plans **required reviewers** for an environment are only available for **public** repositories; for a private platform repository the approval gate needs GitHub Enterprise (or use Azure DevOps, where environment approvals have no such limit). Azure DevOps: nothing beyond your organisation's pipelines.

### Deploy and destroy: Terraform

```bash
cd chapters/13-platform-automation/terraform
cp terraform.tfvars.example terraform.tfvars   # subscription, management group, GitHub org and repository
terraform init
terraform plan -out tfplan
terraform apply tfplan
terraform output                               # client IDs, tenant, backend settings for the pipelines
```

Destroy:

```bash
terraform destroy
```

This removes the role assignments, the federated credentials, the identities, the storage account (with any state in it) and the resource group. Destroy the platform that the pipeline deployed first (chapter 6), while its identities still exist, or clean it up by hand afterwards.

Allow a minute or two after `apply` before the first pipeline run: Learn notes that a new federated credential takes time to propagate, and an early token request can fail with `AADSTS70021: No matching federated identity record found`. Retry rather than change anything.

### Deploy and destroy: Bicep

```bash
cd chapters/13-platform-automation/bicep
# edit main.bicepparam: subscriptionId, githubOrganization, githubRepository
az deployment mg what-if --management-group-id alz --location uksouth --name ch13-identity --parameters main.bicepparam
az deployment mg create  --management-group-id alz --location uksouth --name ch13-identity --parameters main.bicepparam
az deployment mg show    --management-group-id alz --name ch13-identity --query properties.outputs
```

The management group in `--management-group-id` is the one the identities get their roles on. What-if reports the role assignments as "Unsupported" because their principal IDs only exist after the identities are created; that's expected.

Destroy (Bash). Remove the role assignments before the identities, or they stay behind as "Identity not found":

```bash
MG=alz
SUB=00000000-0000-0000-0000-000000000000
RG=rg-alz-platform-automation-uksouth

# --all covers subscriptions and below, so list the management group scope too
for ID in id-alz-platform-plan-uksouth id-alz-platform-apply-uksouth; do
  PRINCIPAL=$(az identity show --subscription $SUB -g $RG -n $ID --query principalId -o tsv)
  for RA in $(az role assignment list --all --assignee "$PRINCIPAL" --query "[].id" -o tsv) \
            $(az role assignment list --scope "/providers/Microsoft.Management/managementGroups/$MG" --assignee "$PRINCIPAL" --query "[].id" -o tsv); do
    az role assignment delete --ids "$RA"
  done
done

# Identities, federated credentials and (if created) the state storage account
az group delete --subscription $SUB --name $RG --yes

# Deployment records (optional). The modules leave their own records too:
# ch13-ra-* and role-asi-mg-* at the management group, ch13-rg and
# role-asi-sub-* at the subscription.
az deployment mg delete --management-group-id $MG --name ch13-identity
```

## The GitHub pipeline (`pipelines/github/alz-platform.yml`)

1. **Repository.** Put chapter 6's `terraform/` folder in a repository (this book's repository layout, `chapters/06-resource-organisation/terraform`, is what the workflow's `TF_ROOT` points at) and copy the workflow to `.github/workflows/alz-platform.yml`.
2. **State.** Deploy the identity code with `state_storage_enabled = true`, or point the workflow at an existing storage account where both identities have Storage Blob Data Contributor. The account has shared-key access disabled, so the backend uses Entra ID (`ARM_USE_AZUREAD=true`) with the same OIDC sign-in. The workflow adds a backend block (`ci_backend.tf`) at run time because chapter 6 has none.
3. **Variables** (Settings > Secrets and variables > Actions > Variables), from `terraform output` / the Bicep outputs. None is a secret.

   | Variable | Value |
   | --- | --- |
   | `AZURE_TENANT_ID` | `tenant_id` |
   | `AZURE_SUBSCRIPTION_ID` | `subscription_id` |
   | `AZURE_CLIENT_ID_PLAN` | `client_ids.plan` |
   | `AZURE_CLIENT_ID_APPLY` | `client_ids.apply` |
   | `BACKEND_RESOURCE_GROUP`, `BACKEND_STORAGE_ACCOUNT`, `BACKEND_CONTAINER` | `state_backend` |

4. **Environment.** Settings > Environments > New environment `alz-apply`: add **required reviewers** (the platform approvers) and limit **deployment branches** to `main`. The environment name must match the apply identity's credential.
5. **Branch protection** on `main`: require a pull request and the `Plan` check, so every change is planned and reviewed before it can reach the apply job.
6. Open a pull request that changes chapter 6. The `Plan` job signs in as the plan identity (subject `pull_request`) and posts the plan as a comment; the full plan is also in the `tfplan` artefact. Merge it, and the workflow plans again on `main` (subject `ref:refs/heads/main`), then waits for approval; once approved, the `Apply` job signs in as the apply identity (subject `environment:alz-apply`) and applies the saved plan.

## The Azure DevOps pipeline (`pipelines/azure-devops/alz-platform.yml`)

1. **Service connections** (Project settings > Service connections > New > Azure Resource Manager > **App registration or Managed identity (manual)** > **Workload identity federation**), one per identity: `sc-alz-plan` with the plan identity's client ID, `sc-alz-apply` with the apply identity's. Use **Subscription** scope with the identities' subscription (the role on the management group still applies; the task needs a subscription to select). Copy the **Issuer** and **Subject identifier** the form generates and save the connection as a draft.
2. **Federated credentials.** Add each issuer/subject pair to `additional_federated_credentials` (Terraform) or `additionalFederatedCredentials` (Bicep) with `identity_key` `plan` or `apply`, and apply again. Then finish (verify and save) the service connections. New service connections use the Microsoft Entra issuer (under `https://login.microsoftonline.com/`); Learn says the older Azure DevOps issuer (`https://vstoken.dev.azure.com`) is deprecated and retires on 1 July 2027. Copy the values exactly as the form shows them.
3. Don't grant the service connections to all pipelines; authorise this pipeline on each.
4. **Environment** `alz-apply` (Pipelines > Environments) with an **Approvals** check. Optionally add the same check to `sc-alz-apply`, so nothing can use the Owner identity without approval.
5. **Variables** at the top of the YAML: the backend storage account, container and resource group.
6. **Pull requests.** For code in Azure Repos, add a build validation branch policy on `main` that runs this pipeline; the `pr:` trigger only applies to GitHub and Bitbucket repositories. Pull request runs stop after the Plan stage (`condition: ... ne(variables['Build.Reason'], 'PullRequest')`), and the plan is published as the `plan-text` artefact.

`AzureCLI@2` signs in through the service connection, and `addSpnToEnvironment: true` exposes the federated token to the script as `$idToken` with `$servicePrincipalId` and `$tenantId`, which the script passes to Terraform as `ARM_OIDC_TOKEN`, `ARM_CLIENT_ID` and `ARM_TENANT_ID`. This is the pattern the IaC Accelerator's own Azure DevOps templates use.

## Inputs (identity code)

| Terraform | Bicep | Default | Notes |
| --- | --- | --- | --- |
| `subscription_id` | `subscriptionId` | none, required | Subscription for the identities (the management subscription). |
| `management_group_id` | `--management-group-id` | none, required | Management group the roles are assigned on. |
| `github_organization` | `githubOrganization` | none, required | |
| `github_repository` | `githubRepository` | none, required | |
| `identities` | `identities` | plan (Reader; `pull_request`, branch `main`), apply (Owner; environment `alz-apply`) | Map (Terraform) or array (Bicep) of identities, each with a role and up to 20 federated credentials. |
| `additional_federated_credentials` | `additionalFederatedCredentials` | none | Other issuers, such as Azure DevOps service connections. |
| `subscription_reader_enabled` | `subscriptionReaderEnabled` | `true` | Reader on the sign-in subscription. |
| `state_storage_enabled` | `stateStorageEnabled` | `false` | Storage account (`Standard_LRS`, shared keys off, versioning and 30-day soft delete) and `tfstate` container. |
| `prefix` | `prefix` | `alz` | |
| `location` | `location` | `uksouth` | |
| `resource_group_name` | `resourceGroupName` | `rg-<prefix>-platform-automation-<location>` | |
| `tags` | `tags` | `{}` | |
| `enable_telemetry` | `enableTelemetry` | `true` | AVM telemetry. No cost. |

## Cost

- **Identities, federated credentials, role assignments, resource group:** no charge.
- **State storage (opt-in):** a Standard LRS general-purpose v2 account holding a few small state files and their versions; billed for capacity and transactions at a level of pence a month. Off by default.
- **Pipeline minutes:** GitHub-hosted runners and Microsoft-hosted agents use your GitHub plan's minutes or your Azure DevOps organisation's hosted parallel jobs.
- **The accelerator (if you run it):** bootstrap resources are the state storage account and identities. Self-hosted runners and private networking (`use_self_hosted_runners`, `use_private_networking`) add a container registry, container instances, a NAT gateway, a public IP and private endpoints, which bill while they exist. The platform landing zone scenarios range from no fixed cost (management only) to thousands of dollars a month (hub and spoke or Virtual WAN with Azure Firewall); see `accelerator/README.md`.

## How it works

The chapter's Build it text is written from these points.

1. **No secrets, only trust** (`federated_identity_credentials` on `module "identity"`; `federatedIdentityCredentials` in Bicep). Each credential says: tokens from issuer `https://token.actions.githubusercontent.com`, for audience `api://AzureADTokenExchange`, with exactly this subject, may act as this identity. GitHub signs a short-lived token per job; there's nothing to store, leak or rotate.
2. **The subject decides who gets which identity** (`local.github_subject`). `pull_request` and `ref:refs/heads/main` map to the Reader identity; `environment:alz-apply` maps to the Owner identity. The approval gate on the GitHub environment is what turns "a workflow ran" into "a person approved a change to the platform".
3. **Roles at the management group** (`azurerm_role_assignment.management_group`, scope `/providers/Microsoft.Management/managementGroups/<id>`). The pipeline manages management groups and policy, so its identities are scoped where those live, not to a subscription. A plain resource is used rather than the AVM role assignment module, whose lookup maps hide the one line that matters here.
4. **Credentials are created one at a time.** Learn: concurrent writes to federated credentials on one user-assigned identity fail with 409 Conflict. The azurerm provider (3.40.0 and later) serialises them, and the AVM Bicep module uses `batchSize(1)`.
5. **The workflow asks for a token, not a password** (`permissions: id-token: write` per job, `azure/login@v3` with `client-id`, `tenant-id`, `subscription-id`, and `ARM_USE_OIDC: "true"`). With `id-token: write`, GitHub exposes a token endpoint to the job; `azure/login` signs the Azure CLI in with it, and the Terraform providers and the azurerm backend (`ARM_USE_AZUREAD: "true"`) request their own tokens from the same endpoint.
6. **Plan on pull request, apply the saved plan** (`terraform plan -out=tfplan`, artefact, `terraform apply tfplan`). The apply job applies exactly the plan that was reviewed. If the state changed in between, Terraform rejects the stale plan rather than doing something nobody saw.
7. **Least privilege per job** (`permissions: {}` at the top, then only `id-token: write`, `contents: read` and, for the plan job, `pull-requests: write`), and `concurrency: alz-platform` so two runs never change the platform at once.
8. **Azure DevOps does the same through service connections** (`AzureCLI@2` with `addSpnToEnvironment: true`, `ARM_OIDC_TOKEN="$idToken"`). The issuer and subject come from the service connection, so they are added to the identity as `additional_federated_credentials`; approvals sit on the `alz-apply` environment.
9. **The accelerator automates all of this** (`accelerator/`): its bootstrap creates the repositories, workflows, environments, approvers team, state storage and the same plan/apply identity pair, and goes further by customising GitHub's OIDC subject to include the workflow template (`job_workflow_ref`).

## Versions

Checked against the Terraform registry, the Microsoft Container Registry, GitHub and the PowerShell Gallery on 7 October 2026.

| Component | Version |
| --- | --- |
| Terraform | `~> 1.13` (validated with 1.13.4; the pipelines install 1.13.4) |
| `Azure/avm-res-resources-resourcegroup/azurerm` | 0.4.0 |
| `Azure/avm-res-managedidentity-userassignedidentity/azurerm` | 0.5.3 |
| `Azure/avm-res-storage-storageaccount/azurerm` | 0.10.0 |
| Role assignments (Terraform) | `azurerm_role_assignment` |
| Provider `hashicorp/azurerm` | `~> 4.81` (locked 4.81.0; the AVM modules require < 5.0) |
| Provider `Azure/azapi` | `~> 2.13` (locked 2.13.0) |
| Providers `Azure/modtm`, `hashicorp/random` | locked 0.4.0, 3.9.1 |
| Bicep `br/public:avm/res/resources/resource-group` | 0.4.4 |
| Bicep `br/public:avm/res/managed-identity/user-assigned-identity` | 0.6.0 |
| Bicep `br/public:avm/ptn/authorization/role-assignment` | 0.2.4 |
| Bicep `br/public:avm/res/storage/storage-account` | 0.33.1 |
| Bicep CLI used to build | 0.48.1 |
| GitHub Actions | `actions/checkout@v7`, `azure/login@v3`, `hashicorp/setup-terraform@v4`, `actions/upload-artifact@v7`, `actions/download-artifact@v8`, `actions/github-script@v9` (workflow checked with actionlint 1.7.12) |
| Azure Pipelines task | `AzureCLI@2` |
| Accelerator (not run) | ALZ PowerShell module 7.1.5; bootstrap modules v7.3.1; Terraform starter v9.1.3 |

## References

- Platform automation and DevOps design area: https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/platform-automation-devops
- Automation considerations (CAF): https://learn.microsoft.com/azure/cloud-adoption-framework/ready/considerations/automation
- Deploy to Azure infrastructure with GitHub Actions (read-only and read/write identities, environment approvals): https://learn.microsoft.com/devops/deliver/iac-github-actions
- Use the Azure Login action with OpenID Connect: https://learn.microsoft.com/azure/developer/github/connect-from-azure-openid-connect
- Configure a user-assigned managed identity to trust an external identity provider (GitHub entity types, issuer, audience, 20-credential limit): https://learn.microsoft.com/entra/workload-id/workload-identity-federation-create-trust-user-assigned-managed-identity
- Configure an app to trust an external identity provider (GitHub subject formats): https://learn.microsoft.com/entra/workload-id/workload-identity-federation-create-trust
- Federated identity credential considerations (propagation delay, no concurrent writes): https://learn.microsoft.com/entra/workload-id/workload-identity-federation-considerations
- Workload identity federation concepts (case-sensitive matching): https://learn.microsoft.com/entra/workload-id/workload-identity-federation
- GitHub's OIDC subject claims: https://docs.github.com/actions/reference/security/oidc
- Azure DevOps workload identity federation service connections (manual, managed identity; Entra issuer; Azure DevOps issuer retirement): https://learn.microsoft.com/azure/devops/pipelines/release/configure-workload-identity
- AzureCLI@2 (`addSpnToEnvironment`, `idToken`): https://learn.microsoft.com/azure/devops/pipelines/tasks/reference/azure-cli-v2
- Azure DevOps approvals and checks: https://learn.microsoft.com/azure/devops/pipelines/process/approvals
- Management group deployments with Bicep (deployment scopes): https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-to-management-group and https://learn.microsoft.com/azure/azure-resource-manager/templates/deploy-to-management-group#deployment-scopes
- Terraform azurerm backend: https://developer.hashicorp.com/terraform/language/backend/azurerm
- IaC Accelerator: https://azure.github.io/Azure-Landing-Zones/accelerator/ (more in `accelerator/README.md`)
- Terraform modules: https://registry.terraform.io/modules/Azure/avm-res-managedidentity-userassignedidentity/azurerm/0.5.3, https://registry.terraform.io/modules/Azure/avm-res-storage-storageaccount/azurerm/0.10.0, https://registry.terraform.io/modules/Azure/avm-res-resources-resourcegroup/azurerm/0.4.0
- Bicep modules: https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/managed-identity/user-assigned-identity, https://github.com/Azure/bicep-registry-modules/tree/main/avm/ptn/authorization/role-assignment, https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/storage/storage-account
