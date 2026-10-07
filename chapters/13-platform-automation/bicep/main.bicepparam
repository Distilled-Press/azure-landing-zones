using 'main.bicep'

// Deploy at the management group that should receive the roles (the identities'
// subscription must be in it, or below it):
//   az deployment mg create --management-group-id alz --location uksouth \
//     --name ch13-identity --parameters main.bicepparam

param subscriptionId = '00000000-0000-0000-0000-000000000000'

param githubOrganization = 'my-github-org'
param githubRepository = 'azure-landing-zones'

param prefix = 'alz'
param location = 'uksouth'

// The defaults, written out. Plan: Reader, trusted for pull requests and main.
// Apply: Owner, trusted only for jobs in the "alz-apply" GitHub environment.
param identities = [
  {
    key: 'plan'
    roleDefinitionIdOrName: 'Reader'
    federatedCredentials: [
      { name: 'github-pull-request', type: 'pull_request' }
      { name: 'github-main-branch', type: 'branch', value: 'main' }
    ]
  }
  {
    key: 'apply'
    roleDefinitionIdOrName: 'Owner'
    federatedCredentials: [
      { name: 'github-apply-environment', type: 'environment', value: 'alz-apply' }
    ]
  }
]

// Azure DevOps: copy the Issuer and Subject identifier from the service connection.
param additionalFederatedCredentials = [
  // {
  //   identityKey: 'apply'
  //   name: 'ado-sc-alz-apply'
  //   issuer: '<issuer shown by the service connection>'
  //   subject: '<subject identifier shown by the service connection>'
  // }
]

// Reader on subscriptionId for sign-in; false when the subscription is under this management group.
param subscriptionReaderEnabled = true

// Storage account for Terraform state (small monthly cost).
param stateStorageEnabled = false

param tags = {}
param enableTelemetry = true
