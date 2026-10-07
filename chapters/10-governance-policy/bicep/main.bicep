// Chapter 10: policy as code at a test management group.
// Deploy AT the test management group (create it first; see the README):
//   az deployment mg create --management-group-id alz-policytest --location uksouth --parameters main.bicepparam
targetScope = 'managementGroup'

// ---------- Parameters ----------

@description('Prefix for the names this template creates. Assignment and exemption names at management group scope are limited to 24 characters.')
@minLength(1)
@maxLength(10)
param prefix string = 'alz'

@description('Region recorded for the Modify assignment\'s system-assigned managed identity (and the deployment metadata).')
param location string = deployment().location

@description('Enforcement mode of both assignments. DoNotEnforce: evaluate and report only. Default: enforce.')
@allowed([
  'Default'
  'DoNotEnforce'
])
param enforcementMode string = 'DoNotEnforce'

@description('Tag every resource group must carry, and the tag resources inherit from their resource group.')
param requiredTagName string = 'costCentre'

@description('Effect for both policies in the guardrails initiative.')
@allowed([
  'Audit'
  'Deny'
])
param guardrailEffect string = 'Audit'

@description('Regions resources may be created in.')
param allowedLocations string[] = [
  'uksouth'
  'ukwest'
]

@description('When the allowed-locations waiver stops applying (UTC ISO 8601). Default: 30 days after this deployment runs. Each redeployment with the default moves it.')
param exemptionExpiresOn string = dateTimeAdd(utcNow(), 'P30D')

@description('Create a remediation task for the Modify assignment. Off by default; see the README.')
param createRemediationTask bool = false

@description('AVM usage telemetry.')
param enableTelemetry bool = true

// ---------- Built-in definitions (IDs from Learn's built-in policy list) ----------

// Allowed locations (General)
var builtinAllowedLocations = '/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c'
// Inherit a tag from the resource group if missing (Tags), effect modify
var builtinInheritTag = '/providers/Microsoft.Authorization/policyDefinitions/ea3f2387-9b95-492a-a190-fcdc54f7b070'
// The roles in that definition's then.details.roleDefinitionIds (Contributor).
// Bicep can't read a built-in definition at build time, so they are listed here;
// check them against the definition when you change it.
var inheritTagRoleDefinitionIds = [
  '/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c'
]

// ---------- 1. Custom policy definition (shared JSON with the Terraform version) ----------

var requireTag = loadJsonContent('../lib/require-rg-tag.policy.json').properties

resource requireRgTag 'Microsoft.Authorization/policyDefinitions@2025-01-01' = {
  name: '${prefix}-require-rg-tag'
  properties: {
    policyType: 'Custom'
    mode: requireTag.mode
    displayName: requireTag.displayName
    description: requireTag.description
    metadata: requireTag.metadata
    parameters: requireTag.parameters
    policyRule: requireTag.policyRule
  }
}

// ---------- 2. Custom initiative: the custom definition plus a built-in ----------

resource guardrails 'Microsoft.Authorization/policySetDefinitions@2025-01-01' = {
  name: '${prefix}-guardrails'
  properties: {
    policyType: 'Custom'
    displayName: 'Guardrails: required tag and allowed locations (${prefix})'
    description: 'Chapter 10 example initiative: one custom definition and one built-in, sharing an effect parameter.'
    metadata: {
      category: 'General'
      version: '1.0.0'
    }
    parameters: {
      tagName: {
        type: 'String'
        metadata: { displayName: 'Required tag name' }
      }
      effect: {
        type: 'String'
        defaultValue: 'Audit'
        allowedValues: [
          'Audit'
          'Deny'
          'Disabled'
        ]
        metadata: { displayName: 'Effect for both policies' }
      }
      listOfAllowedLocations: {
        type: 'Array'
        metadata: {
          displayName: 'Allowed locations'
          strongType: 'location'
        }
      }
    }
    policyDefinitions: [
      {
        policyDefinitionReferenceId: 'requireRgTag'
        policyDefinitionId: requireRgTag.id
        parameters: {
          tagName: { value: '[parameters(\'tagName\')]' }
          effect: { value: '[parameters(\'effect\')]' }
        }
      }
      {
        policyDefinitionReferenceId: 'allowedLocations'
        policyDefinitionId: builtinAllowedLocations
        parameters: {
          listOfAllowedLocations: { value: '[parameters(\'listOfAllowedLocations\')]' }
          effect: { value: '[parameters(\'effect\')]' }
        }
      }
    ]
  }
}

