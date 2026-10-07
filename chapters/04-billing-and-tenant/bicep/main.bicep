metadata name = 'Subscription alias against a billing scope'
metadata description = 'Creates one Azure subscription with Microsoft.Subscription/aliases (chapter 4).'

// Deploy at a management group (az deployment mg). The alias itself is a
// tenant-scope resource, so it is deployed with scope: tenant(). This is the
// pattern Microsoft Learn documents for MCA; it avoids needing deployment
// rights at the tenant root ("/").
targetScope = 'managementGroup'

@description('Full resource ID of the billing scope. MCA: the invoice section ID (/providers/Microsoft.Billing/billingAccounts/<account>/billingProfiles/<profile>/invoiceSections/<section>). EA: /providers/Microsoft.Billing/billingAccounts/<enrolment>/enrollmentAccounts/<account>.')
param billingScopeId string

@description('Name of the alias (the creation request). The same alias name never creates a second subscription. Letters, digits and hyphens; start with a letter; no periods.')
@minLength(2)
@maxLength(63)
param subscriptionAliasName string

@description('Display name of the new subscription.')
param subscriptionDisplayName string

@description('Workload type: Production (Microsoft Azure Plan) or DevTest (Microsoft Azure Plan for DevTest).')
@allowed([
  'Production'
  'DevTest'
])
param subscriptionWorkload string = 'Production'

@description('Optional ID (name) of the management group to place the subscription in, for example alz-corp. Empty leaves it in the default management group.')
param managementGroupId string = ''

@description('Tags to set on the subscription itself.')
param subscriptionTags object = {}

resource subscriptionAlias 'Microsoft.Subscription/aliases@2021-10-01' = {
  scope: tenant()
  name: subscriptionAliasName
  properties: {
    displayName: subscriptionDisplayName
    workload: subscriptionWorkload
    billingScope: billingScopeId
    additionalProperties: {
      managementGroupId: empty(managementGroupId)
        ? null
        : tenantResourceId('Microsoft.Management/managementGroups', managementGroupId)
      tags: subscriptionTags
    }
  }
}

@description('ID of the subscription the alias created.')
output subscriptionId string = subscriptionAlias.properties.subscriptionId

@description('Resource ID of the new subscription.')
output subscriptionResourceId string = '/subscriptions/${subscriptionAlias.properties.subscriptionId}'
