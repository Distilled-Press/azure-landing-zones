# Chapter 11: Security baseline

Companion code for the "Build it" section of chapter 11. It applies a security baseline to **one subscription** (input): Microsoft Defender for Cloud's free settings, opt-in paid Defender plans, and an opt-in Microsoft Sentinel workspace.

```
Subscription <subscription_id>
├── Defender for Cloud
│   ├── security contact "default"       emails for alerts and attack paths            free
│   ├── foundational CSPM                on for every subscription, nothing deployed     free
│   └── paid plans from defender_plans   default: NONE                                   billed
└── deploy_sentinel = true only (default false)
    └── rg-alz-security-uksouth
        └── law-alz-security-uksouth     Log Analytics, PerGB2018, 30-day retention      billed per GB
            ├── Microsoft Sentinel onboarding
            └── <- subscription Activity log (Azure Activity data connector)              free table
```

| Folder | What it deploys |
| --- | --- |
| `terraform/` | `azapi` for the security contact, `azurerm` for plans, workspace, Sentinel onboarding and the Activity log diagnostic setting. |
| `bicep/` | Subscription-scope deployment with AVM modules: `avm/ptn/security/security-center` (contact and plans), `avm/res/resources/resource-group`, `avm/res/operational-insights/workspace` (with Sentinel onboarding) and `avm/res/insights/diagnostic-setting`. |

Tested: 8 October 2026 (Terraform 1.13.4, Bicep CLI 0.48.1, Azure CLI 2.91.0): Terraform apply with the defaults (security contact only), then with `deploy_sentinel = true` (workspace, Sentinel onboarding, Activity log diagnostic setting), and destroy; Bicep deployment with the defaults and with `deploySentinel = true`, and the clean-up commands below, in a test subscription. Every Defender plan tier was checked before and after: neither version changed any plan, and destroy/clean-up left no security contact. Paid Defender plans (`defender_plans` / `defenderPlans`) weren't applied, to avoid charges; their reset to Free on destroy is untested.

## Read this first: Defender plans are subscription-wide

**A Defender plan is switched on for the whole subscription, not for the resources this code creates.** Turning on `VirtualMachines` covers every VM (and Arc-connected server) in the subscription, `StorageAccounts` every storage account, and so on, and each is billed for every covered resource. By default this code turns on **no** paid plan.

**Turning a plan off again is the clean-up step.** Terraform does it for you: `terraform destroy`, or removing a key from `defender_plans`, sets that plan back to Free. In Bicep there's no destroy, so set each plan back to Free with the CLI (below). Turning a plan off doesn't uninstall extensions it deployed to resources; they stop collecting data after a short time.

The same applies the other way round: if someone else has already enabled a plan on the subscription, this code leaves it alone unless you list that plan. The AVM Bicep module would set **every** plan to Free if its `defenderPlans` parameter were left out, which is why `main.bicep` always passes the array (empty by default).

## Prerequisites

