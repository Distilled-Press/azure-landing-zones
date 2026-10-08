# Chapter 12: Management baseline

Companion code for the "Build it" section of chapter 12. It builds the management resources a platform landing zone needs before the ALZ monitoring policies can do anything useful, plus the alerting that tells the platform team when Azure itself has a problem.

```
Management subscription
└── rg-alz-management-uksouth
    ├── log-alz-uksouth              Log Analytics workspace (PerGB2018, 30 days)
    ├── dcr-alz-vminsights-uksouth   Data collection rule: VM insights performance counters
    ├── id-alz-ama-uksouth           User-assigned identity for the Azure Monitor Agent policies
    ├── ag-alz-platform              Action group (email receivers), location global
    └── alert-alz-servicehealth      Service Health activity log alert -> ag-alz-platform

Opt-in (deploy_amba / amba.bicep), at a management group you choose:
    AMBA-ALZ policy definitions, initiatives and assignments (DoNotEnforce by default)
```

Names start with the `prefix` input (default `alz`) and end with the region where the resource is regional.

| Folder | What it deploys |
| --- | --- |
| `terraform/` | Everything above. With `deploy_amba = true`, the **full** AMBA-ALZ set from the ALZ library (platform/amba 2026.06.2): 143 policy definitions, 16 initiatives and 15 initiative assignments on one management group, the role assignments their identities need, and a resource group with the identity AMBA's log search alerts run as. |
| `bicep/main.bicep` | Everything above except AMBA (subscription deployment). |
| `bicep/amba.bicep` | Opt-in, separate management group deployment: all AMBA definitions and initiatives from the AMBA release 2026-06-03 templates, and a **subset** of two assignments (Resource and Service Health, Notification Assets). See [AMBA in Bicep](#amba-in-bicep). |

Tested: 8 October 2026 (Terraform 1.13.4, Bicep CLI 0.48.1, Azure CLI 2.91.0): Terraform apply and destroy of the baseline; Bicep deployment of `main.bicep` and the clean-up commands, in a test tenant. **AMBA failed in both versions** (see [Known issue: AMBA initiatives rejected](#known-issue-amba-initiatives-rejected)): the Terraform apply created the 143 definitions, 12 of 16 initiatives and the AMBA identity, then stopped; `amba.bicep` created the definitions and stopped at the initiatives. No AMBA assignment was created, so assignments, their role assignments and enforcement mode weren't verified. Both were destroyed with the commands below.

The baseline is testable on its own: it needs a subscription, not chapter 6's hierarchy. Its outputs are the IDs chapter 6's `policy_default_values` asks for (see [Feeding chapter 6](#feeding-chapter-6)).

## Prerequisites

- **A subscription for the management resources** (in a real platform, the management subscription). Azure CLI signed in with `az login` and that subscription selected (`az account set --subscription <id>`).
- **Permissions.**
  - Baseline only: Contributor on the subscription. It creates a resource group, a workspace, a data collection rule, an identity, an action group and an activity log alert, and no role assignments.
  - AMBA (opt-in): Owner on the target management group and on the management subscription. The code creates policy definitions, initiatives and assignments at the management group, role assignments for the assignments' managed identities (Monitoring Policy Contributor and Managed Identity Operator, some of them on the management subscription), and a Monitoring Reader assignment for the AMBA identity. AMBA's documentation gives a least-privilege alternative to Owner: Managed Identity Contributor, Monitoring Policy Contributor, and User Access Administrator with a condition that stops it assigning Owner, User Access Administrator or Role Based Access Control Administrator.
- **Resource providers.** AMBA's prerequisites say `Microsoft.AlertsManagement` and `Microsoft.Insights` must be registered on every subscription in scope: `az provider register --namespace Microsoft.AlertsManagement` (and the same for `Microsoft.Insights`).
- **For AMBA, an existing management group** to deploy to. The default is `alz`, the intermediate root chapter 6 creates; any test management group works. Don't move production subscriptions under it while testing: in `Default` enforcement mode the AMBA policies deploy alert rules, alert processing rules and action groups into every subscription below it.
- **Licences:** none.
- **Tools:** Terraform 1.13 or later (validated with 1.13.4). Bicep CLI 0.48.1 or later, and Azure CLI 2.53.0 or later for `.bicepparam` files.

## Email receivers have to verify themselves (one-time passcode)

Learn's action groups page (updated July 2026) says each email receiver **must be verified through a one-time passcode (OTP) within 30 minutes of saving the action group**. When an address is added, its owner gets a "Verify your email address" message containing the passcode. An unverified address **can't receive alert or test notifications** once enforcement is active. The verification **persists across all past and future action groups in the same tenant**, so each address does this once per tenant. If the 30 minutes pass, open the action group in the portal and select **Resend**. Emails to Azure Resource Manager *role* receivers (for example, "email the subscription Owners") don't need OTP verification.

This matters more for code than for the portal. `terraform apply` or `az deployment ... create` succeeds whether or not anyone verifies, and nothing in the output says an address is unverified; the alerts just go nowhere. So:

- Tell the receivers before you apply, and have them enter the code within 30 minutes. The Terraform output `action_group_email_receivers_to_verify` and the Bicep output `actionGroupEmailReceiversToVerify` list the addresses.
- Prefer a team mailbox or distribution list that someone watches, so one verification covers the team.
- Anything else that creates action groups needs the same step: AMBA's policies (when they create their own action groups) and subscription vending (chapter 7) if it adds action groups for workload teams. This code points AMBA at the platform action group by default, so AMBA adds no new addresses.
- After verifying, use **Test** on the action group in the portal to confirm that an email arrives.

## Terraform

```bash
cd chapters/12-management-baseline/terraform
cp terraform.tfvars.example terraform.tfvars   # set subscription_id and the email addresses
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

Then have each new email receiver enter their passcode within 30 minutes.

### AMBA-ALZ (opt-in)

```bash
# Only if AMBA should target a management group other than "alz":
terraform -chdir=set-amba-scope init
terraform -chdir=set-amba-scope apply -var management_group_id=mg-amba-test

terraform plan -var deploy_amba=true -var amba_management_group_id=mg-amba-test -out tfplan
terraform apply tfplan
```

The management group must already exist. As in chapter 6, its ID is written in `lib/architecture_definitions/amba_single.alz_architecture_definition.json`, which the ALZ provider reads before Terraform plans anything, so a small helper rewrites it. The helper only writes a local file; don't run `terraform destroy` in `set-amba-scope/` (run it again with the old ID to go back). If the file and `amba_management_group_id` disagree, the plan stops with an error that says so.

### Known issue: AMBA initiatives rejected

In the test on 8 October 2026, Azure rejected four AMBA initiatives from library platform/amba 2026.06.2 (`Alerting-VM`, `Alerting-VMSS`, `Alerting-HybridVM`, `Alerting-ResourceAndServiceHealth`) with `PolicySetParameterAllowedValuesMismatch`: some initiative parameters allow values the policy definitions don't (for example `PT1M` for `evaluationFrequency`, `P1D` for `windowSize`, and `deployIfNotExists`/`disabled` in lower case for the built-in Service Health policy's `effect`). The apply stops before any assignment is created. Earlier library releases (2026.06.1, 2026.06.0, 2026.01.1) contain the same mismatches, and AMBA's own ARM templates (release 2026-06-03, used by `amba.bicep`) fail the same way, plus a fifth initiative, `Alerting-LandingZone`. Replacing the four initiatives through a local library with `library_overwrite_enabled = true` didn't work with ALZ provider 0.22.0: the library's own copies were still used. Until AMBA publishes a fixed release, `deploy_amba = true` and `amba.bicep` don't complete; destroy what the failed run created (below).

The first plan with AMBA on is slower: the ALZ provider downloads the library into `.alzlib/` (git-ignored) and reads built-in policy definitions from Azure. A plan in the test tenant showed 244 resources to add: 19 for the baseline and 225 for AMBA.

With `deploy_amba = false` the `alz` provider is still installed by `terraform init` (it's in `required_providers`), but no AMBA resources or data sources are evaluated.

### Destroy (Terraform)

```bash
terraform destroy          # with the same -var flags you applied with
```

This deletes everything Terraform created, including the AMBA definitions, initiatives, assignments, role assignments, identity and its resource group. The workspace is deleted **permanently** (the provider feature `permanently_delete_on_destroy` is set in `terraform.tf`), so the name can be reused at once instead of waiting out the 14-day soft-delete.

What it can't delete is anything AMBA's policies deployed themselves. In the default `DoNotEnforce` mode, without remediation tasks, there is none. If you switched to `Default` or ran remediation, AMBA's documentation says to run its clean-up script after `terraform destroy`: `Start-AMBA-ALZ-Maintenance.ps1 -pseudoRootManagementGroup <mg> -cleanItems Amba-Alz`, from `patterns/alz/scripts` in the AMBA repository (PowerShell 7 with Az.Accounts, Az.Resources, Az.ResourceGraph and Az.ManagedServiceIdentity; try `-WhatIf` first). It finds AMBA's resources by the `_deployed_by_amba` tag or metadata.

## Bicep

```bash
cd chapters/12-management-baseline/bicep
az account set --subscription <management-subscription-id>
az deployment sub what-if --name ch12-management --location uksouth --parameters main.bicepparam
az deployment sub create  --name ch12-management --location uksouth --parameters main.bicepparam
```

Edit `actionGroupEmailAddresses` in `main.bicepparam` first, then verify the addresses within 30 minutes. `--location` is where the deployment record is stored; the resources use the `location` parameter.

### AMBA in Bicep

AMBA-ALZ's Bicep/ARM route is a set of linked ARM templates in the AMBA repository (`patterns/alz/alzArm.json` and the files it links to), deployed with `az deployment mg create --template-uri ...`. There's no AVM Bicep module for it. `alzArm.json` doesn't pass an enforcement mode to its assignments, so they are always created in `Default`. `amba.bicep` therefore links the same templates from the pinned release itself:

1. the eleven `policyDefinitions/policies-*.json` templates and `policySets.json` (every AMBA definition and initiative; the initiatives reference definitions from several files, and definitions cost nothing), then
2. the two assignment templates AMBA puts on the intermediate root, `DINE-ResourceAndServiceHealthAssignment.json` (assignment `Deploy-AMBA-Res-SvcHlth`) and `DINE-NotificationAssetsAssignment.json` (`Deploy-AMBA-Notification`), passing the `enforcementMode` parameter those templates accept.

```bash
# first set byoActionGroupIds in amba.bicepparam to main.bicep's actionGroupId output
az deployment mg what-if --management-group-id alz --location uksouth --name ch12-amba --parameters amba.bicepparam
az deployment mg create  --management-group-id alz --location uksouth --name ch12-amba --parameters amba.bicepparam
```

A what-if of `amba.bicep` in the test tenant listed 143 policy definitions, 17 policy set definitions, 2 policy assignments and 2 role assignments. The other thirteen AMBA assignments (Connectivity and Connectivity 2, Identity, Management, VM, VMSS, Hybrid VM, Key Management, Load Balancing, Network Changes, Recovery Services, Storage, Web) are in the Terraform version. To deploy all of them with ARM, use AMBA's `alzArm.json` with its parameter file as AMBA's "Deploy with Azure CLI" page shows, in a test hierarchy, and expect them in `Default` mode.

### Destroy (Bicep)

Remove AMBA first (if you deployed it), then the baseline. Bash:

```bash
MG=alz                                            # where amba.bicep was deployed
SUB=00000000-0000-0000-0000-000000000000          # the management subscription
SCOPE="/providers/Microsoft.Management/managementGroups/$MG"

# 1. The two AMBA assignments, and the role assignments held by their managed identities
#    (--all covers subscriptions and below, so list the management group scope too)
for PA in Deploy-AMBA-Res-SvcHlth Deploy-AMBA-Notification; do
  PRINCIPAL=$(az policy assignment show --name "$PA" --scope "$SCOPE" --query identity.principalId -o tsv)
  [ -z "$PRINCIPAL" ] && continue
  for RA in $(az role assignment list --all --assignee "$PRINCIPAL" --query "[].id" -o tsv) \
            $(az role assignment list --scope "$SCOPE" --assignee "$PRINCIPAL" --query "[].id" -o tsv); do
    az role assignment delete --ids "$RA"
  done
  az policy assignment delete --name "$PA" --scope "$SCOPE"
done

# 2. AMBA initiatives, then AMBA definitions (all carry the metadata _deployed_by_amba)
for SET in $(az policy set-definition list --management-group "$MG" --query "[?metadata._deployed_by_amba].name" -o tsv); do
  az policy set-definition delete --name "$SET" --management-group "$MG"
done
for DEF in $(az policy definition list --management-group "$MG" --query "[?metadata._deployed_by_amba].name" -o tsv); do
  az policy definition delete --name "$DEF" --management-group "$MG"
done

# 3. Optional: the AMBA deployment records
for D in $(az deployment mg list --management-group-id "$MG" --query "[?starts_with(name, 'ch12-amba')].name" -o tsv); do
  az deployment mg delete --management-group-id "$MG" --name "$D"
done

# 4. The baseline. Delete the workspace permanently first; otherwise it stays
#    soft-deleted for 14 days.
az monitor log-analytics workspace delete --subscription $SUB \
  --resource-group rg-alz-management-uksouth --workspace-name log-alz-uksouth --force --yes
az group delete --subscription $SUB --name rg-alz-management-uksouth --yes
az deployment sub delete --subscription $SUB --name ch12-management
az deployment sub delete --subscription $SUB --name ch12-rg        # the resource group module's own record
```

If you ran `amba.bicep` in `Default` mode or ran remediation, also run AMBA's clean-up script (see [Destroy (Terraform)](#destroy-terraform)) to remove the `rg-amba-monitoring-001` resource groups, alerts, alert processing rules and action groups the policies created in each subscription.

## Inputs

| Terraform | Bicep (`main.bicep`) | Default | Notes |
| --- | --- | --- | --- |
| `subscription_id` | (the subscription you deploy to) | none, required | The management subscription. |
| `prefix` | `prefix` | `alz` | Name prefix. |
| `location` | `location` | `uksouth` | Region of the regional resources. |
| `resource_group_name` | `resourceGroupName` | `rg-<prefix>-management-<location>` | |
| `log_analytics_retention_in_days` | `logAnalyticsRetentionInDays` | `30` | 30-730. |
| `log_analytics_daily_quota_gb` | `logAnalyticsDailyQuotaGb` | `null` / `-1` (no cap) | See [Cost](#cost). |
| `action_group_email_addresses` | `actionGroupEmailAddresses` | `[]` | Each new address needs OTP verification. |
| `action_group_short_name` | `actionGroupShortName` | `<prefix>-platform`, cut to 12 | 1-12 characters. |
| `service_health_alert_enabled` | `serviceHealthAlertEnabled` | `true` | |
| `service_health_event_types` | `serviceHealthEventTypes` | all five | `Incident`, `Maintenance`, `Informational`, `ActionRequired`, `Security`. |
| `service_health_regions` | `serviceHealthRegions` | `[]` (all) | Service Health region names, for example `"UK South"`, `"Global"`. |
| `tags` | `tags` | `{}` | |
| `enable_telemetry` | `enableTelemetry` | `true` | AVM telemetry. No cost. |

AMBA inputs:

| Terraform | Bicep (`amba.bicep`) | Default | Notes |
| --- | --- | --- | --- |
| `deploy_amba` | (run `amba.bicep` or not) | `false` | Opt-in. |
| `amba_management_group_id` | `--management-group-id` | `alz` | Existing management group. Terraform: run `set-amba-scope` to change it. |
| `amba_enforcement_mode` | `enforcementMode` | `DoNotEnforce` | `Default` deploys alerts into the subscriptions below. |
| `amba_use_platform_action_group` | `byoActionGroupIds` | `true` / the platform action group | AMBA's "bring your own notifications": its alert processing rule and Service Health alerts use the platform action group. |
| `amba_action_group_email_addresses` | `actionGroupEmailAddresses` | `[]` | Only used when AMBA doesn't use the platform action group. |
| `amba_resource_group_name` | `ambaResourceGroupName` | `rg-amba-monitoring-001` | AMBA's per-subscription resource group name (and, in Terraform, where its identity lives). |
| `amba_user_assigned_managed_identity_name` | n/a | `id-amba-prod-001` | Terraform only; the Bicep subset doesn't use it. |
| n/a | `ambaRelease` | `2026-06-03` | AMBA release tag of the linked templates. |

## Feeding chapter 6

Chapter 6 deploys the ALZ policies with placeholder resource IDs. Pass this chapter's outputs to its `policy_default_values` and the AMA, VM insights and activity log policies point at real resources:

| Chapter 6 `policy_default_values` key | This chapter's output (Terraform / Bicep) |
| --- | --- |
| `log_analytics_workspace_id` | `log_analytics_workspace_id` / `logAnalyticsWorkspaceId` |
| `ama_vm_insights_data_collection_rule_id` | `vm_insights_data_collection_rule_id` / `vmInsightsDataCollectionRuleId` |
| `ama_user_assigned_managed_identity_id` | `ama_user_assigned_identity.id` / `amaIdentityId` |
| `ama_user_assigned_managed_identity_name` | `ama_user_assigned_identity.name` / `amaIdentityName` |

The library also asks for change tracking and Defender for SQL data collection rules (`ama_change_tracking_data_collection_rule_id`, `ama_mdfc_sql_data_collection_rule_id`); this chapter builds only the VM insights one.

## Cost

With the defaults, close to nothing while nothing sends data:

- **Log Analytics workspace:** pay-as-you-go (`PerGB2018`), billed per GB ingested. 31 days of analytics retention are included in the ingestion price, so the 30-day default adds no retention charge. Nothing in this chapter sends data to it (no diagnostic settings, agents or VMs). Chapter 6's policies in `Default` mode, or VMs associated with the data collection rule, start ingestion and billing.
- **Daily cap:** off by default. When a cap is reached, collection **stops** until the workspace's daily reset hour, which you can't choose. Learn's advice is to use it as protection against unexpected spikes, not as routine cost control.
- **Data collection rule, user-assigned identity, resource group, action group:** no charge for the resources themselves.
- **Service Health alert:** activity log, Service Health and Resource Health alerts are free. Notifications sent through action groups are billed under Azure Monitor pricing; a test sends a handful of emails.
- **AMBA in `DoNotEnforce`:** policy definitions, initiatives and assignments are free, and nothing is deployed into subscriptions. The AMBA identity and its resource group are free.
- **AMBA in `Default` (or after remediation):** the policies create metric alert rules (billed per monitored time series), log search alert rules (billed by evaluation frequency) and activity log alerts (free) for matching resources in every subscription under the management group, plus notification charges. This is the real running cost of AMBA, and it grows with the estate.

## How it works

The chapter's Build it text is written from these points.

1. **One workspace, `PerGB2018`, 30 days** (`module "log_analytics"` / `module logAnalytics`). A single central workspace in the management subscription is the ALZ default; retention is 30 days because the first 31 are included in the price. In Terraform, `log_analytics_workspace_internet_ingestion_enabled = "true"` and `log_analytics_workspace_internet_query_enabled = "true"` are set on purpose: the AVM module defaults both to `"false"`, which closes the workspace to everything except a private link scope. The Bicep module leaves public access enabled but defaults retention to 365 days, so `dataRetention: 30` is set.
2. **The data collection rule is configuration, not collection** (`module "dcr_vm_insights"`). `counter_specifiers = ["\\VmInsights\\DetailedMetrics"]` on the `Microsoft-InsightsMetrics` stream, sent to the workspace, is the VM insights rule. Nothing flows until a machine running the Azure Monitor Agent is associated with it, which is what the ALZ VM monitoring policies do.
3. **The user-assigned identity exists for the policies** (`module "ama_identity"`). The ALZ AMA policies attach this one identity to VMs so the agent can authenticate, instead of turning on a system-assigned identity on every VM. Its ID and name are policy parameters in chapter 6.
4. **The action group is `global`** (`location = "global"`). Learn: Service Health alerts are only supported in the global region, so an action group meant for them must be global.
5. **Email receivers need OTP verification** (`dynamic "email_receiver"` / `emailReceivers`). The deployment succeeds either way; each new address must enter the passcode within 30 minutes or it receives nothing. The outputs list the addresses to chase.
6. **Service Health goes straight to the action group** (`azurerm_monitor_activity_log_alert.service_health`: `category = "ServiceHealth"`, `action { action_group_id = ... }`). Alert processing rules don't affect Service Health alerts, so a design that routes all notifications through processing rules would silently miss them. The CAF management design area says to configure Service Health alerts directly with the action group.
7. **AMBA comes from the library, like the ALZ policies** (`lib/alz_library_metadata.json` with `"path": "platform/amba", "ref": "2026.06.2"`, and `module "amba_policy"` using `Azure/avm-ptn-alz/azurerm`). The pattern module from chapter 6 deploys a different library. The architecture file puts every AMBA archetype (`amba_root`, `amba_landing_zones`, `amba_management`, `amba_connectivity`, `amba_identity`) on one existing management group (`"exists": true`), so nothing is added to the hierarchy.
8. **One switch for enforcement** (`local.amba_enforcement_overrides`, built from `data "alz_architecture" "amba"`). It lists every assignment the library version contains and sets them all to `DoNotEnforce`, so AMBA reports compliance without deploying alerts until you decide to.
9. **AMBA uses the platform action group** (`amba_alz_byo_action_group`). With "bring your own notifications", AMBA's alert processing rule and Service Health alerts point at the action group whose receivers are already verified, instead of creating action groups with new addresses in every subscription. The ID is built from names (`local.platform_action_group_id`) so the ALZ data source knows it at plan time on the first run.
10. **Bicep links AMBA's own templates from a pinned release** (`amba.bicep`, `templateLink.uri` with `ambaRelease = '2026-06-03'`). There's no AVM module for AMBA in Bicep, and the release's assignment templates accept an `enforcementMode` that its top-level template doesn't pass, so this file calls them directly.

## Versions

Checked against the Terraform registry, the Microsoft Container Registry and GitHub on 7 October 2026.

| Component | Version |
| --- | --- |
| Terraform | `~> 1.13` (validated with 1.13.4) |
| `Azure/avm-res-resources-resourcegroup/azurerm` | 0.4.0 |
| `Azure/avm-res-operationalinsights-workspace/azurerm` | 0.5.1 |
| `Azure/avm-res-insights-datacollectionrule/azurerm` | 0.1.0 |
| `Azure/avm-res-managedidentity-userassignedidentity/azurerm` | 0.5.3 |
| `Azure/avm-ptn-monitoring-amba-alz/azurerm` (AMBA identity) | 0.4.0 |
| `Azure/avm-ptn-alz/azurerm` (AMBA policies) | 0.22.0 |
| Action group and Service Health alert (Terraform) | `azurerm_monitor_action_group` and `azurerm_monitor_activity_log_alert`: the AVM Terraform modules for both are listed as "proposed" in the AVM module index and aren't published |
| Provider `hashicorp/azurerm` | `~> 4.81` (locked 4.81.0; the AVM modules require < 5.0) |
| Provider `Azure/azapi` | `~> 2.13` (locked 2.13.0) |
| Provider `Azure/alz` | `~> 0.22` (locked 0.22.0) |
| Providers `Azure/modtm`, `hashicorp/random`, `hashicorp/time` | locked 0.4.0, 3.9.1, 0.14.2 |
| Provider `hashicorp/local` (set-amba-scope helper) | `~> 2.9` |
| ALZ library | platform/amba 2026.06.2 |
| Bicep `br/public:avm/res/resources/resource-group` | 0.4.4 |
| Bicep `br/public:avm/res/operational-insights/workspace` | 0.16.1 |
| Bicep `br/public:avm/res/insights/data-collection-rule` | 0.11.0 |
| Bicep `br/public:avm/res/managed-identity/user-assigned-identity` | 0.6.0 |
| Bicep `br/public:avm/res/insights/action-group` | 0.8.0 |
| Bicep `br/public:avm/res/insights/activity-log-alert` | 0.4.2 |
| AMBA templates (`amba.bicep`) | release 2026-06-03 |
| Bicep CLI used to build | 0.48.1 |

## References

- Monitor Azure platform landing zone components (CAF management design area: AMBA, action groups, Service Health and alert processing rules): https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/management-monitor
- Action groups (email OTP verification; global region for Service Health): https://learn.microsoft.com/azure/azure-monitor/alerts/action-groups
- Alert processing rules (don't affect Service Health alerts): https://learn.microsoft.com/azure/azure-monitor/alerts/alerts-processing-rules
- Create Service Health alerts with Bicep and ARM: https://learn.microsoft.com/azure/service-health/alerts-activity-log-service-notifications-bicep and https://learn.microsoft.com/azure/service-health/alerts-activity-log-service-notifications-arm
- Deploy Service Health alerts at scale (built-in policy and AMBA): https://learn.microsoft.com/azure/service-health/service-health-alert-deploy-policy
- Log Analytics data retention: https://learn.microsoft.com/azure/azure-monitor/logs/data-retention-configure
- Daily cap: https://learn.microsoft.com/azure/azure-monitor/logs/daily-cap
- Azure Monitor service limits (retention beyond 31 days is charged): https://learn.microsoft.com/azure/azure-monitor/fundamentals/service-limits#log-analytics-workspaces
- Azure Monitor cost and usage; alert cost best practices: https://learn.microsoft.com/azure/azure-monitor/fundamentals/cost-usage and https://learn.microsoft.com/azure/azure-monitor/alerts/best-practices-alerts#cost-optimization
- Delete and recover a workspace (soft-delete, `--force`): https://learn.microsoft.com/azure/azure-monitor/logs/delete-workspace
- VM insights data collection rule: https://learn.microsoft.com/azure/virtual-machines/monitor-vm#data-collection-rules
- Data collection rule structure: https://learn.microsoft.com/azure/azure-monitor/data-collection/data-collection-rule-structure
- CAF resource abbreviations: https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations
- AMBA-ALZ deployment introduction, prerequisites and permissions: https://azure.github.io/azure-monitor-baseline-alerts/patterns/alz/HowTo/deploy/Introduction-to-deploying-the-ALZ-Pattern/
- AMBA-ALZ with Terraform: https://azure.github.io/azure-monitor-baseline-alerts/patterns/alz/HowTo/deploy/Deploy-with-Terraform/
- AMBA-ALZ with Azure CLI (ARM templates): https://azure.github.io/azure-monitor-baseline-alerts/patterns/alz/HowTo/deploy/Deploy-with-Azure-CLI/
- AMBA bring your own notifications: https://azure.github.io/azure-monitor-baseline-alerts/patterns/alz/HowTo/Bring-your-own-Notifications/
- AMBA clean-up: https://azure.github.io/azure-monitor-baseline-alerts/patterns/alz/HowTo/Cleaning-up-a-Deployment/
- AMBA option in the ALZ Terraform accelerator: https://azure.github.io/Azure-Landing-Zones/accelerator/starter-terraform/options/amba/
- Terraform modules: https://registry.terraform.io/modules/Azure/avm-res-operationalinsights-workspace/azurerm/0.5.1, https://registry.terraform.io/modules/Azure/avm-res-insights-datacollectionrule/azurerm/0.1.0, https://registry.terraform.io/modules/Azure/avm-res-managedidentity-userassignedidentity/azurerm/0.5.3, https://registry.terraform.io/modules/Azure/avm-ptn-monitoring-amba-alz/azurerm/0.4.0, https://registry.terraform.io/modules/Azure/avm-ptn-alz/azurerm/0.22.0
- AMBA library: https://github.com/Azure/Azure-Landing-Zones-Library/tree/platform/amba/2026.06.2/platform/amba
- AMBA templates: https://github.com/Azure/azure-monitor-baseline-alerts/tree/2026-06-03/patterns/alz
