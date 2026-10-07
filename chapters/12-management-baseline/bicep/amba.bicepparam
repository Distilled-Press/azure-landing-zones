using 'amba.bicep'

// Opt-in. Deploy at the test management group AFTER main.bicep:
//   az deployment mg create --management-group-id alz --location uksouth \
//     --name ch12-amba --parameters amba.bicepparam

param ambaRelease = '2026-06-03'

// Report compliance only. 'Default' deploys alerts into subscriptions under the management group.
param enforcementMode = 'DoNotEnforce'

// main.bicep's actionGroupId output, so AMBA notifies receivers who have already verified their addresses.
param byoActionGroupIds = [
  '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-alz-management-uksouth/providers/Microsoft.Insights/actionGroups/ag-alz-platform'
]

// Only used when byoActionGroupIds is empty.
param actionGroupEmailAddresses = []

param ambaResourceGroupName = 'rg-amba-monitoring-001'
param ambaResourceGroupLocation = 'uksouth'