- **A subscription to test in.** A dedicated test or sandbox subscription is best, because the security contact and any plans you enable apply to all of it.
- **Azure CLI**, signed in with `az login`.
- **Permissions** on the subscription: Owner covers everything. With less:
  - security contact and Defender plans: Security Admin, Contributor or Owner (Learn notes that the Defender CSPM plan's agentless scanning only works if a subscription Owner enables the plan);
  - resource group, workspace and Sentinel onboarding: Contributor (or Log Analytics Contributor plus Microsoft Sentinel Contributor on the resource group);
  - the subscription diagnostic setting: Monitoring Contributor or Contributor;
  - resource provider registration (below): Contributor or Owner.
- **Resource providers.** Terraform registers `Microsoft.Security`, `Microsoft.OperationalInsights`, `Microsoft.SecurityInsights` and `Microsoft.Insights` itself (`resource_providers_to_register` in `terraform.tf`; the `azurerm` 5.x provider registers nothing by default). For Bicep, register them first, plus `Microsoft.OperationsManagement` for the Sentinel solution resource:
  ```bash
  for NS in Microsoft.Security Microsoft.OperationalInsights Microsoft.OperationsManagement Microsoft.SecurityInsights Microsoft.Insights; do
    az provider register --namespace $NS --subscription <subscription-id>
  done
  ```
  Registration is free, and neither version unregisters anything.
- **Licences:** none for this code. Defender for Cloud plans and Sentinel are billed per use through the subscription, not licensed per user. (Some Sentinel data sources, such as Microsoft Entra ID sign-in logs, need their own licences; none are connected here.)
- **Tools:** Terraform 1.13 or later; Bicep CLI 0.48 or later; Azure CLI 2.53.0 or later to deploy a `.bicepparam` file.

## Deploy and destroy: Terraform

```bash
cd chapters/11-security-baseline/terraform
cp terraform.tfvars.example terraform.tfvars    # set subscription_id and security_contact_emails
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

Sentinel, when you want it: set `deploy_sentinel = true` (and leave `connect_azure_activity = true`) and apply again.

Destroy:

```bash
terraform destroy
```

This removes the Activity log diagnostic setting, the Sentinel onboarding, the workspace (permanently: `permanently_delete_on_destroy = true` skips the 14-day soft delete so the name can be reused), the resource group and the security contact, and **sets every plan in `defender_plans` back to Free**. The Activity log diagnostic setting is the slow part: its delete can take over 11 minutes, because the provider waits until the subscription's list of diagnostic settings stops showing it, which lags behind the delete itself. Afterwards the subscription is back to Defender for Cloud's defaults: foundational CSPM only, and with no security contact, Defender for Cloud's default of emailing subscription owners about high-severity alerts and attack paths.

## Deploy and destroy: Bicep

```bash
cd chapters/11-security-baseline/bicep
# edit main.bicepparam: securityContactEmails, and deploySentinel if you want Sentinel
az deployment sub what-if --subscription <subscription-id> --location uksouth --name ch11-security --parameters main.bicepparam
az deployment sub create  --subscription <subscription-id> --location uksouth --name ch11-security --parameters main.bicepparam
```

Bicep has no destroy. Clean up in this order (Bash):

```bash
SUB=00000000-0000-0000-0000-000000000000
NAME=alz-security-uksouth          # <prefix>-security-<location>

# 1. Defender plans: set EVERY plan you listed in defenderPlans back to Free (one line per plan)
az security pricing create --name VirtualMachines --tier free --subscription $SUB
#    check every plan's tier: az security pricing list --subscription $SUB -o table

# 2. Security contact
az security contact delete --name default --subscription $SUB --yes

# 3. Sentinel (only if deploySentinel = true): the Activity log export, then the resource group
az monitor diagnostic-settings subscription delete --name activity-to-$NAME --subscription $SUB --yes
az monitor log-analytics workspace delete --resource-group rg-$NAME --workspace-name law-$NAME \
  --subscription $SUB --force --yes      # --force skips the 14-day soft delete
az group delete --name rg-$NAME --subscription $SUB --yes

# 4. Optional: the deployment records (the top-level one and the module deployments at subscription scope)
for D in ch11-security ch11-alz-defender ch11-alz-rg ch11-alz-activity; do   # ch11-<prefix>-...
  az deployment sub delete --name $D --subscription $SUB
done
```

`az security contact` is marked Preview in the Azure CLI.

### Sentinel and the Defender portal

Microsoft Sentinel in the Azure portal is retired after 31 March 2027; from then on it's available only in the Microsoft Defender portal. Since July 2025, when the **first** workspace in a tenant is onboarded to Sentinel by a subscription Owner or User Access Administrator, it's onboarded to the Defender portal automatically, and Azure portal links redirect there. In a fresh test tenant the workspace this code creates may therefore become the tenant's primary Sentinel workspace in the Defender portal. Deleting it removes it; if you later want a different primary workspace, connect it under **System > Settings > Microsoft Sentinel > Workspaces** in the Defender portal.

## Inputs

| Terraform | Bicep | Default | Notes |
| --- | --- | --- | --- |
| `subscription_id` | `--subscription` on the CLI | none (required) | The subscription the baseline applies to. |
| `prefix` | `prefix` | `alz` | Used in resource names. |
| `location` | `location` | `uksouth` / deployment location | Sentinel resource group and workspace region. |
| `tags` | `tags` | `{}` | Resource group and workspace. |
| `security_contact_emails` | `securityContactEmails` | none (required) | Joined with `;` into the contact's `emails`. |
| `security_contact_phone` | `securityContactPhone` | `""` | |
| `notify_roles` | `notifyRoles` | `["Owner"]` | Also email holders of these subscription roles (`AccountAdmin`, `ServiceAdmin`, `Owner`, `Contributor`). `[]` turns this off. |
| `alert_minimal_severity` | `alertMinimalSeverity` | `Medium` | `High`, `Medium` or `Low`. |
| `attack_path_minimal_risk_level` | `attackPathMinimalRiskLevel` | `Critical` | Attack paths come from the paid Defender CSPM plan. |
| `defender_plans` | `defenderPlans` | none | **Paid**, subscription-wide. See below. |
| `deploy_sentinel` | `deploySentinel` | `false` | **Billable** once data other than free tables flows. |
| `log_retention_days` | `logRetentionDays` | `30` | 30-730. |
| `connect_azure_activity` | `connectAzureActivity` | `true` | Only with Sentinel. |
| n/a | `enableTelemetry` | `true` | AVM usage telemetry. No cost. |

### Defender plans

Terraform: a map keyed by plan name. Bicep: an array of `{ name, pricingTier: 'Standard', subPlan?, extensions? }` (the AVM module's `defenderPlanType`).

```hcl
defender_plans = {
  VirtualMachines = { subplan = "P1" }                    # Defender for Servers Plan 1 (P2 for Plan 2)
  StorageAccounts = { subplan = "DefenderForStorageV2" }  # Defender for Storage
  KeyVaults       = {}                                    # Defender for Key Vault
  CloudPosture    = {}                                    # Defender CSPM (paid)
}
```

Plan names the Terraform validation accepts: `AI`, `Api`, `AppServices`, `Arm`, `CloudPosture`, `Containers`, `CosmosDbs`, `KeyVaults`, `OpenSourceRelationalDatabases`, `SqlServers`, `SqlServerVirtualMachines`, `StorageAccounts`, `VirtualMachines`. Extensions are opt-in too: an extension you don't list isn't enabled (`extensions = { AgentlessVmScanning = {} }` in Terraform, `extensions: [{ name: 'AgentlessVmScanning', isEnabled: 'True' }]` in Bicep).

### Auto-provisioning

There's no auto-provisioning setting in this code, on purpose. The legacy Log Analytics agent (MMA) auto-provisioning that older baselines set is retired: it can no longer be enabled on new subscriptions, and since the end of November 2024 not on existing ones either. Defender for Servers now uses agentless machine scanning and the Microsoft Defender for Endpoint integration, configured as **extensions of the plan** (for example `AgentlessVmScanning`), so they only come with a paid plan you choose. The Azure Monitor Agent is still used for Defender for Servers Plan 2's 500 MB data ingestion benefit and is covered in chapter 12.

## Cost

**With the defaults this costs nothing.** The security contact and foundational CSPM are free, no paid plan is enabled and no workspace is created.

What costs, all off by default:

- **Defender plans** (`defender_plans` / `defenderPlans`). Each plan bills for every covered resource in the subscription (per server per hour, per storage account, per vault and so on). Prices by plan: https://azure.microsoft.com/pricing/details/defender-for-cloud/ and the estimator https://learn.microsoft.com/azure/defender-for-cloud/cost-calculator. Learn notes a 30-day free trial for some plans, after which charges start; Defender for Storage malware scanning is charged from the first day.
- **Sentinel** (`deploy_sentinel` / `deploySentinel`). The empty workspace has no fixed charge on the pay-as-you-go (`PerGB2018`) tier; you pay per GB ingested into the analytics tier, for Log Analytics and Sentinel analysis (https://azure.microsoft.com/pricing/details/microsoft-sentinel/). With only this code's data source it stays near zero:
  - the Azure Activity log (`AzureActivity` table) is a free data source for Sentinel and isn't charged for ingestion in Log Analytics;
  - Defender for Cloud security alerts (`SecurityAlert`) are free too;
  - a new Sentinel workspace gets a 31-day free trial for the first 10 GB a day in the analytics tier (up to 20 workspaces per tenant);
  - analytics-tier retention up to 90 days is included for Sentinel-enabled workspaces; this code keeps 30.

  Anything you connect later (Entra ID sign-in logs, Windows security events, firewall logs) is billed by volume, and automation (Logic Apps) and other services have their own charges.

## How it works

The lines the chapter's Build it text is written from:

1. **One security contact per subscription, named `default`.** `azapi_resource "security_contact"` with `type = "Microsoft.Security/securityContacts@2023-12-01-preview"` (Bicep: `securityContactProperties` on the AVM module, which uses the same API). `emails` is one `;`-separated string; `notificationsSources` sets the thresholds for **alerts** (`minimalSeverity`) and **attack paths** (`minimalRiskLevel`); `notificationsByRole` also emails holders of chosen roles. Terraform uses `azapi` here because `azurerm_security_center_contact` still calls the 2020 API, which has no attack path setting.
2. **Foundational CSPM needs no code.** Secure score, recommendations, asset inventory and the Microsoft cloud security benchmark are free and on by default for every subscription. The baseline's job is to make sure someone is told (point 1) and that paid plans are a deliberate choice (point 3).
3. **Paid plans are data, empty by default.** `for_each = var.defender_plans` on `azurerm_security_center_subscription_pricing` with `tier = "Standard"`, `subplan` and `extension` blocks. In Bicep, `defenderPlans: defenderPlans` with a default of `[]`, never omitted (omitting it makes the AVM module set every plan to Free). Each entry is a `Microsoft.Security/pricings/<plan>` setting for the whole subscription, and removing it is how you turn the plan off.
4. **Sentinel is a switch.** `count = var.deploy_sentinel ? 1 : 0` on the resource group, workspace (`sku = "PerGB2018"`, `retention_in_days = 30`) and `azurerm_sentinel_log_analytics_workspace_onboarding`. The onboarding is a single child resource of the workspace (`Microsoft.SecurityInsights/onboardingStates/default`): Sentinel isn't a separate resource, it's a mode of a Log Analytics workspace. In Bicep the AVM workspace module creates the onboarding when `onboardWorkspaceToSentinel: true` **and** the `SecurityInsights(<workspace>)` gallery solution is listed.
5. **The Azure Activity connector is a diagnostic setting.** The connector now uses the diagnostic settings pipeline, so in code it's `azurerm_monitor_diagnostic_setting` with `target_resource_id = "/subscriptions/<id>"`, the workspace as destination, and one `enabled_log` per Activity log category (Administrative, Security, ServiceHealth, Alert, Recommendation, Policy, Autoscale, ResourceHealth). In Bicep, `avm/res/insights/diagnostic-setting` with `metricCategories: []`, because the Activity log has no metrics. The connector page in Sentinel shows Connected once data has arrived. The connector's analytics rules and workbooks come from the **Azure Activity** solution in the content hub; installing it is a portal (or content-as-code) step and isn't done here.
6. **Destroy is part of the design.** Terraform's pricing resource resets the plan to Free on delete, and `permanently_delete_on_destroy` stops the workspace lingering in soft delete; the Bicep clean-up list does the same by hand.

### Why these modules

- **Terraform:** there's no AVM Terraform module for Defender for Cloud settings. The AVM Log Analytics module (`Azure/avm-res-operationalinsights-workspace/azurerm` 0.5.1) requires `azurerm` below 5.0 and has no Sentinel onboarding, so the workspace is a plain `azurerm_log_analytics_workspace`; it's one resource.
- **Bicep:** all AVM. `avm/ptn/security/security-center` sets both the contact and the plans; the workspace module handles Sentinel onboarding; the diagnostic-setting module is the subscription Activity log export.

## Versions

Checked against the Terraform registry and the Microsoft Container Registry on 7 October 2026.

| Component | Version |
| --- | --- |
| Terraform | `~> 1.13` (validated with 1.13.4) |
| Provider `hashicorp/azurerm` | `~> 5.8` (locked 5.8.0) |
| Provider `Azure/azapi` | `~> 2.13` (locked 2.13.0) |
| Bicep CLI | 0.48.1 |
| `br/public:avm/ptn/security/security-center` | 0.3.0 |
| `br/public:avm/res/resources/resource-group` | 0.4.4 |
| `br/public:avm/res/operational-insights/workspace` | 0.16.1 (uses `avm/res/operations-management/solution` 0.3.1; onboarding API `Microsoft.SecurityInsights/onboardingStates@2025-09-01`) |
| `br/public:avm/res/insights/diagnostic-setting` | 0.1.4 |
| Security contact API | `Microsoft.Security/securityContacts@2023-12-01-preview` |

## References

- Connect your Azure subscriptions (foundational CSPM, free trial, turning plans off): https://learn.microsoft.com/azure/defender-for-cloud/connect-azure-subscription
- Cloud security posture management (foundational vs Defender CSPM): https://learn.microsoft.com/azure/defender-for-cloud/concept-cloud-security-posture-management
- Protect your resources with Defender CSPM (Owner needed for agentless scanning): https://learn.microsoft.com/azure/defender-for-cloud/tutorial-enable-cspm-plan
- Configure email notifications for alerts and attack paths: https://learn.microsoft.com/azure/defender-for-cloud/configure-email-notifications
- `Microsoft.Security/securityContacts` template reference: https://learn.microsoft.com/azure/templates/microsoft.security/securitycontacts
- Prepare for retirement of the Log Analytics agent (auto-provisioning deprecation): https://learn.microsoft.com/azure/defender-for-cloud/prepare-deprecation-log-analytics-mma-agent
- Defender for Servers (agentless scanning and Defender for Endpoint replace the agents): https://learn.microsoft.com/azure/defender-for-cloud/defender-for-servers-overview
- Defender for Cloud pricing: https://azure.microsoft.com/pricing/details/defender-for-cloud/ and cost calculator https://learn.microsoft.com/azure/defender-for-cloud/cost-calculator
- Onboard Microsoft Sentinel: https://learn.microsoft.com/azure/sentinel/quickstart-onboard
- `Microsoft.SecurityInsights/onboardingStates` template reference: https://learn.microsoft.com/azure/templates/microsoft.securityinsights/onboardingstates
- Sentinel in the Azure portal retirement and changes for new customers: https://learn.microsoft.com/azure/sentinel/overview#microsoft-sentinel-in-the-azure-portal-retirement-timeline
- Connect Microsoft Sentinel to the Defender portal (primary workspace, offboarding): https://learn.microsoft.com/azure/sentinel/microsoft-sentinel-onboard
- Diagnostic settings-based connectors (Azure Activity uses the diagnostic settings pipeline): https://learn.microsoft.com/azure/sentinel/connect-services-diagnostic-setting-based
- Sentinel billing (free data sources, free trial): https://learn.microsoft.com/azure/sentinel/billing
- Sentinel data tiers and retention: https://learn.microsoft.com/azure/sentinel/manage-data-overview
- Azure Monitor Logs cost (AzureActivity not charged): https://learn.microsoft.com/azure/azure-monitor/logs/cost-logs
- Activity log diagnostic settings in Bicep: https://learn.microsoft.com/azure/azure-resource-manager/bicep/scenarios-monitoring#diagnostic-settings
- Remove Microsoft Sentinel from a workspace, and implications: https://learn.microsoft.com/azure/sentinel/offboard and https://learn.microsoft.com/azure/sentinel/offboard-implications
- CLI: `az security contact` https://learn.microsoft.com/cli/azure/security/contact, `az monitor diagnostic-settings subscription` https://learn.microsoft.com/cli/azure/monitor/diagnostic-settings/subscription
- `azurerm` 5.8.0 docs (`security_center_subscription_pricing` resets to Free on delete; provider registration defaults): https://registry.terraform.io/providers/hashicorp/azurerm/5.8.0/docs
- Bicep modules: https://github.com/Azure/bicep-registry-modules/tree/main/avm/ptn/security/security-center, https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/operational-insights/workspace, https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/insights/diagnostic-setting
