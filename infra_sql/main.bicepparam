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

// Content Understanding Analyzer ID
// Create this in Azure Portal under your AI Services resource
param contentUnderstandingAnalyzerId = 'contract-analyzer'

// SharePoint Configuration
// Site URL: The full URL to your SharePoint site
param sharePointSiteUrl = '' // e.g., 'https://contoso.sharepoint.com/sites/ContractAI'

// Library ID: The GUID of the document library where contracts are uploaded
// To find this: Go to Library Settings -> Look at the URL for the List parameter
// Or use: SharePoint REST API /_api/web/lists?$filter=BaseTemplate eq 101
param sharePointLibraryId = '' // e.g., '0c082b7c-8834-480c-8b30-47ba73e8562c'

// Optional: Override location (defaults to resource group location)
// param location = 'eastus'
