// Chapter 11: security baseline for one subscription.
// Deploy at subscription scope:
//   az deployment sub create --subscription <id> --location uksouth --name ch11-security --parameters main.bicepparam
targetScope = 'subscription'

import { defenderPlanType } from 'br/public:avm/ptn/security/security-center:0.3.0'

// ---------- Parameters ----------

@description('Prefix used in resource names.')
param prefix string = 'alz'

@description('Region for the Sentinel resource group and workspace (and the deployment metadata).')
param location string = deployment().location

@description('Tags for the resource group and workspace.')
param tags object = {}

// Defender for Cloud: email notifications (free)

@description('Email addresses that receive Defender for Cloud alert and attack path notifications.')
@minLength(1)
param securityContactEmails string[]

@description('Optional phone number recorded on the security contact.')
param securityContactPhone string = ''

@description('Subscription roles that also get the emails. [] turns role notifications off.')
@allowed([
  'AccountAdmin'
  'ServiceAdmin'
  'Owner'
  'Contributor'
])
param notifyRoles string[] = [
  'Owner'
]

@description('Lowest security alert severity that sends an email.')
@allowed([
  'High'
  'Medium'
  'Low'
])
param alertMinimalSeverity string = 'Medium'

@description('Lowest attack path risk level that sends an email. Attack paths come from the paid Defender CSPM plan.')
@allowed([
  'Critical'
  'High'
  'Medium'
  'Low'
])
param attackPathMinimalRiskLevel string = 'Critical'

// Defender for Cloud: paid plans (opt-in)

@description('PAID Defender plans to set, for the WHOLE subscription. Default []: none, so only the free foundational CSPM applies. Pricing: https://azure.microsoft.com/pricing/details/defender-for-cloud/')
param defenderPlans defenderPlanType[] = []

// Microsoft Sentinel (opt-in)

@description('Create a resource group and Log Analytics workspace and onboard Microsoft Sentinel to it. BILLABLE: see the README.')
param deploySentinel bool = false

@description('Workspace retention in days.')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 30

@description('With deploySentinel: send this subscription\'s Activity log to the workspace (what the Azure Activity data connector uses).')
param connectAzureActivity bool = true

@description('AVM usage telemetry.')
param enableTelemetry bool = true

// ---------- Variables ----------

var sentinelName = '${prefix}-security-${location}'
var resourceGroupName = 'rg-${sentinelName}'
var workspaceName = 'law-${sentinelName}'

// Activity log categories, the diagnostic setting categories for a subscription.
var activityLogCategories = [
  'Administrative'
  'Security'
  'ServiceHealth'
  'Alert'
  'Recommendation'
  'Policy'
  'Autoscale'
  'ResourceHealth'
]

// ---------- Defender for Cloud ----------

module defender 'br/public:avm/ptn/security/security-center:0.3.0' = {
  name: 'ch11-${prefix}-defender'
  params: {
    location: location
    // ALWAYS pass an array. If defenderPlans is left out (null), this module
    // sets every plan to Free, which would switch OFF paid plans someone else
    // enabled on the subscription. [] changes no plan at all.
    defenderPlans: defenderPlans
    // One contact per subscription; the module names it 'default'.
    securityContactProperties: {
      isEnabled: true
      emails: join(securityContactEmails, ';')
      phone: securityContactPhone
      notificationsByRole: {
        state: empty(notifyRoles) ? 'Off' : 'On'
        roles: notifyRoles
      }
      notificationsSources: [
        {
          sourceType: 'Alert'
          minimalSeverity: alertMinimalSeverity
        }
        {
          sourceType: 'AttackPath'
          minimalRiskLevel: attackPathMinimalRiskLevel
        }
      ]
    }
    enableTelemetry: enableTelemetry
  }
}

// ---------- Microsoft Sentinel (opt-in) ----------

module securityRg 'br/public:avm/res/resources/resource-group:0.4.4' = if (deploySentinel) {
  name: 'ch11-${prefix}-rg'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

module workspace 'br/public:avm/res/operational-insights/workspace:0.16.1' = if (deploySentinel) {
  name: 'ch11-${prefix}-law'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: workspaceName
    location: location
    skuName: 'PerGB2018'
    dataRetention: logRetentionDays // the module's default is 365
    // Sentinel onboarding (Microsoft.SecurityInsights/onboardingStates 'default')
    // happens only when the SecurityInsights solution is in this list too.
    gallerySolutions: [
      {
        name: 'SecurityInsights(${workspaceName})'
        plan: {
          product: 'OMSGallery/SecurityInsights'
          publisher: 'Microsoft'
        }
      }
    ]
    onboardWorkspaceToSentinel: true
    tags: tags
    enableTelemetry: enableTelemetry
  }
  dependsOn: [
    securityRg
  ]
}

// Azure Activity data connector = subscription Activity log -> Sentinel workspace
// through a diagnostic setting. AzureActivity data is free.
module activityToSentinel 'br/public:avm/res/insights/diagnostic-setting:0.1.4' = if (deploySentinel && connectAzureActivity) {
  name: 'ch11-${prefix}-activity'
  params: {
    name: 'activity-to-${sentinelName}'
    workspaceResourceId: workspace!.outputs.resourceId
    logCategoriesAndGroups: [
      for category in activityLogCategories: {
        category: category
      }
    ]
    metricCategories: [] // the Activity log has no metrics; the module would otherwise add AllMetrics
    location: location
    enableTelemetry: enableTelemetry
  }
}

// ---------- Outputs ----------

output defenderPlansSet array = defender.outputs.configuredDefenderPlans
output sentinelWorkspaceId string = deploySentinel ? workspace!.outputs.resourceId : ''
output sentinelResourceGroup string = deploySentinel ? resourceGroupName : ''
