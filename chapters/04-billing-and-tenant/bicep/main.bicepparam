using './main.bicep'

// Replace the placeholders. See the README for the az billing commands that
// list your billing account, billing profile and invoice section IDs.
param billingScopeId = '/providers/Microsoft.Billing/billingAccounts/00000000-0000-0000-0000-000000000000:00000000-0000-0000-0000-000000000000_2019-05-31/billingProfiles/AAAA-AAAA-AAA-AAA/invoiceSections/BBBB-BBBB-BBB-BBB'
param subscriptionAliasName = 'alz-sub-test-001'
param subscriptionDisplayName = 'alz-sub-test-001'
param subscriptionWorkload = 'DevTest'
param managementGroupId = '' // for example 'alz-corp' once chapter 6 has built the hierarchy
param subscriptionTags = {
  environment: 'test'
  owner: 'platform-team'
}
