metadata name = 'Chapter 6 - ALZ management group hierarchy'
metadata description = 'Creates the Azure landing zone management group hierarchy with avm/ptn/alz/empty and assigns a subset of the ALZ library policies to it.'

// Management groups are tenant-level resources, so this file is deployed with
// `az deployment tenant create`. Each management group is one call to the AVM
// pattern module avm/ptn/alz/empty, scoped to its parent management group.
targetScope = 'tenant'

// ---------- Parameters ----------

@description('Prefix for the management group IDs: <prefix>, <prefix>-platform, <prefix>-corp and so on.')
@minLength(1)
@maxLength(40)
param prefix string = 'alz'

@description('ID (not resource ID) of the management group to build under. Defaults to the tenant root group, whose ID is the tenant ID.')
param parentManagementGroupId string = tenant().tenantId

@description('Region for the policy assignments\' managed identities.')
param location string = 'uksouth'

@description('DoNotEnforce (default, for testing) puts every assignment into DoNotEnforce. Default keeps the enforcement mode each library assignment ships with.')
@allowed([
  'DoNotEnforce'
  'Default'
])
param policyAssignmentEnforcementMode string = 'DoNotEnforce'

@description('Log Analytics workspace resource ID for the Deploy-AzActivity-Log assignment. The default is the ALZ library placeholder, which needs no real workspace.')
param logAnalyticsWorkspaceResourceId string = '/subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/placeholder/providers/Microsoft.OperationalInsights/workspaces/placeholder-la'

@description('AVM module usage telemetry (https://aka.ms/avm/telemetryinfo).')
param enableTelemetry bool = true

// ---------- Names ----------

var mgNames = {
  intRoot: prefix
  platform: '${prefix}-platform'
  security: '${prefix}-security'
  management: '${prefix}-management'
  identity: '${prefix}-identity'
  connectivity: '${prefix}-connectivity'
  landingZones: '${prefix}-landingzones'
  corp: '${prefix}-corp'
  online: '${prefix}-online'
  local: '${prefix}-local'
  sandbox: '${prefix}-sandbox'
  decommissioned: '${prefix}-decommissioned'
}

// ---------- ALZ library content (subset, copied unchanged from platform/alz 2026.10.0) ----------

// Custom definitions live on the intermediate root so every child can assign them.
var libPolicyDefinitions = [
  loadJsonContent('lib/Deny-Subnet-Without-Nsg.alz_policy_definition.json')
  loadJsonContent('lib/Deny-VNET-Peer-Cross-Sub.alz_policy_definition.json')
  loadJsonContent('lib/Deploy-Vm-autoShutdown.alz_policy_definition.json')
]

var libPolicySetDefinitions = [
  loadJsonContent('lib/Enforce-ALZ-Sandbox.alz_policy_set_definition.json')
  loadJsonContent('lib/Enforce-ALZ-Decomm.alz_policy_set_definition.json')
]

// Which library assignments go on which management group (the archetypes).
var libAssignments = {
  intRoot: [
    loadJsonContent('lib/Audit-ResourceRGLocation.alz_policy_assignment.json')
    loadJsonContent('lib/Deny-Classic-Resources.alz_policy_assignment.json')
    loadJsonContent('lib/Deploy-AzActivity-Log.alz_policy_assignment.json')
  ]
  identity: [
    loadJsonContent('lib/Deny-Public-IP.alz_policy_assignment.json')
    loadJsonContent('lib/Deny-Subnet-Without-Nsg.alz_policy_assignment.json')
  ]
  landingZones: [
    loadJsonContent('lib/Deny-IP-forwarding.alz_policy_assignment.json')
    loadJsonContent('lib/Deny-Storage-http.alz_policy_assignment.json')
    loadJsonContent('lib/Deny-Subnet-Without-Nsg.alz_policy_assignment.json')
  ]
  corp: [
    loadJsonContent('lib/Deny-HybridNetworking.alz_policy_assignment.json')
    loadJsonContent('lib/Deny-Public-IP-On-NIC.alz_policy_assignment.json')
  ]
  local: [
    loadJsonContent('lib/Enforce-ALDO-Services.alz_policy_assignment.json')
  ]
  sandbox: [
    loadJsonContent('lib/Enforce-ALZ-Sandbox.alz_policy_assignment.json')
  ]
  decommissioned: [
    loadJsonContent('lib/Enforce-ALZ-Decomm.alz_policy_assignment.json')
  ]
}

