// Deploy at subscription scope:
//   az deployment sub create --subscription 00000000-0000-0000-0000-000000000000 \
//     --location uksouth --name ch11-security --parameters main.bicepparam
using 'main.bicep'

param prefix = 'alz'

// Defender for Cloud email notifications (free).
param securityContactEmails = [
  'security-team@example.com'
]
param notifyRoles = [
  'Owner'
]
param alertMinimalSeverity = 'Medium'
param attackPathMinimalRiskLevel = 'Critical'

// PAID Defender plans, subscription-wide. Default: none.
// Pricing: https://azure.microsoft.com/pricing/details/defender-for-cloud/
param defenderPlans = []
// param defenderPlans = [
//   { name: 'VirtualMachines', pricingTier: 'Standard', subPlan: 'P1' }                 // Defender for Servers Plan 1
//   { name: 'StorageAccounts', pricingTier: 'Standard', subPlan: 'DefenderForStorageV2' } // Defender for Storage
//   { name: 'KeyVaults', pricingTier: 'Standard' }                                      // Defender for Key Vault
// ]

// Microsoft Sentinel on a new Log Analytics workspace. BILLABLE once data flows.
param deploySentinel = false
param logRetentionDays = 30
param connectAzureActivity = true
