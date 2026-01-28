// ============================================================================
// Contract Analysis Solution - Main Deployment
// Deploys: Function App, Logic App, SQL Database, AI Services, Storage
// All with proper managed identity permissions
// ============================================================================

targetScope = 'resourceGroup'

// ============================================================================
// Parameters
// ============================================================================

@description('Base name for all resources (will be used as prefix)')
@minLength(3)
@maxLength(15)
param baseName string

@description('Azure region for primary resources (Function App, Storage, AI Services)')
param location string = resourceGroup().location

@description('Azure region for SQL Database (some regions have restrictions)')
param sqlLocation string = 'centralus'

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Azure AD Object ID of the SQL Admin user (for AAD auth)')
param sqlAadAdminObjectId string

@description('Azure AD display name of the SQL Admin user')
param sqlAadAdminDisplayName string

@description('Content Understanding Analyzer ID (create this in Azure portal first)')
param contentUnderstandingAnalyzerId string

@description('SharePoint site URL (e.g., https://contoso.sharepoint.com/sites/ContractAI)')
param sharePointSiteUrl string

@description('SharePoint document library ID (GUID of the library where contracts are uploaded)')
param sharePointLibraryId string

@description('Tags to apply to all resources')
param tags object = {
  environment: environment
  solution: 'contract-analysis'
  deployedBy: 'bicep'
}

// ============================================================================
// Variables
// ============================================================================

var uniqueSuffix = uniqueString(resourceGroup().id)
var resourcePrefix = '${baseName}-${environment}'

// Resource names
var storageAccountName = toLower(replace('${baseName}${environment}${uniqueSuffix}', '-', ''))
var functionAppName = '${resourcePrefix}-func-${uniqueSuffix}'
var appServicePlanName = '${resourcePrefix}-asp'
var logicAppName = '${resourcePrefix}-logic'
var sqlServerName = '${resourcePrefix}-sql-${uniqueSuffix}'
var sqlDatabaseName = 'contractsdb'
var aiServicesName = '${resourcePrefix}-ai-${uniqueSuffix}'
var logAnalyticsName = '${resourcePrefix}-logs'
var appInsightsName = '${resourcePrefix}-insights'

// ============================================================================
// Modules
// ============================================================================

// Log Analytics & Application Insights
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring-deployment'
  params: {
    location: location
    logAnalyticsName: logAnalyticsName
    appInsightsName: appInsightsName
    tags: tags
  }
}

// Storage Account (for Function App and Logic App blob trigger)
module storage 'modules/storage.bicep' = {
  name: 'storage-deployment'
  params: {
    location: location
    storageAccountName: take(storageAccountName, 24) // Max 24 chars
    tags: tags
  }
}

// Azure AI Services (Content Understanding)
module aiServices 'modules/ai-services.bicep' = {
  name: 'ai-services-deployment'
  params: {
    location: location
    aiServicesName: aiServicesName
    tags: tags
  }
}

// Azure SQL Database (Azure AD-only authentication)
module sql 'modules/sql.bicep' = {
  name: 'sql-deployment'
  params: {
    location: sqlLocation
    sqlServerName: sqlServerName
    sqlDatabaseName: sqlDatabaseName
    sqlAadAdminObjectId: sqlAadAdminObjectId
    sqlAadAdminDisplayName: sqlAadAdminDisplayName
    tags: tags
  }
}

// Function App with App Service Plan
module functionApp 'modules/function-app.bicep' = {
  name: 'function-app-deployment'
  params: {
    location: location
    functionAppName: functionAppName
    appServicePlanName: appServicePlanName
    storageAccountName: storage.outputs.storageAccountName
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    contentUnderstandingEndpoint: aiServices.outputs.endpoint
    contentUnderstandingAnalyzerId: contentUnderstandingAnalyzerId
    sqlServerName: sql.outputs.sqlServerName
    sqlDatabaseName: sql.outputs.sqlDatabaseName
    tags: tags
  }
}

// Logic App (SharePoint trigger -> Function App)
// Note: Function key header is set to placeholder, updated post-deployment
module logicApp 'modules/logic-app-sharepoint.bicep' = {
  name: 'logic-app-deployment'
  params: {
    location: location
    logicAppName: logicAppName
    functionAppHostname: replace(functionApp.outputs.functionAppUrl, 'https://', '')
    sharePointSiteUrl: sharePointSiteUrl
    sharePointLibraryId: sharePointLibraryId
    tags: tags
  }
}

