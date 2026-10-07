using 'main.bicep'

// Deploy to the management subscription:
//   az account set --subscription <management-subscription-id>
//   az deployment sub create --name ch12-management --location uksouth --parameters main.bicepparam

param prefix = 'alz'
param location = 'uksouth'

param logAnalyticsRetentionInDays = 30
// Optional safety-net cap in GB; -1 means no cap.
param logAnalyticsDailyQuotaGb = -1

// Each NEW address receives a "Verify your email address" message with a
// one-time passcode that expires after 30 minutes. Verify it, or the address
// gets no alerts.
param actionGroupEmailAddresses = [
  'platform-team@example.com'
]

param serviceHealthAlertEnabled = true
// param serviceHealthRegions = ['UK South', 'UK West', 'Global']

param tags = {}
param enableTelemetry = true
