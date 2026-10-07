metadata name = 'Platform RBAC at management group scope'
metadata description = 'Custom roles at the intermediate root, group role assignments at management group scopes and optional PIM-eligible assignments (chapter 5).'

// Deploy at the intermediate root management group (az deployment mg
// --management-group-id alz). The custom roles are created here; the role
// assignment modules are scoped to the child management groups.
targetScope = 'managementGroup'

@description('Prefix added to custom role names so they are unique in the tenant.')
param prefix string = 'alz'

@description('ID of the Platform management group.')
param platformManagementGroupId string = 'alz-platform'

@description('ID of the Landing zones management group (used for the optional PIM-eligible platform access).')
param landingZonesManagementGroupId string = 'alz-landingzones'

@description('ID of the landing zone management group where the workload team gets Contributor.')
param workloadManagementGroupId string = 'alz-corp'

@description('Object ID of the Microsoft Entra group for the platform team (Owner at Platform).')
param platformTeamGroupObjectId string

@description('Object ID of the Microsoft Entra group for a workload team (Contributor at the workload landing zone management group).')
param workloadTeamGroupObjectId string

@description('Object ID of the Microsoft Entra group for security operations (Security Reader at the intermediate root).')
param securityOpsGroupObjectId string

@description('Optional object ID of the Microsoft Entra group for network operations (custom Network Management role at the intermediate root). Empty skips the assignment.')
param networkOpsGroupObjectId string = ''

@description('When true, the platform team\'s Owner at Platform becomes PIM-eligible instead of active, and the platform team gets eligible Contributor at Landing zones. Needs Microsoft Entra ID P2 or ID Governance.')
param enablePimEligibleAssignments bool = false

@description('How long the eligible assignments last, as an ISO 8601 duration. Must be within the maximum the PIM role settings allow.')
param pimEligibilityDuration string = 'P365D'

@description('Start of the eligibility window. Leave the default (deployment time).')
param pimStartTime string = utcNow()

@description('Send Azure Verified Modules usage telemetry.')
param enableTelemetry bool = true

// The deployment's own scope is the intermediate root.
var intermediateRootManagementGroupId = managementGroup().name

// Built-in role definition IDs are the same in every tenant. The AVM modules
// know Owner and Contributor by name; Security Reader needs its ID.
var securityReaderRoleId = '39bc4728-0917-49c7-9d2c-d95423bc2eb4'

// ---------------------------------------------------------------------------
// (a) Custom role definitions at the intermediate root
// Both follow the custom roles the Azure landing zone reference architecture
// ships (ALZ library: Application-Owners and Network-Management).
// ---------------------------------------------------------------------------

// Workload teams: Contributor-like, but no RBAC writes, public IPs, virtual
// network writes or key vault purge.
module applicationOwnerRole 'br/public:avm/ptn/authorization/role-definition:0.1.1' = {
  name: 'ch05-role-application-owner'
  params: {
    name: '${intermediateRootManagementGroupId}-application-owner' // hashed to a stable GUID by the module
    roleName: 'Landing Zone Application Owner (${prefix})'
    description: 'Contributor role for application and operations teams in a landing zone, without RBAC writes, public IPs, virtual network writes or key vault purge.'
    assignableScopes: [
      managementGroup().id
    ]
    actions: [
      '*'
    ]
    notActions: [
      'Microsoft.Authorization/*/write'
      'Microsoft.Network/publicIPAddresses/write'
      'Microsoft.Network/virtualNetworks/write'
      'Microsoft.KeyVault/locations/deletedVaults/purge/action'
    ]
    enableTelemetry: enableTelemetry
  }
}

// Network operations: read everything, manage networking, run deployments,
// raise support tickets.
module networkManagementRole 'br/public:avm/ptn/authorization/role-definition:0.1.1' = {
  name: 'ch05-role-network-management'
  params: {
    name: '${intermediateRootManagementGroupId}-network-management'
    roleName: 'Network Management (${prefix})'
    description: 'Platform-wide connectivity management: virtual networks, route tables, NSGs, NVAs, VPN, ExpressRoute and related resources.'
    assignableScopes: [
      managementGroup().id
    ]
    actions: [
      '*/read'
      'Microsoft.Network/*'
      'Microsoft.Resources/deployments/*'
      'Microsoft.Support/*'
    ]
    enableTelemetry: enableTelemetry
  }
}

// ---------------------------------------------------------------------------
// (b) Roles assigned to Microsoft Entra groups at management group scopes
// ---------------------------------------------------------------------------