// Library files say "placeholder" (assignments) or "contoso" (set definitions)
// where the intermediate root's name belongs.
var definitionScopeFixups = {
  '/managementGroups/placeholder/': '/managementGroups/${mgNames.intRoot}/'
  '/managementGroups/contoso/': '/managementGroups/${mgNames.intRoot}/'
}

// Parameters this deployment sets on top of the library values.
var parameterOverrides = {
  'Deploy-AzActivity-Log': {
    logAnalytics: {
      value: logAnalyticsWorkspaceResourceId
    }
  }
}

// Roles the module grants each assignment's managed identity (from the
// roleDefinitionIds in the assigned policy definitions).
var builtInRoles = {
  logAnalyticsContributor: '/providers/Microsoft.Authorization/roleDefinitions/92aaf0da-9dab-42b6-94a3-d43ce8d16293'
  monitoringContributor: '/providers/Microsoft.Authorization/roleDefinitions/749f88d5-cbae-40b8-bcfc-e573ddc772fa'
  virtualMachineContributor: '/providers/Microsoft.Authorization/roleDefinitions/9980e02c-c2be-4d73-94e8-173b1dc7cf3c'
}

var assignmentRoles = {
  'Deploy-AzActivity-Log': [
    builtInRoles.logAnalyticsContributor
    builtInRoles.monitoringContributor
  ]
  'Enforce-ALZ-Decomm': [
    builtInRoles.virtualMachineContributor
  ]
}

// ---------- Conversions from library JSON to the module's input types ----------

func fixScopes(item object, fixups object) object =>
  json(reduce(items(fixups), string(item), (text, f) => replace(text, f.key, f.value)))

func toPolicyDefinition(def object) object => {
  name: def.name
  properties: {
    description: def.properties.?description
    displayName: def.properties.?displayName
    metadata: def.properties.?metadata
    mode: def.properties.?mode
    parameters: def.properties.?parameters
    policyRule: def.properties.policyRule
  }
}

func toPolicySetDefinition(def object) object => {
  name: def.name
  properties: {
    description: def.properties.?description
    displayName: def.properties.?displayName
    metadata: def.properties.?metadata
    parameters: def.properties.?parameters
    policyDefinitions: def.properties.policyDefinitions
    policyDefinitionGroups: def.properties.?policyDefinitionGroups
  }
}

func toPolicyAssignment(
  pa object,
  location string,
  enforcementMode string,
  overrides object,
  roles object
) object => {
  name: pa.name
  displayName: pa.properties.?displayName
  description: pa.properties.?description
  policyDefinitionId: pa.properties.policyDefinitionId
  definitionVersion: pa.properties.?definitionVersion
  parameters: union(pa.properties.?parameters ?? {}, overrides[?pa.name] ?? {})
  identity: pa.?identity.?type ?? 'None'
  roleDefinitionIds: roles[?pa.name]
  // DoNotEnforce overrides everything; Default keeps the library's own mode.
  enforcementMode: enforcementMode == 'DoNotEnforce' ? 'DoNotEnforce' : (pa.properties.?enforcementMode ?? 'Default')
  nonComplianceMessages: map(
    pa.properties.?nonComplianceMessages ?? [],
    m =>
      union(m, {
        message: replace(
          m.message,
          '{enforcementMode}',
          (enforcementMode == 'DoNotEnforce' || pa.properties.?enforcementMode == 'DoNotEnforce') ? 'should' : 'must'
        )
      })
  )
  notScopes: pa.properties.?notScopes
  location: location
}

var policyDefinitions = map(libPolicyDefinitions, d => toPolicyDefinition(d))
var policySetDefinitions = map(
  libPolicySetDefinitions,
  d => toPolicySetDefinition(fixScopes(d, definitionScopeFixups))
)
var policyAssignments = toObject(
  items(libAssignments),
  e => e.key,
  e =>
    map(
      e.value,
      pa =>
        toPolicyAssignment(
          fixScopes(pa, definitionScopeFixups),
          location,
          policyAssignmentEnforcementMode,
          parameterOverrides,
          assignmentRoles
        )
    )
)

// Settings shared by every management group module.
var common = {
  location: location
  enableTelemetry: enableTelemetry
}

// ---------- Management groups ----------

// Level 1: intermediate root, with the custom definitions.
module intRoot 'br/public:avm/ptn/alz/empty:0.3.6' = {
  name: take('ch06-${mgNames.intRoot}', 64)
  scope: managementGroup(parentManagementGroupId)
  params: {
    managementGroupName: mgNames.intRoot
    managementGroupDisplayName: 'Azure Landing Zones'
    managementGroupParentId: parentManagementGroupId
    managementGroupCustomPolicyDefinitions: policyDefinitions
    managementGroupCustomPolicySetDefinitions: policySetDefinitions
    managementGroupPolicyAssignments: policyAssignments.intRoot
    location: common.location
    enableTelemetry: common.enableTelemetry
  }
}

