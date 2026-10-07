// Chapter 13: identities for the platform pipeline.
// User-assigned managed identities with federated credentials for a GitHub
// repository (no secrets), each given a role on the management group this
// template is deployed to, plus optional Terraform state storage.
//
// Deploy at the management group that should receive the roles. The
// subscription that holds the identities must be in that management group (or
// below it): ARM only lets a management group deployment reach subscriptions in
// the management group.
//   az deployment mg create --management-group-id alz --location uksouth \
//     --name ch13-identity --parameters main.bicepparam
targetScope = 'managementGroup'

@description('Subscription for the identity resource group (and the optional state storage). In ALZ, the management subscription.')
param subscriptionId string

@description('Prefix used in the names this template creates.')
param prefix string = 'alz'

@description('Region of the resource group, identities and optional storage account.')
param location string = 'uksouth'

@description('Name of the resource group for the identities.')
param resourceGroupName string = 'rg-${prefix}-platform-automation-${location}'

@description('GitHub organisation (or user) that owns the repository.')
param githubOrganization string

@description('GitHub repository that runs the platform pipeline.')
param githubRepository string

type federatedCredential = {
  @description('Credential name (3-120 characters: letters, numbers, hyphens, underscores).')
  name: string
  @description('environment | branch | tag | pull_request')
  type: ('environment' | 'branch' | 'tag' | 'pull_request')
  @description('Environment, branch or tag name. Leave out for pull_request.')
  value: string?
}

type platformIdentity = {
  @description('Short key used in the identity name, for example plan or apply.')
  key: string
  @description('Built-in role on the management group: Reader, Contributor or Owner (names the role-assignment module knows), or a role definition resource ID.')
  roleDefinitionIdOrName: string
  @maxLength(20)
  federatedCredentials: federatedCredential[]
}

