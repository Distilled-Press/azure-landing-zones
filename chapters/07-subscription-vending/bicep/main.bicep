// Subscription vending: one request file in, one configured subscription out.
// Deploy at management group scope (for example the intermediate root, `alz`).
targetScope = 'managementGroup'

// ---------- The request file's shape ----------
// The .bicepparam file loads the YAML request into this typed parameter, so a
// malformed request fails at build time, before anything reaches Azure.

type subnetRequest = {
  name: string
  address_prefix: string
}

type roleAssignmentRequest = {
  @description('Entra ID object ID of the user, group or service principal.')
  principal_id: string
  principal_type: ('User' | 'Group' | 'ServicePrincipal')?
  @description('A built-in role name from the roleDefinitionIds map below, or a role definition GUID.')
  role: string
}

type subscriptionRequest = {
  workload: string
  environment: string
  location: string?
  owner_email: string
  management_group_id: string
  subscription_workload_type: ('Production' | 'DevTest')?
  budget: {
    amount: int
    threshold_type: ('Actual' | 'Forecasted')?
    @maxLength(5)
    thresholds: int[]
    contact_emails: string[]
  }
  tags: object
  network: {
    address_space: string[]
    subnets: subnetRequest[]
  }
  role_assignments: roleAssignmentRequest[]
  resource_providers: string[]?
}

// ---------- Parameters ----------

@description('The subscription request, loaded from the YAML file by the .bicepparam file.')
param request subscriptionRequest

@description('Prefix used in the names this template creates.')
param prefix string = 'alz'

@description('true: create a NEW subscription with an alias against billingScope. false (default): configure the EXISTING subscription in existingSubscriptionId.')
param subscriptionAliasEnabled bool = false

@description('Billing scope for a new subscription (alias mode only).')
param billingScope string = ''

@description('ID of an existing subscription to configure (existing mode only).')
param existingSubscriptionId string = ''

@description('Peer the spoke to a hub virtual network (chapter 8). Off by default.')
param hubPeeringEnabled bool = false

@description('Resource ID of the hub virtual network. Required when hubPeeringEnabled is true.')
param hubVirtualNetworkResourceId string = ''

@description('Let the spoke use the hub gateway. Only true if the hub has a VPN or ExpressRoute gateway.')
param hubUseRemoteGateways bool = false

@description('Register the request\'s resource providers. In Bicep the module does this with a deployment script, which creates billable helper resources, so it is off by default.')
param registerResourceProviders bool = false

@description('AVM module usage telemetry. See https://aka.ms/avm/telemetryinfo.')
param enableTelemetry bool = true

// ---------- Derived values ----------

var location = request.?location ?? 'uksouth'
var name = '${prefix}-${request.workload}-${request.environment}' // e.g. alz-payments-prod

var tags = union(request.tags, {
  managedBy: 'subscription-vending'
  requestId: name
})

// The module's role-assignment sub-module only knows five role names, so map
// the common names to their built-in role definition GUIDs here.
var roleDefinitionIds = {
  Owner: '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
  Contributor: 'b24988ac-6180-42a0-ab88-20f7382dd24c'
  Reader: 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
  'User Access Administrator': '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9'
  'Role Based Access Control Administrator': 'f58310d9-a9f6-439a-9e8d-f62e7b41a168'
  'Network Contributor': '4d97b98b-1d4f-4787-a291-c67834d212e7'
}

var roleAssignments = [
  for ra in request.role_assignments: {
    principalId: ra.principal_id
    principalType: ra.?principal_type
    definition: '/providers/Microsoft.Authorization/roleDefinitions/${roleDefinitionIds[?ra.role] ?? toLower(ra.role)}'
    relativeScope: '' // subscription scope
  }
]

var resourceProviders = registerResourceProviders
  ? toObject(request.?resource_providers ?? [], rp => rp, rp => [])
  : {}

// ---------- The vending module ----------

module subVending 'br/public:avm/ptn/lz/sub-vending:0.8.0' = {
  name: take('vend-${name}', 64)
  params: {
    enableTelemetry: enableTelemetry

    // 1. New subscription (alias) or existing subscription.
    subscriptionAliasEnabled: subscriptionAliasEnabled
    subscriptionAliasName: subscriptionAliasEnabled ? name : ''
    subscriptionDisplayName: subscriptionAliasEnabled ? name : ''
    subscriptionBillingScope: subscriptionAliasEnabled ? billingScope : ''
    subscriptionWorkload: request.?subscription_workload_type ?? 'Production'
    existingSubscriptionId: subscriptionAliasEnabled ? '' : existingSubscriptionId
    subscriptionTags: tags

    // 2. Management group placement.
    subscriptionManagementGroupAssociationEnabled: true
    subscriptionManagementGroupId: request.management_group_id

    // 3. Resource providers (empty object = no deployment script).
    resourceProviders: resourceProviders

    // 4. Budget with email notifications from the request.
    budgetName: 'budget-${name}'
    budgetAmount: request.budget.amount
    budgetThresholdType: request.budget.?threshold_type ?? 'Actual'
    budgetThresholds: request.budget.thresholds
    budgetContactEmails: request.budget.contact_emails

    // 5. Spoke network. The module creates an NSG for each subnet.
    virtualNetworkEnabled: true
    virtualNetworkLocation: location
    virtualNetworkResourceGroupName: 'rg-${name}-network-${location}'
    virtualNetworkResourceGroupTags: tags
    virtualNetworkResourceGroupLockEnabled: false // the module's default (true) blocks clean-up
    virtualNetworkName: 'vnet-${name}-${location}'
    virtualNetworkTags: tags
    virtualNetworkAddressSpace: request.network.address_space
    virtualNetworkSubnets: [
      for s in request.network.subnets: {
        name: s.name
        addressPrefix: s.address_prefix
        networkSecurityGroup: {
          name: 'nsg-${name}-${s.name}'
        }
      }
    ]

    // 6. Optional hub peering, off by default (the hub is chapter 8).
    virtualNetworkPeeringEnabled: hubPeeringEnabled
    hubNetworkResourceId: hubPeeringEnabled ? hubVirtualNetworkResourceId : ''
    virtualNetworkUseRemoteGateways: hubUseRemoteGateways

    // 7. Role assignments at subscription scope.
    roleAssignmentEnabled: true
    roleAssignments: roleAssignments
  }
}

output subscriptionId string = subVending.outputs.subscriptionId
output subscriptionResourceId string = subVending.outputs.subscriptionResourceId
output virtualNetworkResourceGroupName string = 'rg-${name}-network-${location}'
output budgetName string = 'budget-${name}'
