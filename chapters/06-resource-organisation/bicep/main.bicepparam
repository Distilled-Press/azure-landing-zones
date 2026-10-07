using 'main.bicep'

// Every value is optional; these are the defaults written out.

param prefix = 'alz'
param location = 'uksouth'

// Leave out to build under the tenant root group, or name an existing management group:
// param parentManagementGroupId = 'my-parent-mg'

// Test deployment: report compliance only. Use 'Default' for a real platform.
param policyAssignmentEnforcementMode = 'DoNotEnforce'

// Real deployments point Deploy-AzActivity-Log at the platform's workspace (chapter 12), e.g.
// '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-alz-management-uksouth/providers/Microsoft.OperationalInsights/workspaces/law-alz-uksouth'
param logAnalyticsWorkspaceResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/placeholder/providers/Microsoft.OperationalInsights/workspaces/placeholder-la'

param enableTelemetry = true
