# Chapter 4: Billing and tenant

Companion code for the "Build it" section of chapter 4: create a subscription programmatically with a **subscription alias** against a Microsoft Customer Agreement (MCA) billing scope.

- `terraform/`: Terraform version (AzAPI provider)
- `bicep/`: Bicep version

> **Creating a subscription is not free to undo instantly.** You can cancel a subscription straight away, but you can't delete it until a waiting period has passed (3 days for customer-led subscriptions, 7 days for field-led and partner subscriptions), and Azure deletes a cancelled subscription automatically only after 90 days. Treat the deploy test as **plan / what-if only** unless you intend to keep the subscription.

Tested: not yet

## What it builds

One `Microsoft.Subscription/aliases` resource, which asks Azure to create one subscription:

- billed to the invoice section (MCA) or enrollment account (EA) you give it;
- with the display name and workload type (`Production` or `DevTest`) you give it;
- optionally placed straight into a management group (for example `alz-corp` from chapter 6) and tagged.

The outputs are the new subscription ID and resource ID. Nothing is deployed *inside* the subscription.

### Why the raw resource and not an AVM module

Azure Verified Modules has no resource module for a subscription alias on its own. The modules that create subscriptions are the subscription vending pattern modules (Bicep `avm/ptn/lz/sub-vending`, Terraform `Azure/avm-ptn-alz-sub-vending/azure`), which chapter 7 uses. They wrap this same `Microsoft.Subscription/aliases@2021-10-01` call together with networking, RBAC and budgets. This chapter shows the bare API call so you can see what the vending module does underneath.

### Why AzAPI and not `azurerm_subscription` (Terraform)

Both work. This folder uses `azapi_resource` with `Microsoft.Subscription/aliases@2021-10-01` because:

