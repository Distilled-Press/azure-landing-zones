// Chapter 12: management baseline.
// A resource group with the central Log Analytics workspace, a VM insights data
// collection rule, the user-assigned identity for the Azure Monitor Agent
// policies, the platform action group and a Service Health alert wired
// straight to it. Deploy at subscription scope (the management subscription).
// AMBA-ALZ is a separate, opt-in deployment: see amba.bicep.
targetScope = 'subscription'

@description('Prefix used in the names this template creates.')
param prefix string = 'alz'

@description('Region of the resource group, workspace, data collection rule and identity.')
param location string = 'uksouth'

@description('Name of the management resource group. Default: rg-<prefix>-management-<location>.')
param resourceGroupName string = 'rg-${prefix}-management-${location}'

@description('Tags for every resource created here.')
param tags object = {}

// ---------- Log Analytics workspace ----------

@description('Analytics retention in days (30-730). The first 31 days are included in the ingestion price.')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionInDays int = 30

@description('Optional daily cap in GB. -1 (default) means no cap. When the cap is reached, collection stops until the daily reset hour.')
param logAnalyticsDailyQuotaGb int = -1

// ---------- Action group and Service Health ----------

@description('Email receivers for the platform action group. Each NEW address must complete one-time passcode verification within 30 minutes (see README).')
param actionGroupEmailAddresses string[] = []

@description('Short name shown in notifications (1-12 characters).')
@minLength(1)
@maxLength(12)
param actionGroupShortName string = take('${prefix}-platform', 12)

@description('Create the Service Health activity log alert, wired directly to the action group.')
param serviceHealthAlertEnabled bool = true

@description('Service Health event types: Incident, Maintenance, Informational, ActionRequired, Security.')
param serviceHealthEventTypes ('Incident' | 'Maintenance' | 'Informational' | 'ActionRequired' | 'Security')[] = [
  'Incident'
  'Maintenance'
  'Informational'
  'ActionRequired'
  'Security'
]

@description('Regions to alert on, as Service Health names them (for example "UK South", "Global"). Empty means all regions.')
param serviceHealthRegions string[] = []

@description('AVM module usage telemetry. No cost.')
param enableTelemetry bool = true

// One condition per event type, any of which fires the alert.
var serviceHealthEventConditions = [
  for t in serviceHealthEventTypes: {
    field: 'properties.incidentType'
    equals: t
  }
]

// ---------- Resource group ----------

module resourceGroup 'br/public:avm/res/resources/resource-group:0.4.4' = {
  name: 'ch12-rg'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

// ---------- Central Log Analytics workspace ----------

module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.16.1' = {
  name: 'ch12-log'
  scope: az.resourceGroup(resourceGroupName)
  dependsOn: [resourceGroup]
  params: {
    name: 'log-${prefix}-${location}'
    location: location
    skuName: 'PerGB2018'
    dataRetention: logAnalyticsRetentionInDays // the module's default is 365
    dailyQuotaGb: string(logAnalyticsDailyQuotaGb)
    forceCmkForQuery: false // no customer-managed key in this example
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

// ---------- Data collection rule: VM insights ----------

module dcrVmInsights 'br/public:avm/res/insights/data-collection-rule:0.11.0' = {
  name: 'ch12-dcr'
  scope: az.resourceGroup(resourceGroupName)
  dependsOn: [resourceGroup]
  params: {
    name: 'dcr-${prefix}-vminsights-${location}'
    location: location
    dataCollectionRuleProperties: {
      kind: 'All' // Windows and Linux
      description: 'VM insights performance counters (InsightsMetrics) for Windows and Linux machines.'
      dataSources: {
        performanceCounters: [
          {
            name: 'VMInsightsPerfCounters'
            streams: ['Microsoft-InsightsMetrics']
            samplingFrequencyInSeconds: 60
            counterSpecifiers: ['\\VmInsights\\DetailedMetrics']
          }
        ]
      }
      destinations: {
        logAnalytics: [
          {
            name: 'VMInsightsPerf-Logs-Dest'
            workspaceResourceId: logAnalytics.outputs.resourceId
          }
        ]
      }
      dataFlows: [
        {
          streams: ['Microsoft-InsightsMetrics']
          destinations: ['VMInsightsPerf-Logs-Dest']
        }
      ]
    }
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

// ---------- User-assigned identity for the Azure Monitor Agent policies ----------

module amaIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.6.0' = {
  name: 'ch12-id-ama'
  scope: az.resourceGroup(resourceGroupName)
  dependsOn: [resourceGroup]
  params: {
    name: 'id-${prefix}-ama-${location}'
    location: location
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

// ---------- Platform action group ----------
// Location must be 'global' for Service Health alerts to reach it.

module actionGroup 'br/public:avm/res/insights/action-group:0.8.0' = {
  name: 'ch12-ag'
  scope: az.resourceGroup(resourceGroupName)
  dependsOn: [resourceGroup]
  params: {
    name: 'ag-${prefix}-platform'
    groupShortName: actionGroupShortName
    location: 'global'
    emailReceivers: [
      for (address, i) in actionGroupEmailAddresses: {
        name: 'email-${i + 1}'
        emailAddress: address
        useCommonAlertSchema: true
      }
    ]
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

// ---------- Service Health alert ----------
// Wired straight to the action group: alert processing rules don't apply to
// Service Health alerts.

module serviceHealthAlert 'br/public:avm/res/insights/activity-log-alert:0.4.2' = if (serviceHealthAlertEnabled) {
  name: 'ch12-alert-sh'
  scope: az.resourceGroup(resourceGroupName)
  dependsOn: [resourceGroup]
  params: {
    name: 'alert-${prefix}-servicehealth'
    location: 'global'
    alertDescription: 'Service Health events for this subscription, sent directly to ag-${prefix}-platform.'
    scopes: [subscription().id]
    conditions: concat(
      [
        {
          field: 'category'
          equals: 'ServiceHealth'
        }
        {
          anyOf: serviceHealthEventConditions
        }
      ],
      empty(serviceHealthRegions)
        ? []
        : [
            {
              field: 'properties.impactedServices[*].ImpactedRegions[*].RegionName'
              containsAny: serviceHealthRegions
            }
          ]
    )
    actions: [
      {
        actionGroupId: actionGroup.outputs.resourceId
      }
    ]
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

output resourceGroupName string = resourceGroupName
output logAnalyticsWorkspaceId string = logAnalytics.outputs.resourceId
output vmInsightsDataCollectionRuleId string = dcrVmInsights.outputs.resourceId
output amaIdentityId string = amaIdentity.outputs.resourceId
output amaIdentityName string = amaIdentity.outputs.name
output actionGroupId string = actionGroup.outputs.resourceId
@description('Addresses that must complete the one-time passcode verification within 30 minutes.')
output actionGroupEmailReceiversToVerify string[] = actionGroupEmailAddresses
