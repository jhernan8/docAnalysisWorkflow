// ============================================================================
// Parameters file for Contract Analysis Solution
// Copy this file and customize for your environment
// ============================================================================

using 'main.bicep'

// Base name for all resources (3-15 characters, alphanumeric and hyphens)
param baseName = 'contracts'

// Environment: dev, staging, or prod
param environment = 'dev'

// Azure AD Admin for SQL Server (Azure AD-only authentication)
// Run: az ad signed-in-user show --query id -o tsv
param sqlAadAdminObjectId = '' // Your Azure AD Object ID

// Run: az ad signed-in-user show --query userPrincipalName -o tsv
param sqlAadAdminDisplayName = '' // Your email/UPN

// SharePoint Configuration
param sharePointSiteUrl = '' // e.g., 'https://contoso.sharepoint.com/sites/ContractAI'
param sharePointLibraryId = '' // e.g., '0c082b7c-8834-480c-8b30-47ba73e8562c'

// ============================================================================
// Networking Configuration
// ============================================================================

// Existing VNet
param vnetName = 'cai-a1-tst-vnet-spoke01'
param vnetResourceGroupName = '' // Resource group containing the VNet

// Subnet address ranges (must not overlap with existing subnets in the VNet)
param privateEndpointSubnetAddressPrefix = '' // e.g., '10.0.4.0/24'
param vnetIntegrationSubnetAddressPrefix = '' // e.g., '10.0.5.0/24'
param logicAppSubnetAddressPrefix = ''        // e.g., '10.0.6.0/24'

// Private DNS Zones (deployed in a different subscription)
param dnsZoneSubscriptionId = '' // Subscription ID where DNS Zones live
param dnsZoneResourceGroupName = '' // Resource group containing DNS Zones

// Optional: Override locations (defaults to resource group location)
// param location = 'eastus'
// param sqlLocation = 'centralus'