- it's the same resource type, API version and property names as the Bicep version and the REST API on Microsoft Learn, so one explanation covers both languages;
- it exposes `additionalProperties.managementGroupId` and `tags`, so the subscription is placed and tagged in the creation request (with `azurerm_subscription` you'd add a separate `azurerm_management_group_subscription_association`);
- it's what the AVM Terraform vending module uses, so chapter 7 builds on the same pattern.

The one thing `azurerm_subscription` does for you is cancel the subscription when you destroy it. Deleting an alias does *not* cancel the subscription, so the Terraform version adds an `azapi_resource_action` that calls the Subscription - Cancel API on destroy (see "How it works").

## Prerequisites

### Billing roles (to create the subscription)

| Agreement | Role needed to create subscriptions | Billing scope ID format |
| --- | --- | --- |
| Microsoft Customer Agreement | Owner, contributor or **Azure subscription creator** on the invoice section; or owner or contributor on the billing profile or billing account | `/providers/Microsoft.Billing/billingAccounts/<account>/billingProfiles/<profile>/invoiceSections/<section>` |
| Enterprise Agreement | Enterprise Administrator, or **Owner of the enrollment account** (Account Owner) | `/providers/Microsoft.Billing/billingAccounts/<enrolment>/enrollmentAccounts/<account>` |

A service principal (for a pipeline) can be given the same billing role. For EA, the enrollment account role for the current API is granted with the 2019-10-01-preview Enrollment Account Role Assignments API; grants made with the older 2015-07-01 API don't carry over.

### Azure roles

- **Bicep:** permission to create deployments at the management group you deploy to (`Microsoft.Resources/deployments/*`, for example Owner or Contributor on that management group).
- **Management group placement (optional):** placing a subscription in a management group needs management group write access on the target management group (Owner, Contributor or Management Group Contributor). The tenant root group is the exception: no permission is needed to place a subscription there.
- **Cancel:** the subscription Owner (without a condition) can cancel. A user who creates a subscription through the alias API becomes its Owner.

### Licences and tools

- No Microsoft Entra licence is needed.
- Azure CLI signed in to the tenant (`az login`). The `az account alias` and `az account subscription` commands need the `account` extension: `az extension add --name account`.
- Terraform `~> 1.13` or the Bicep CLI.

## Find the billing scope ID

Sign in with an account that holds one of the billing roles above, then:

```bash
# 1. Billing accounts you can see. Check agreementType is MicrosoftCustomerAgreement and copy "name".
az billing account list --query "[].{name:name, displayName:displayName, agreementType:agreementType}" -o table

# 2. Billing profiles and their invoice sections under that account.
az billing profile list --account-name "<billing-account-name>" --expand "InvoiceSections" -o json

# Or list the invoice sections of one billing profile.
az billing invoice section list --account-name "<billing-account-name>" --profile-name "<billing-profile-name>" -o table
```

Copy the invoice section's full `id` (it starts `/providers/Microsoft.Billing/billingAccounts/`). That string is `billing_scope_id` / `billingScopeId`. For EA, `az billing account list` shows the enrollment accounts you own; use the enrollment account's `id`.

## Deploy

### Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # then edit the values
terraform init
terraform plan                                  # the deploy test stops here
# Only if you mean to keep the subscription:
terraform apply
```

`terraform plan` checks the configuration and your inputs; it doesn't check your billing rights. Azure checks those only when the alias is created.

### Bicep

```bash
cd bicep
# edit main.bicepparam first
az deployment mg what-if \
  --management-group-id <any-management-group-you-can-deploy-to> \
  --location uksouth \
  --name ch04-subscription-alias \
  --parameters main.bicepparam                 # the deploy test stops here

# Only if you mean to keep the subscription:
az deployment mg create \
  --management-group-id <any-management-group-you-can-deploy-to> \
  --location uksouth \
  --name ch04-subscription-alias \
  --parameters main.bicepparam
```

The `--location` is where the deployment record is stored, not where the subscription "lives". If you leave `managementGroupId` empty, the subscription lands in the tenant's default management group (the tenant root group unless the hierarchy settings name another).

## Destroy (cancel, then delete)

A subscription goes through three states: **active, cancelled, deleted**.

1. **Cancel.** Billing stops immediately and services are disabled (virtual machines deallocated, storage read-only). Delete the subscription's resources first: Learn requires that before a subscription can be deleted, and the cancel call fails while resources remain.
2. **Delete.** The **Delete** option appears in the portal 3 days after cancellation for customer-led subscriptions, or 7 days for field-led and partner subscriptions. You need the Owner role. Learn documents this step in the portal only (Subscriptions > the subscription > **Delete**).
3. **Automatic deletion.** If you don't delete it, Azure deletes a cancelled subscription automatically 90 days after cancellation.

### Terraform

```bash
cd terraform
terraform destroy
```

With `cancel_subscription_on_destroy = true` (the default), destroy cancels the subscription and then deletes the alias. Then delete the subscription in the portal after the waiting period, or let Azure delete it after 90 days. With `cancel_subscription_on_destroy = false`, destroy only deletes the alias and the subscription keeps running.

### Bicep

Deleting a deployment record doesn't delete what it created, so clean up with the CLI:

```bash
az extension add --name account

# 1. Find the subscription ID the alias created.
az account alias show --name alz-sub-test-001 --query properties.subscriptionId -o tsv

# 2. Delete any resource groups in it, then cancel it (billing stops now).
az account subscription cancel --id <subscription-id>

# 3. Delete the alias (this doesn't touch the subscription).
az account alias delete --name alz-sub-test-001

# 4. Optional: remove the deployment record.
az deployment mg delete --management-group-id <management-group-id> --name ch04-subscription-alias
```

Then delete the cancelled subscription in the portal after the waiting period, or leave Azure to delete it after 90 days.

## Inputs

| Terraform | Bicep | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `billing_scope_id` | `billingScopeId` | yes | none | Invoice section ID (MCA) or enrollment account ID (EA) |
| `subscription_alias_name` | `subscriptionAliasName` | yes | none | Alias name: letters, digits, hyphens; starts with a letter; no periods |
| `subscription_display_name` | `subscriptionDisplayName` | yes | none | Subscription display name |
| `subscription_workload` | `subscriptionWorkload` | no | `Production` | `Production` or `DevTest` |
| `management_group_id` | `managementGroupId` | no | `null` / `''` | Management group ID (name) to place the subscription in |
| `subscription_tags` | `subscriptionTags` | no | `{}` | Tags on the subscription |
| `cancel_subscription_on_destroy` | n/a | no | `true` | Cancel the subscription on `terraform destroy` |

## What it costs to leave running

An empty subscription has no resource charges; you pay for what you deploy into it, and removing all resources is how Microsoft Learn suggests stopping charges without cancelling. A support plan, if you buy one, is billed separately. The real cost of a test run is administrative: a cancelled subscription stays in the tenant for days before it can be deleted.

## Versions

| Component | Version |
| --- | --- |
| Terraform | `~> 1.13` (validated with 1.13.4) |
| `Azure/azapi` provider | `~> 2.13` (lock file: 2.13.0) |
| Bicep CLI | built with 0.48.1 |
| `Microsoft.Subscription/aliases` API | 2021-10-01 (the newest non-preview version) |
| Subscription - Cancel API | 2021-10-01 |

## How it works

These are the lines the chapter's Build it text explains.

1. **The alias is a tenant-scope resource.** Terraform: `parent_id = "/"`. Bicep: `scope: tenant()` inside a management group deployment, the pattern Learn shows for MCA, which avoids needing deployment rights at the tenant root. An alias isn't the subscription; it's the named request that creates it. Its name is the idempotency key: send the same alias twice and you get the same subscription, not two.

   ```hcl
   type      = "Microsoft.Subscription/aliases@2021-10-01"
   name      = var.subscription_alias_name
   parent_id = "/"
   ```

2. **`billingScope` decides who pays.** For MCA it's the invoice section ID, and the charges appear on that section of the billing profile's invoice. Billing roles, not Azure RBAC, decide whether you may create the subscription.

3. **`workload` picks the plan.** `Production` is the Microsoft Azure Plan; `DevTest` is the Microsoft Azure Plan for DevTest, available only if the billing profile has it enabled (`enabledAzurePlans` in the billing profile output).

4. **`additionalProperties` sets placement and tags at birth.** `managementGroupId` takes the full management group resource ID (`/providers/Microsoft.Management/managementGroups/<id>`), so the new subscription inherits that management group's policy and RBAC from the start. Without it, the subscription lands in the default management group. `additionalProperties` can also carry `subscriptionOwnerId` and `subscriptionTenantId` to make someone other than the caller the owner (used when a pipeline's service principal creates subscriptions).

5. **The subscription ID comes back on the alias.** `response_export_values = ["properties.subscriptionId"]` (Terraform) and `subscriptionAlias.properties.subscriptionId` (Bicep). Everything that follows (RBAC, budgets, networking in chapter 7) keys off this ID.

6. **An alias can create but not update.** Azure doesn't keep property changes sent to an existing alias, so the Terraform resource has `ignore_changes = [body, name]`; ignoring `name` also stops an edited alias name from replacing (and so cancelling) the subscription. Rename a subscription with the Rename operation, not by editing the alias.

7. **Deleting the alias doesn't cancel the subscription.** The Terraform version adds an action that runs only on destroy:

   ```hcl
   resource "azapi_resource_action" "cancel_subscription" {
     type        = "Microsoft.Resources/subscriptions@2021-10-01"
     resource_id = "/subscriptions/${local.subscription_id}"
     action      = "providers/Microsoft.Subscription/cancel"
     method      = "POST"
     when        = "destroy"
   }
   ```

   That's `POST /subscriptions/{id}/providers/Microsoft.Subscription/cancel`, the same call as `az account subscription cancel`. Bicep has no destroy step, so this README gives the CLI commands.

## Notes on the sources

- **Who can cancel.** The cancellation article says the subscription Owner (without a condition) cancels an Azure plan subscription. The MCA roles article's table shows the Azure subscription creator role can cancel the subscriptions it created, and the invoice section, billing profile and billing account roles can't. This README follows the cancellation article (Owner); the creator of an alias-made subscription is its Owner anyway.
- **Billing scope format.** The REST reference describes `billingScope` as `/billingAccounts/...`; the MCA how-to article and its examples use the full ID starting `/providers/Microsoft.Billing/billingAccounts/...`, which is what `az billing` returns. This code follows the how-to article.
- **`managementGroupId` format.** Learn's API reference describes it only as "Management group Id". The full resource ID format used here is the one the AVM Terraform vending module (0.3.3) sends.

## References

- Programmatically create Azure subscriptions for an MCA with the latest APIs: https://learn.microsoft.com/azure/cost-management-billing/manage/programmatically-create-subscription-microsoft-customer-agreement
- Programmatically create Azure EA subscriptions with the latest APIs: https://learn.microsoft.com/azure/cost-management-billing/manage/programmatically-create-subscription-enterprise-agreement
- Create a Microsoft Customer Agreement subscription (permissions): https://learn.microsoft.com/azure/cost-management-billing/manage/create-subscription
- Understand MCA administrative roles: https://learn.microsoft.com/azure/cost-management-billing/manage/understand-mca-roles
- Microsoft.Subscription aliases template reference (2021-10-01): https://learn.microsoft.com/azure/templates/microsoft.subscription/2021-10-01/aliases
- Alias - Create REST API: https://learn.microsoft.com/rest/api/subscription/alias/create
- Subscription - Cancel REST API: https://learn.microsoft.com/rest/api/subscription/subscription/cancel
- Cancel and delete your Azure subscription: https://learn.microsoft.com/azure/cost-management-billing/manage/cancel-azure-subscription
- az account subscription: https://learn.microsoft.com/cli/azure/account/subscription
- az account alias: https://learn.microsoft.com/cli/azure/account/alias
- az billing invoice section: https://learn.microsoft.com/cli/azure/billing/invoice/section
- Move subscriptions between management groups (permissions): https://learn.microsoft.com/azure/governance/management-groups/manage#move-management-groups-and-subscriptions
- AVM Terraform subscription vending module (alias implementation): https://registry.terraform.io/modules/Azure/avm-ptn-alz-sub-vending/azure/0.3.3
- `azurerm_subscription` (cancel-on-destroy behaviour): https://registry.terraform.io/providers/hashicorp/azurerm/5.8.0/docs/resources/subscription