// ============================================================================
// Role Assignments (Permissions)
// ============================================================================

// Grant Function App access to Cognitive Services (Content Understanding)
module functionToCognitiveServices 'modules/role-assignment.bicep' = {
  name: 'func-to-cognitive-role'
  params: {
    principalId: functionApp.outputs.functionAppPrincipalId
    roleDefinitionId: 'a97b65f3-24c7-4388-baec-2e87135dc908' // Cognitive Services User
    principalType: 'ServicePrincipal'
    resourceId: aiServices.outputs.aiServicesId
  }
}

// ============================================================================
// Function App Storage Roles (Required for Managed Identity connection)
// ============================================================================

// Storage Blob Data Owner - Required for AzureWebJobsStorage
module functionToStorageBlobOwner 'modules/role-assignment.bicep' = {
  name: 'func-to-storage-blob-owner'
  params: {
    principalId: functionApp.outputs.functionAppPrincipalId
    roleDefinitionId: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' // Storage Blob Data Owner
    principalType: 'ServicePrincipal'
    resourceId: storage.outputs.storageAccountId
  }
}

// Storage Queue Data Contributor - Required for trigger/binding operations
module functionToStorageQueue 'modules/role-assignment.bicep' = {
  name: 'func-to-storage-queue'
  params: {
    principalId: functionApp.outputs.functionAppPrincipalId
    roleDefinitionId: '974c5e8b-45b9-4653-ba55-5f855dd0fb88' // Storage Queue Data Contributor
    principalType: 'ServicePrincipal'
    resourceId: storage.outputs.storageAccountId
  }
}

// Storage Table Data Contributor - Required for some internal operations
module functionToStorageTable 'modules/role-assignment.bicep' = {
  name: 'func-to-storage-table'
  params: {
    principalId: functionApp.outputs.functionAppPrincipalId
    roleDefinitionId: '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3' // Storage Table Data Contributor
    principalType: 'ServicePrincipal'
    resourceId: storage.outputs.storageAccountId
  }
}

// Storage File Data SMB Share Contributor - Required for WEBSITE_CONTENTAZUREFILECONNECTIONSTRING
module functionToStorageFile 'modules/role-assignment.bicep' = {
  name: 'func-to-storage-file'
  params: {
    principalId: functionApp.outputs.functionAppPrincipalId
    roleDefinitionId: '0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb' // Storage File Data SMB Share Contributor
    principalType: 'ServicePrincipal'
    resourceId: storage.outputs.storageAccountId
  }
}

// Note: Logic App uses SharePoint connection, no storage role needed for Logic App
// The SharePoint connection requires interactive OAuth consent in Azure Portal

// ============================================================================
// Outputs
// ============================================================================

output functionAppName string = functionApp.outputs.functionAppName
output functionAppUrl string = functionApp.outputs.functionAppUrl
output logicAppName string = logicApp.outputs.logicAppName
output sharePointConnectionName string = logicApp.outputs.sharePointConnectionName
output sqlServerFqdn string = sql.outputs.sqlServerFqdn
output sqlDatabaseName string = sql.outputs.sqlDatabaseName
output storageAccountName string = storage.outputs.storageAccountName
output aiServicesEndpoint string = aiServices.outputs.endpoint
output functionAppPrincipalId string = functionApp.outputs.functionAppPrincipalId

// Post-deployment instructions
output postDeploymentInstructions string = '''
================================================================================
POST-DEPLOYMENT STEPS:
================================================================================

1. DEPLOY FUNCTION APP CODE:
   cd azure_function_sql
   func azure functionapp publish ${functionAppName}

2. GRANT SQL DATABASE ACCESS (run as Azure AD admin):
   CREATE USER [${functionAppName}] FROM EXTERNAL PROVIDER;
   ALTER ROLE db_datareader ADD MEMBER [${functionAppName}];
   ALTER ROLE db_datawriter ADD MEMBER [${functionAppName}];

3. CREATE DATABASE TABLES:
   Run create_tables.sql against the SQL database

4. AUTHORIZE SHAREPOINT CONNECTION:
   - Go to Azure Portal -> Resource Group -> API Connections
   - Click on the SharePoint connection
   - Click "Edit API connection" 
   - Click "Authorize" and sign in with your SharePoint account
   - Click "Save"

5. ENABLE LOGIC APP:
   - Go to Azure Portal -> Logic Apps -> ${logicAppName}
   - Click "Enable"

6. TEST:
   Upload a PDF contract to your SharePoint document library
================================================================================
'''