// Platform team: Owner at Platform (active only when PIM is off).
module platformTeamOwner 'br/public:avm/res/authorization/role-assignment/mg-scope:0.1.2' = if (!enablePimEligibleAssignments) {
  name: 'ch05-ra-platform-owner'
  scope: managementGroup(platformManagementGroupId)
  params: {
    managementGroupId: platformManagementGroupId
    roleDefinitionIdOrName: 'Owner'
    principalId: platformTeamGroupObjectId
    principalType: 'Group'
    description: 'Platform team manages the platform subscriptions.'
    enableTelemetry: enableTelemetry
  }
}

// Workload team: Contributor at its landing zone management group.
module workloadTeamContributor 'br/public:avm/res/authorization/role-assignment/mg-scope:0.1.2' = {
  name: 'ch05-ra-workload-contributor'
  scope: managementGroup(workloadManagementGroupId)
  params: {
    managementGroupId: workloadManagementGroupId
    roleDefinitionIdOrName: 'Contributor'
    principalId: workloadTeamGroupObjectId
    principalType: 'Group'
    description: 'Workload team builds in the landing zones under this management group.'
    enableTelemetry: enableTelemetry
  }
}

// Security operations: Security Reader across the estate. Security Reader isn't
// in the module's short-name list, so pass the full role definition ID.
module securityOpsReader 'br/public:avm/res/authorization/role-assignment/mg-scope:0.1.2' = {
  name: 'ch05-ra-security-reader'
  params: {
    managementGroupId: intermediateRootManagementGroupId
    roleDefinitionIdOrName: managementGroupResourceId('Microsoft.Authorization/roleDefinitions', securityReaderRoleId)
    principalId: securityOpsGroupObjectId
    principalType: 'Group'
    description: 'Security operations view security posture across the estate.'
    enableTelemetry: enableTelemetry
  }
}

// Network operations: the custom Network Management role across the estate.
module networkOps 'br/public:avm/res/authorization/role-assignment/mg-scope:0.1.2' = if (!empty(networkOpsGroupObjectId)) {
  name: 'ch05-ra-network-ops'
  params: {
    managementGroupId: intermediateRootManagementGroupId
    roleDefinitionIdOrName: networkManagementRole.outputs.roleDefinitionIdName
    principalId: networkOpsGroupObjectId
    principalType: 'Group'
    description: 'Network operations manage connectivity across the estate.'
    enableTelemetry: enableTelemetry
  }
}

// ---------------------------------------------------------------------------
// (c) Optional PIM-eligible assignments (Microsoft Entra ID P2 or ID Governance)
// Each one is a Microsoft.Authorization/roleEligibilityScheduleRequests
// resource with requestType AdminAssign.
// ---------------------------------------------------------------------------

module platformTeamOwnerEligible 'br/public:avm/ptn/authorization/pim-role-assignment:0.1.2' = if (enablePimEligibleAssignments) {
  name: 'ch05-pim-platform-owner'
  scope: managementGroup(platformManagementGroupId)
  params: {
    managementGroupId: platformManagementGroupId
    roleDefinitionIdOrName: 'Owner'
    principalId: platformTeamGroupObjectId
    requestType: 'AdminAssign'
    justification: 'Platform team: just-in-time Owner on the Platform management group.'
    pimRoleAssignmentType: {
      roleAssignmentType: 'Eligible'
      scheduleInfo: {
        durationType: 'AfterDuration'
        duration: pimEligibilityDuration
        startTime: pimStartTime
      }
    }
    enableTelemetry: enableTelemetry
  }
}

// Platform admins get no standing access to workload landing zones; they can
// activate Contributor there to troubleshoot.
module platformTeamLandingZonesContributorEligible 'br/public:avm/ptn/authorization/pim-role-assignment:0.1.2' = if (enablePimEligibleAssignments) {
  name: 'ch05-pim-platform-lz-contributor'
  scope: managementGroup(landingZonesManagementGroupId)
  params: {
    managementGroupId: landingZonesManagementGroupId
    roleDefinitionIdOrName: 'Contributor'
    principalId: platformTeamGroupObjectId
    requestType: 'AdminAssign'
    justification: 'Platform team: just-in-time Contributor on landing zones for troubleshooting.'
    pimRoleAssignmentType: {
      roleAssignmentType: 'Eligible'
      scheduleInfo: {
        durationType: 'AfterDuration'
        duration: pimEligibilityDuration
        startTime: pimStartTime
      }
    }
    enableTelemetry: enableTelemetry
  }
}

@description('Resource ID of the custom Landing Zone Application Owner role (chapter 7 assigns it at subscription scope).')
output applicationOwnerRoleDefinitionId string = applicationOwnerRole.outputs.roleDefinitionIdName

@description('Resource ID of the custom Network Management role.')
output networkManagementRoleDefinitionId string = networkManagementRole.outputs.roleDefinitionIdName
