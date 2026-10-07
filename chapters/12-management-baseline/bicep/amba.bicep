// Chapter 12, opt-in: Azure Monitor Baseline Alerts for Azure Landing Zones
// (AMBA-ALZ), representative subset, at one management group.
//
// AMBA-ALZ publishes its Bicep/ARM deployment as linked ARM templates in the
// AMBA repository (patterns/alz/alzArm.json and the files it links to); there
// is no AVM Bicep module for it. This file links the same templates from a
// pinned release:
//   1. every AMBA policy definition and initiative (definitions are free and
//      the initiatives reference definitions from several files), then
//   2. the two initiatives AMBA assigns at the intermediate root: Resource and
//      Service Health ("Deploy-AMBA-Res-SvcHlth") and Notification Assets
//      ("Deploy-AMBA-Notification"), with an enforcement mode switch.
// The full set of 15 assignments is in the Terraform version.
//
// Deploy at management group scope, AFTER main.bicep (it needs the action group):
//   az deployment mg create --management-group-id <mg> --location uksouth \
//     --name ch12-amba --parameters amba.bicepparam
targetScope = 'managementGroup'

@description('AMBA release tag the linked templates are taken from.')
param ambaRelease string = '2026-06-03'

@description('DoNotEnforce (default): report compliance only. Default: deploy Service Health alerts, alert processing rules and action groups into subscriptions under this management group.')
@allowed([
  'DoNotEnforce'
  'Default'
])
param enforcementMode string = 'DoNotEnforce'

@description('Resource IDs of existing action groups for AMBA to use ("bring your own notifications"), e.g. main.bicep\'s actionGroupId output. Leave empty to have AMBA create its own action groups emailing actionGroupEmailAddresses.')
param byoActionGroupIds string[] = []

@description('Only used when byoActionGroupIds is empty: emails for the action groups AMBA creates. Each new address needs OTP verification.')
param actionGroupEmailAddresses string[] = []

@description('Name of the resource group AMBA\'s policies create in each subscription for its alerts and notification assets.')
param ambaResourceGroupName string = 'rg-amba-monitoring-001'

@description('Region of that resource group.')
param ambaResourceGroupLocation string = 'uksouth'

@description('Tags on that resource group.')
param ambaResourceGroupTags object = {
  _deployed_by_amba: true
}

var baseUri = 'https://raw.githubusercontent.com/Azure/azure-monitor-baseline-alerts/${ambaRelease}/patterns/alz/'

var definitionFiles = [
  'Automation'
  'Compute'
  'Hybrid'
  'KeyManagement'
  'Monitoring'
  'Network'
  'NotificationAssets'
  'RecoveryServices'
  'ServiceHealth'
  'Storage'
  'Web'
]

var useByo = !empty(byoActionGroupIds)
var emails = useByo ? [] : actionGroupEmailAddresses

// The parameter sets alzArm.json builds for these two assignments, with the
// defaults from alzArm.param.json of the same release.
var commonParameters = {
  ALZMonitorResourceGroupName: { value: ambaResourceGroupName }
  ALZMonitorResourceGroupTags: { value: ambaResourceGroupTags }
  ALZMonitorResourceGroupLocation: { value: ambaResourceGroupLocation }
  ALZMonitorDisableTagName: { value: 'MonitorDisable' }
  ALZMonitorDisableTagValues: { value: ['true', 'Test', 'Dev', 'Sandbox'] }
}

var serviceHealthParameters = union(commonParameters, {
  ResHlthUnhealthyAlertState: { value: 'true' }
  ResHlthUnhealthyPolicyEffect: { value: 'deployIfNotExists' }
  ShaBuiltInEnableAlertRule: { value: 'true' }
  ShaBuiltInPolicyEffect: { value: 'DeployIfNotExists' }
  ShaBuiltInAlertRuleName: { value: 'ServiceHealthSubscriptionAlertRule' }
  ShaBuiltInEventTypes: { value: ['Service Issues', 'Planned Maintenance', 'Health Advisories', 'Security Advisories'] }
  BYOActionGroup: { value: byoActionGroupIds }
  ALZArmRoleId: { value: [] }
  AlzShaActionGroupResources: {
    value: {
      actionGroupEmail: emails
      logicappResourceId: ''
      logicappCallbackUrl: ''
      eventHubResourceId: []
      webhookServiceUri: []
      functionResourceId: ''
      functionTriggerUrl: ''
    }
  }
})