@description('One user-assigned managed identity per entry, each with a role on this management group and GitHub federated credentials.')
param identities platformIdentity[] = [
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

type extraCredential = {
  @description('Key of the identity in the identities parameter.')
  identityKey: string
  name: string
  issuer: string
  subject: string
}

@description('Federated credentials from other issuers, for example an Azure DevOps service connection (copy its Issuer and Subject identifier).')
param additionalFederatedCredentials extraCredential[] = []

@description('Also give every identity Reader on subscriptionId: azure/login and the AzureCLI task select that subscription when they sign in. Inherited (set false) when the subscription is under this management group.')
param subscriptionReaderEnabled bool = true

@description('Create a storage account and container for Terraform state, with Storage Blob Data Contributor on the container for every identity. Billable (small).')
param stateStorageEnabled bool = false

@description('Tags for every resource created here.')
param tags object = {}

@description('AVM module usage telemetry. No cost.')
param enableTelemetry bool = true

var repo = '${githubOrganization}/${githubRepository}'

// GitHub's OIDC token subject ("sub" claim) for each kind of job; the
// credential's subject must match it exactly.
var subjectPrefix = {
  environment: 'repo:${repo}:environment:'
  branch: 'repo:${repo}:ref:refs/heads/'
  tag: 'repo:${repo}:ref:refs/tags/'
  pull_request: 'repo:${repo}:pull_request'
}

// ---------- Resource group ----------

module resourceGroup 'br/public:avm/res/resources/resource-group:0.4.4' = {
  name: 'ch13-rg'
  scope: subscription(subscriptionId)
  params: {
    name: resourceGroupName
    location: location
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

// ---------- Identities with federated credentials ----------
// The module creates the credentials one at a time (@batchSize(1) inside):
// Learn says concurrent writes to credentials on the same identity fail with 409.

module identity 'br/public:avm/res/managed-identity/user-assigned-identity:0.6.0' = [
  for id in identities: {
    name: 'ch13-id-${id.key}'
    scope: az.resourceGroup(subscriptionId, resourceGroupName)
    dependsOn: [resourceGroup]
    params: {
      name: 'id-${prefix}-platform-${id.key}-${location}'
      location: location
      federatedIdentityCredentials: concat(
        map(id.federatedCredentials, c => {
          name: c.name
          issuer: 'https://token.actions.githubusercontent.com'
          audiences: ['api://AzureADTokenExchange']
          subject: c.type == 'pull_request' ? subjectPrefix.pull_request : '${subjectPrefix[c.type]}${c.?value ?? ''}'
        }),
        map(filter(additionalFederatedCredentials, x => x.identityKey == id.key), x => {
          name: x.name
          issuer: x.issuer
          audiences: ['api://AzureADTokenExchange']
          subject: x.subject
        })
      )
      tags: tags
      enableTelemetry: enableTelemetry
    }
  }
]

// ---------- Role on this management group ----------

module roleAssignment 'br/public:avm/ptn/authorization/role-assignment:0.2.4' = [
  for (id, i) in identities: {
    name: 'ch13-ra-${id.key}'
    params: {
      managementGroupId: managementGroup().name
      principalId: identity[i].outputs.principalId
      principalType: 'ServicePrincipal'
      roleDefinitionIdOrName: id.roleDefinitionIdOrName
      description: 'Platform pipeline (${id.key}) for ${repo}'
      enableTelemetry: enableTelemetry
    }
  }
]

// Read access to the subscription the pipelines sign in to.
module subscriptionReader 'br/public:avm/ptn/authorization/role-assignment:0.2.4' = [
  for (id, i) in identities: if (subscriptionReaderEnabled) {
    name: 'ch13-ra-sub-${id.key}'
    params: {
      subscriptionId: subscriptionId
      principalId: identity[i].outputs.principalId
      principalType: 'ServicePrincipal'
      roleDefinitionIdOrName: 'Reader'
      description: 'Platform pipeline (${id.key}) sign-in subscription'
      enableTelemetry: enableTelemetry
    }
  }
]

// ---------- Optional: Terraform state storage ----------

module stateStorage 'br/public:avm/res/storage/storage-account:0.33.1' = if (stateStorageEnabled) {
  name: 'ch13-state'
  scope: az.resourceGroup(subscriptionId, resourceGroupName)
  dependsOn: [resourceGroup]
  params: {
    name: take('st${prefix}tfstate${uniqueString(subscriptionId, resourceGroupName)}', 24)
    location: location
    skuName: 'Standard_LRS'
    allowSharedKeyAccess: false // Entra ID only; pipelines use OIDC for the backend too
    publicNetworkAccess: 'Enabled' // hosted runners/agents come from the internet
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    blobServices: {
      isVersioningEnabled: true
      deleteRetentionPolicyEnabled: true
      deleteRetentionPolicyDays: 30
      containerDeleteRetentionPolicyEnabled: true
      containerDeleteRetentionPolicyDays: 30
      containers: [
        {
          name: 'tfstate'
          roleAssignments: [
            for (id, i) in identities: {
              principalId: identity[i].outputs.principalId
              principalType: 'ServicePrincipal'
              roleDefinitionIdOrName: 'Storage Blob Data Contributor'
            }
          ]
        }
      ]
    }
    tags: tags
    enableTelemetry: enableTelemetry
  }
}

output tenantId string = tenant().tenantId
output subscriptionId string = subscriptionId
@description('Identity key, client ID (the AZURE_CLIENT_ID_* repository variables) and principal ID for each identity.')
output identities array = [
  for (id, i) in identities: {
    key: id.key
    clientId: identity[i].outputs.clientId
    principalId: identity[i].outputs.principalId
    subjects: map(
      id.federatedCredentials,
      c => c.type == 'pull_request' ? subjectPrefix.pull_request : '${subjectPrefix[c.type]}${c.?value ?? ''}'
    )
  }
]
output stateStorageAccountName string = stateStorageEnabled ? stateStorage!.outputs.name : ''
