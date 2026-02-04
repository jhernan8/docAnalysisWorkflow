// ============================================================================
// Parameters for Contract Search Solution
// ============================================================================

using 'main.bicep'

// Base configuration
param baseName = 'cntrct-srch'
param environment = 'dev'

// Locations
param primaryLocation = 'centralus'
param aiLocation = 'westus'  // Required for Foundry preview features

// SharePoint Configuration
// Update these with your SharePoint site details
param sharePointSiteUrl = 'https://mngenvmcap560696.sharepoint.com/sites/ContractAI'
param sharePointLibraryId = '0c082b7c-8834-480c-8b30-47ba73e8562c'

// Feature flags
param deployAISearch = true
param deployAIServices = true

// AI Search tier
param aiSearchSku = 'basic'