// ---------- 3. Assign the initiative, with non-compliance messages ----------

module guardrailsAssignment 'br/public:avm/ptn/authorization/policy-assignment:0.5.3' = {
  name: 'ch10-${prefix}-guardrails'
  params: {
    name: '${prefix}-guardrails'
    displayName: 'Guardrails: required tag and allowed locations'
    description: 'Chapter 10 example. Reports (or with Deny and Default enforcement, blocks) untagged resource groups and resources outside the allowed regions.'
    policyDefinitionId: guardrails.id
    identity: 'None' // Audit and Deny need no identity
    enforcementMode: enforcementMode
    location: location
    parameters: {
      tagName: { value: requiredTagName }
      effect: { value: guardrailEffect }
      listOfAllowedLocations: { value: allowedLocations }
    }
    nonComplianceMessages: [
      {
        message: 'This breaks the platform guardrails. See the landing zone guide or ask the platform team.'
      }
      {
        message: 'Resource groups must have a \'${requiredTagName}\' tag. Add it and deploy again.'
        policyDefinitionReferenceId: 'requireRgTag'
      }
      {
        message: 'Only these regions are allowed: ${join(allowedLocations, ', ')}. Ask the platform team for an exemption if you need another.'
        policyDefinitionReferenceId: 'allowedLocations'
      }
    ]
    enableTelemetry: enableTelemetry
  }
}

// ---------- 4. Exemption: a time-limited waiver from one member of the initiative ----------

module locationWaiver 'br/public:avm/ptn/authorization/policy-exemption:0.2.0' = {
  name: 'ch10-${prefix}-loc-waiver'
  params: {
    name: '${prefix}-loc-waiver'
    displayName: 'Waiver: allowed locations (test)'
    description: 'Temporary waiver from the allowed-locations rule only; the required-tag rule still applies.'
    policyAssignmentId: guardrailsAssignment.outputs.resourceId
    exemptionCategory: 'Waiver'
    expiresOn: exemptionExpiresOn
    policyDefinitionReferenceIds: [
      'allowedLocations'
    ]
    metadata: {
      requestedBy: 'workload team (example)'
      approvedBy: 'platform team (example)'
      ticketRef: 'CHG-0000'
    }
    location: location
    enableTelemetry: enableTelemetry
  }
}

// ---------- 5. Built-in Modify policy with a system-assigned managed identity ----------

module inheritTagAssignment 'br/public:avm/ptn/authorization/policy-assignment:0.5.3' = {
  name: 'ch10-${prefix}-inherit-tag'
  params: {
    name: '${prefix}-inherit-tag'
    displayName: 'Inherit the ${requiredTagName} tag from the resource group if missing'
    policyDefinitionId: builtinInheritTag
    identity: 'SystemAssigned'
    // The module assigns these roles to the identity at this management group.
    roleDefinitionIds: inheritTagRoleDefinitionIds
    enforcementMode: enforcementMode
    location: location
    parameters: {
      tagName: { value: requiredTagName }
    }
    nonComplianceMessages: [
      {
        message: 'Resources should carry their resource group\'s \'${requiredTagName}\' tag. A remediation task adds it.'
      }
    ]
    enableTelemetry: enableTelemetry
  }
}

// ---------- 6. Remediation task (optional) ----------

module inheritTagRemediation 'br/public:avm/ptn/policy-insights/remediation:0.1.0' = if (createRemediationTask) {
  name: 'ch10-${prefix}-inherit-tag-remediation'
  params: {
    name: '${prefix}-inherit-tag-remediation'
    policyAssignmentId: inheritTagAssignment.outputs.resourceId
    location: location
    enableTelemetry: enableTelemetry
  }
}

// ---------- Outputs ----------

output policyDefinitionId string = requireRgTag.id
output policySetDefinitionId string = guardrails.id
output guardrailsAssignmentId string = guardrailsAssignment.outputs.resourceId
output inheritTagAssignmentId string = inheritTagAssignment.outputs.resourceId
output inheritTagPrincipalId string = inheritTagAssignment.outputs.principalId
output exemptionId string = locationWaiver.outputs.resourceId
output exemptionExpiresOn string = exemptionExpiresOn
