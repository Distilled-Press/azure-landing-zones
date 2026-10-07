using './main.bicep'

// Deploy at the intermediate root: az deployment mg create --management-group-id alz ...
// Find a group's object ID with: az ad group show --group "<display name>" --query id -o tsv

param prefix = 'alz'

param platformManagementGroupId = 'alz-platform'
param landingZonesManagementGroupId = 'alz-landingzones'
param workloadManagementGroupId = 'alz-corp'

param platformTeamGroupObjectId = '00000000-0000-0000-0000-000000000001'
param workloadTeamGroupObjectId = '00000000-0000-0000-0000-000000000002'
param securityOpsGroupObjectId = '00000000-0000-0000-0000-000000000003'
param networkOpsGroupObjectId = '00000000-0000-0000-0000-000000000004' // or '' to skip

// Needs Microsoft Entra ID P2 or ID Governance.
param enablePimEligibleAssignments = false
param pimEligibilityDuration = 'P365D'
