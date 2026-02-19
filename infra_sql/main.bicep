// ============================================================================
// Contract Analysis Solution - Main Deployment
// Deploys: Function App, Logic App, SQL Database, AI Services, Storage
// All with proper managed identity permissions and private endpoints
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
// Networking Parameters
// ============================================================================

@description('Name of the existing VNet')
param vnetName string

@description('Resource group containing the existing VNet')
param vnetResourceGroupName string

@description('Address prefix for the private endpoint subnet (e.g., 10.0.4.0/24)')
param privateEndpointSubnetAddressPrefix string

@description('Address prefix for the Function App VNet integration subnet (e.g., 10.0.5.0/24)')
param vnetIntegrationSubnetAddressPrefix string

@description('Address prefix for the Logic App Standard VNet integration subnet (e.g., 10.0.6.0/24)')
param logicAppSubnetAddressPrefix string

@description('Subscription ID where Private DNS Zones are deployed')
param dnsZoneSubscriptionId string

@description('Resource group containing the Private DNS Zones')
param dnsZoneResourceGroupName string

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
var logAnalyticsName = '${resourcePrefix}-logs'
var appInsightsName = '${resourcePrefix}-insights'

// Private DNS Zone IDs (cross-subscription)
var dnsZoneBaseId = '/subscriptions/${dnsZoneSubscriptionId}/resourceGroups/${dnsZoneResourceGroupName}/providers/Microsoft.Network/privateDnsZones'

// Environment-specific DNS zone suffixes (cloud-portable)
var storageSuffix = az.environment().suffixes.storage
var sqlSuffix = az.environment().suffixes.sqlServerHostname

// ============================================================================
// Networking - Subnets on Existing VNet
// ============================================================================

module subnets 'modules/subnets.bicep' = {
  name: 'subnets-deployment'
  scope: resourceGroup(vnetResourceGroupName)
  params: {
    vnetName: vnetName
    privateEndpointSubnetAddressPrefix: privateEndpointSubnetAddressPrefix
    vnetIntegrationSubnetAddressPrefix: vnetIntegrationSubnetAddressPrefix
    logicAppSubnetAddressPrefix: logicAppSubnetAddressPrefix
  }
}

// ============================================================================
// Modules
// ============================================================================

// Log Analytics & Application Insights (no private endpoint — public access retained)
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring-deployment'
  params: {
    location: location
    logAnalyticsName: logAnalyticsName
    appInsightsName: appInsightsName
    tags: tags
  }
}

// Storage Account (deployed with public access to allow Function App provisioning;
// the deploy script locks it down after all resources are created)
module storage 'modules/storage.bicep' = {
  name: 'storage-deployment'
  params: {
    location: location
    storageAccountName: take(storageAccountName, 24)
    tags: tags
    publicNetworkAccess: 'Enabled'
  }
}

// NOTE: Azure AI Foundry (Content Understanding) must be created manually in Azure Portal.
// The Function App is granted Cognitive Services User role at the RG level,
// so any AI Foundry resource created here will be accessible.

// Azure SQL Database (private endpoint, public access disabled)
module sql 'modules/sql.bicep' = {
  name: 'sql-deployment'
  params: {
    location: sqlLocation
    sqlServerName: sqlServerName
    sqlDatabaseName: sqlDatabaseName
    sqlAadAdminObjectId: sqlAadAdminObjectId
    sqlAadAdminDisplayName: sqlAadAdminDisplayName
    tags: tags
    publicNetworkAccess: 'Disabled'
  }
}

// Function App with VNet integration (outbound) and private endpoint (inbound)
// Public access disabled — Logic App Standard reaches it via VNet integration
module functionApp 'modules/function-app.bicep' = {
  name: 'function-app-deployment'
  params: {
    location: location
    functionAppName: functionAppName
    appServicePlanName: appServicePlanName
    storageAccountName: storage.outputs.storageAccountName
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    sqlServerName: sql.outputs.sqlServerName
    sqlDatabaseName: sql.outputs.sqlDatabaseName
    tags: tags
    virtualNetworkSubnetId: subnets.outputs.funcIntegrationSubnetId
    publicNetworkAccess: 'Disabled'
  }
}

