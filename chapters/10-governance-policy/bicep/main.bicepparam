// Deploy at the test management group, which must already exist:
//   az account management-group create --name alz-policytest --display-name "Policy test (alz)" [--parent <parent-mg-id>]
//   az deployment mg create --management-group-id alz-policytest --location uksouth --name ch10-policy --parameters main.bicepparam
using 'main.bicep'

param prefix = 'alz'

// DoNotEnforce: report only. Default: enforce (Deny blocks, Modify changes tags).
param enforcementMode = 'DoNotEnforce'

param requiredTagName = 'costCentre'
param guardrailEffect = 'Audit'
param allowedLocations = [
  'uksouth'
  'ukwest'
]

// Leave unset for "30 days after this deployment", or fix it:
// param exemptionExpiresOn = '2026-12-31T23:59:59Z'

param createRemediationTask = false