var notificationAssetParameters = union(commonParameters, {
  includeAlzAlertsOnly: { value: 'Yes' }
  ALZAlertDescriptionPrefix: { value: 'AMBA-ALZ: ' }
  ALZMonitorActionGroupEmail: { value: emails }
  ALZLogicappResourceId: { value: '' }
  ALZLogicappCallbackUrl: { value: '' }
  ALZArmRoleId: { value: [] }
  ALZEventHubResourceId: { value: [] }
  ALZWebhookServiceUri: { value: [] }
  ALZFunctionResourceId: { value: '' }
  ALZFunctionTriggerUrl: { value: '' }
  BYOActionGroup: { value: byoActionGroupIds }
  BYOAlertProcessingRule: { value: '' }
  ALZAlertSeverity: { value: ['Sev0', 'Sev1', 'Sev2', 'Sev3', 'Sev4'] }
  ALZNotificationAssetSuffix: { value: '-ALZ-001' }
})

// 1. Policy definitions (one linked template per AMBA definitions file).
// A Bicep module can't point at a template URL, so these are deployments
// resources with a templateLink, as in AMBA's own alzArm.json.
#disable-next-line no-deployments-resources
resource policyDefinitions 'Microsoft.Resources/deployments@2025-04-01' = [
  for file in definitionFiles: {
    name: 'ch12-amba-def-${toLower(file)}'
    location: deployment().location
    properties: {
      mode: 'Incremental'
      templateLink: {
        uri: '${baseUri}policyDefinitions/policies-${file}.json'
        contentVersion: '1.0.0.0'
      }
      parameters: {
        topLevelManagementGroupPrefix: { value: managementGroup().name }
      }
    }
  }
]

// 2. Initiatives (policy set definitions).
#disable-next-line no-deployments-resources
resource policySets 'Microsoft.Resources/deployments@2025-04-01' = {
  name: 'ch12-amba-sets'
  location: deployment().location
  dependsOn: [policyDefinitions]
  properties: {
    mode: 'Incremental'
    templateLink: {
      uri: '${baseUri}policyDefinitions/policySets.json'
      contentVersion: '1.0.0.0'
    }
    parameters: {
      topLevelManagementGroupPrefix: { value: managementGroup().name }
    }
  }
}

// 3. The two assignments, with the enforcement mode the AMBA templates accept
//    but alzArm.json doesn't pass through.
#disable-next-line no-deployments-resources
resource serviceHealthAssignment 'Microsoft.Resources/deployments@2025-04-01' = {
  name: 'ch12-amba-assign-servicehealth'
  location: deployment().location
  dependsOn: [policySets]
  properties: {
    mode: 'Incremental'
    templateLink: {
      uri: '${baseUri}policyAssignments/DINE-ResourceAndServiceHealthAssignment.json'
      contentVersion: '1.0.0.0'
    }
    parameters: {
      topLevelManagementGroupPrefix: { value: managementGroup().name }
      enforcementMode: { value: enforcementMode }
      policyAssignmentParameters: { value: serviceHealthParameters }
      policyAssignmentExclusions: { value: [] }
    }
  }
}

#disable-next-line no-deployments-resources
resource notificationAssetsAssignment 'Microsoft.Resources/deployments@2025-04-01' = {
  name: 'ch12-amba-assign-notification'
  location: deployment().location
  dependsOn: [policySets]
  properties: {
    mode: 'Incremental'
    templateLink: {
      uri: '${baseUri}policyAssignments/DINE-NotificationAssetsAssignment.json'
      contentVersion: '1.0.0.0'
    }
    parameters: {
      topLevelManagementGroupPrefix: { value: managementGroup().name }
      enforcementMode: { value: enforcementMode }
      policyAssignmentParameters: { value: notificationAssetParameters }
      policyAssignmentExclusions: { value: [] }
    }
  }
}

output managementGroupId string = managementGroup().name
output enforcementMode string = enforcementMode
output usesPlatformActionGroup bool = useByo