// Logic App Standard (SharePoint trigger -> Function App)
// Standard tier supports VNet integration and private endpoints
module logicApp 'modules/logic-app-standard.bicep' = {
  name: 'logic-app-deployment'
  params: {
    location: location
    logicAppName: logicAppName
    functionAppHostname: replace(functionApp.outputs.functionAppUrl, 'https://', '')
    sharePointSiteUrl: sharePointSiteUrl
    sharePointLibraryId: sharePointLibraryId
    storageAccountName: storage.outputs.storageAccountName
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    virtualNetworkSubnetId: subnets.outputs.logicAppSubnetId
    publicNetworkAccess: 'Disabled'
    tags: tags
  }
}

// ============================================================================
// Role Assignments (Permissions)
// ============================================================================

// Grant Function App Cognitive Services User role at Resource Group level
module functionToCognitiveServices 'modules/role-assignment.bicep' = {
  name: 'func-to-cognitive-role'
  params: {
    principalId: functionApp.outputs.functionAppPrincipalId
    roleDefinitionId: 'a97b65f3-24c7-4388-baec-2e87135dc908' // Cognitive Services User
    principalType: 'ServicePrincipal'
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

// Note: Logic App Standard uses same storage account — needs blob/queue/table roles
// The SharePoint connection requires interactive OAuth consent in Azure Portal

// Grant Logic App Standard storage roles for workflow state
module logicAppToStorageBlobOwner 'modules/role-assignment.bicep' = {
  name: 'logic-to-storage-blob-owner'
  params: {
    principalId: logicApp.outputs.logicAppPrincipalId
    roleDefinitionId: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' // Storage Blob Data Owner
    principalType: 'ServicePrincipal'
    resourceId: storage.outputs.storageAccountId
  }
}

module logicAppToStorageQueue 'modules/role-assignment.bicep' = {
  name: 'logic-to-storage-queue'
  params: {
    principalId: logicApp.outputs.logicAppPrincipalId
    roleDefinitionId: '974c5e8b-45b9-4653-ba55-5f855dd0fb88' // Storage Queue Data Contributor
    principalType: 'ServicePrincipal'
    resourceId: storage.outputs.storageAccountId
  }
}

module logicAppToStorageTable 'modules/role-assignment.bicep' = {
  name: 'logic-to-storage-table'
  params: {
    principalId: logicApp.outputs.logicAppPrincipalId
    roleDefinitionId: '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3' // Storage Table Data Contributor
    principalType: 'ServicePrincipal'
    resourceId: storage.outputs.storageAccountId
  }
}

module logicAppToStorageFile 'modules/role-assignment.bicep' = {
  name: 'logic-to-storage-file'
  params: {
    principalId: logicApp.outputs.logicAppPrincipalId
    roleDefinitionId: '0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb' // Storage File Data SMB Share Contributor
    principalType: 'ServicePrincipal'
    resourceId: storage.outputs.storageAccountId
  }
}

// ============================================================================
// Private Endpoints
// ============================================================================

// Storage Account - Blob
module peStorageBlob 'modules/private-endpoint.bicep' = {
  name: 'pe-storage-blob'
  params: {
    name: '${resourcePrefix}-pe-blob'
    location: location
    subnetId: subnets.outputs.peSubnetId
    privateLinkServiceId: storage.outputs.storageAccountId
    groupIds: ['blob']
    privateDnsZoneId: '${dnsZoneBaseId}/privatelink.blob.${storageSuffix}'
    tags: tags
  }
}

// Storage Account - File
module peStorageFile 'modules/private-endpoint.bicep' = {
  name: 'pe-storage-file'
  params: {
    name: '${resourcePrefix}-pe-file'
    location: location
    subnetId: subnets.outputs.peSubnetId
    privateLinkServiceId: storage.outputs.storageAccountId
    groupIds: ['file']
    privateDnsZoneId: '${dnsZoneBaseId}/privatelink.file.${storageSuffix}'
    tags: tags
  }
}

// Storage Account - Queue
module peStorageQueue 'modules/private-endpoint.bicep' = {
  name: 'pe-storage-queue'
  params: {
    name: '${resourcePrefix}-pe-queue'
    location: location
    subnetId: subnets.outputs.peSubnetId
    privateLinkServiceId: storage.outputs.storageAccountId
    groupIds: ['queue']
    privateDnsZoneId: '${dnsZoneBaseId}/privatelink.queue.${storageSuffix}'
    tags: tags
  }
}

// Storage Account - Table
module peStorageTable 'modules/private-endpoint.bicep' = {
  name: 'pe-storage-table'
  params: {
    name: '${resourcePrefix}-pe-table'
    location: location
    subnetId: subnets.outputs.peSubnetId
    privateLinkServiceId: storage.outputs.storageAccountId
    groupIds: ['table']
    privateDnsZoneId: '${dnsZoneBaseId}/privatelink.table.${storageSuffix}'
    tags: tags
  }
}

// Azure SQL Server
module peSql 'modules/private-endpoint.bicep' = {
  name: 'pe-sql'
  params: {
    name: '${resourcePrefix}-pe-sql'
    location: location
    subnetId: subnets.outputs.peSubnetId
    privateLinkServiceId: sql.outputs.sqlServerId
    groupIds: ['sqlServer']
    privateDnsZoneId: '${dnsZoneBaseId}/privatelink${sqlSuffix}'
    tags: tags
  }
}

// Function App (inbound private access)
module peFunc 'modules/private-endpoint.bicep' = {
  name: 'pe-func'
  params: {
    name: '${resourcePrefix}-pe-func'
    location: location
    subnetId: subnets.outputs.peSubnetId
    privateLinkServiceId: functionApp.outputs.functionAppId
    groupIds: ['sites']
    privateDnsZoneId: '${dnsZoneBaseId}/privatelink.azurewebsites.net'
    tags: tags
  }
}

// Logic App Standard (inbound private access)
module peLogicApp 'modules/private-endpoint.bicep' = {
  name: 'pe-logic'
  params: {
    name: '${resourcePrefix}-pe-logic'
    location: location
    subnetId: subnets.outputs.peSubnetId
    privateLinkServiceId: logicApp.outputs.logicAppId
    groupIds: ['sites']
    privateDnsZoneId: '${dnsZoneBaseId}/privatelink.azurewebsites.net'
    tags: tags
  }
}

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
output functionAppPrincipalId string = functionApp.outputs.functionAppPrincipalId

// Post-deployment instructions
output postDeploymentInstructions string = '''
================================================================================
POST-DEPLOYMENT STEPS:
================================================================================

1. DEPLOY FUNCTION APP CODE:
   The deploy script temporarily enables storage public access for publishing,
   then re-disables it after deployment completes.

2. GRANT SQL DATABASE ACCESS (connect via Private Endpoint or from within VNet):
   CREATE USER [<functionAppName>] FROM EXTERNAL PROVIDER;
   ALTER ROLE db_datareader ADD MEMBER [<functionAppName>];
   ALTER ROLE db_datawriter ADD MEMBER [<functionAppName>];

3. CREATE DATABASE TABLES:
   Run create_tables.sql against the SQL database (via PE or VNet)

4. VERIFY DNS ZONE VNET LINKS:
   Ensure all Private DNS Zones have VNet links to the spoke VNet.
   Required zones: privatelink.blob, privatelink.file, privatelink.queue,
   privatelink.table (storage), privatelink (SQL), privatelink (sites)

5. AUTHORIZE SHAREPOINT CONNECTION:
   - Azure Portal -> API Connections -> SharePoint connection
   - Edit API connection -> Authorize -> Sign in -> Save

6. DEPLOY LOGIC APP WORKFLOW:
   The deploy script deploys the workflow definition automatically.

7. TEST:
   Upload a PDF contract to your SharePoint document library
================================================================================
'''
