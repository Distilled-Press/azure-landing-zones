// One .bicepparam file per request: loadYamlContent needs a fixed path.
// Copy this file for each new request and change the path.
using 'main.bicep'

param request = loadYamlContent('../requests/example-payments-prod.yaml')

param prefix = 'alz'

// Mode A (default): configure an EXISTING subscription.
//   export ALZ_EXISTING_SUBSCRIPTION_ID=<subscription GUID>
// Mode B: create a NEW subscription (needs billing rights on the billing scope).
//   export ALZ_SUBSCRIPTION_ALIAS_ENABLED=true
//   export ALZ_BILLING_SCOPE=/providers/Microsoft.Billing/billingAccounts/.../invoiceSections/...
param subscriptionAliasEnabled = bool(readEnvironmentVariable('ALZ_SUBSCRIPTION_ALIAS_ENABLED', 'false'))
param existingSubscriptionId = readEnvironmentVariable('ALZ_EXISTING_SUBSCRIPTION_ID', '')
param billingScope = readEnvironmentVariable('ALZ_BILLING_SCOPE', '')

// Optional hub peering (chapter 8). Off by default.
param hubPeeringEnabled = false
param hubVirtualNetworkResourceId = ''
param hubUseRemoteGateways = false

// Resource provider registration runs a deployment script (billable helper
// resources) in the Bicep module, so it is off by default.
param registerResourceProviders = false