// Level 2: Platform, Landing zones, Sandbox, Decommissioned.
module platform 'br/public:avm/ptn/alz/empty:0.3.6' = {
  name: take('ch06-${mgNames.platform}', 64)
  scope: managementGroup(mgNames.intRoot)
  dependsOn: [intRoot]
  params: {
    managementGroupName: mgNames.platform
    managementGroupDisplayName: 'Platform'
    managementGroupParentId: mgNames.intRoot
    location: common.location
    enableTelemetry: common.enableTelemetry
  }
}

module landingZones 'br/public:avm/ptn/alz/empty:0.3.6' = {
  name: take('ch06-${mgNames.landingZones}', 64)
  scope: managementGroup(mgNames.intRoot)
  dependsOn: [intRoot]
  params: {
    managementGroupName: mgNames.landingZones
    managementGroupDisplayName: 'Landing zones'
    managementGroupParentId: mgNames.intRoot
    managementGroupPolicyAssignments: policyAssignments.landingZones
    location: common.location
    enableTelemetry: common.enableTelemetry
  }
}

module sandbox 'br/public:avm/ptn/alz/empty:0.3.6' = {
  name: take('ch06-${mgNames.sandbox}', 64)
  scope: managementGroup(mgNames.intRoot)
  dependsOn: [intRoot]
  params: {
    managementGroupName: mgNames.sandbox
    managementGroupDisplayName: 'Sandbox'
    managementGroupParentId: mgNames.intRoot
    managementGroupPolicyAssignments: policyAssignments.sandbox
    location: common.location
    enableTelemetry: common.enableTelemetry
  }
}

module decommissioned 'br/public:avm/ptn/alz/empty:0.3.6' = {
  name: take('ch06-${mgNames.decommissioned}', 64)
  scope: managementGroup(mgNames.intRoot)
  dependsOn: [intRoot]
  params: {
    managementGroupName: mgNames.decommissioned
    managementGroupDisplayName: 'Decommissioned'
    managementGroupParentId: mgNames.intRoot
    managementGroupPolicyAssignments: policyAssignments.decommissioned
    location: common.location
    enableTelemetry: common.enableTelemetry
  }
}

// Level 3 under Platform.
var platformChildren = [
  {
    key: 'security'
    displayName: 'Security'
  }
  {
    key: 'management'
    displayName: 'Management'
  }
  {
    key: 'identity'
    displayName: 'Identity'
  }
  {
    key: 'connectivity'
    displayName: 'Connectivity'
  }
]

module platformMgs 'br/public:avm/ptn/alz/empty:0.3.6' = [
  for child in platformChildren: {
    name: take('ch06-${mgNames[child.key]}', 64)
    scope: managementGroup(mgNames.platform)
    dependsOn: [platform]
    params: {
      managementGroupName: mgNames[child.key]
      managementGroupDisplayName: child.displayName
      managementGroupParentId: mgNames.platform
      managementGroupPolicyAssignments: policyAssignments[?child.key] ?? []
      location: common.location
      enableTelemetry: common.enableTelemetry
    }
  }
]

// Level 3 under Landing zones.
var landingZoneChildren = [
  {
    key: 'corp'
    displayName: 'Corp'
  }
  {
    key: 'online'
    displayName: 'Online'
  }
  {
    key: 'local'
    displayName: 'Local'
  }
]

module landingZoneMgs 'br/public:avm/ptn/alz/empty:0.3.6' = [
  for child in landingZoneChildren: {
    name: take('ch06-${mgNames[child.key]}', 64)
    scope: managementGroup(mgNames.landingZones)
    dependsOn: [landingZones]
    params: {
      managementGroupName: mgNames[child.key]
      managementGroupDisplayName: child.displayName
      managementGroupParentId: mgNames.landingZones
      managementGroupPolicyAssignments: policyAssignments[?child.key] ?? []
      location: common.location
      enableTelemetry: common.enableTelemetry
    }
  }
]

// ---------- Outputs ----------

output managementGroupIds object = mgNames
output policyAssignmentNames object = toObject(items(policyAssignments), e => mgNames[e.key], e => map(e.value, pa => pa.name))
output enforcementMode string = policyAssignmentEnforcementMode
