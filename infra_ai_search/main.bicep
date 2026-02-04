// ============================================================================
// Contract Search Solution - Full Deployment
// SharePoint → Blob Storage → AI Search → Foundry Agent
// ============================================================================
// Locations:
//   - Central US: Storage, Logic App (preferred region)
//   - West US: AI Services, AI Search (preview access required)
// ============================================================================

targetScope = 'resourceGroup'

// ============================================================================
// Parameters
// ============================================================================

@description('Base name for all resources')
@minLength(3)
@maxLength(15)
param baseName string = 'cntrct-srch'

@description('Environment name')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Primary location for most resources')
param primaryLocation string = 'centralus'

@description('Location for AI Services and AI Search (West US for preview features)')
param aiLocation string = 'westus'

@description('SharePoint site URL')
param sharePointSiteUrl string

@description('SharePoint document library ID (GUID)')
param sharePointLibraryId string

@description('Deploy AI Search service')
param deployAISearch bool = true

@description('Deploy AI Services with model deployments')
param deployAIServices bool = true

@description('AI Search SKU')
@allowed(['free', 'basic', 'standard', 'standard2', 'standard3'])
param aiSearchSku string = 'basic'

@description('Azure AD Object ID of the deploying user (for blob connection authorization)')
param deployingUserObjectId string = ''

@description('Tags for all resources')
param tags object = {
  environment: environment
  solution: 'contract-search'
  deployedBy: 'bicep'
  deployedOn: utcNow('yyyy-MM-dd')
}

// ============================================================================
// Variables
// ============================================================================

var uniqueSuffix = uniqueString(resourceGroup().id)
var resourcePrefix = '${baseName}-${environment}'

// Resource names
var storageAccountName = toLower(take(replace('${baseName}${environment}${uniqueSuffix}', '-', ''), 24))
var aiSearchName = '${resourcePrefix}-search-${uniqueSuffix}'
var aiServicesName = '${resourcePrefix}-ai-${uniqueSuffix}'
var aiProjectName = '${baseName}-project'
var logicAppName = '${resourcePrefix}-logic'

// ============================================================================
// Storage Account
// ============================================================================

module storage 'modules/storage.bicep' = {
  name: 'storage-deployment'
  params: {
    location: primaryLocation
    storageAccountName: storageAccountName
    tags: tags
  }
}

// ============================================================================
// AI Search Service (West US)
// ============================================================================

module aiSearch 'modules/ai-search.bicep' = if (deployAISearch) {
  name: 'ai-search-deployment'
  params: {
    location: aiLocation
    searchServiceName: take(aiSearchName, 60)
    sku: aiSearchSku
    tags: tags
  }
}

// ============================================================================
// AI Services with Project (West US - Foundry)
// ============================================================================

module aiServices 'modules/ai-services-foundry.bicep' = if (deployAIServices) {
  name: 'ai-services-deployment'
  params: {
    location: aiLocation
    aiServicesName: take(aiServicesName, 64)
    projectName: aiProjectName
    tags: tags
  }
}

// ============================================================================
// Logic App with SharePoint Connection
// ============================================================================

module logicApp 'modules/logic-app-sharepoint.bicep' = {
  name: 'logic-app-deployment'
  params: {
    location: primaryLocation
    logicAppName: logicAppName
    storageAccountName: storage.outputs.storageAccountName
    sharePointSiteUrl: sharePointSiteUrl
    sharePointLibraryId: sharePointLibraryId
    tags: tags
  }
}

// ============================================================================
// Role Assignments
// ============================================================================

// Grant Logic App access to Storage
module logicAppStorageRole 'modules/storage-role-assignment.bicep' = {
  name: 'logic-app-storage-role'
  params: {
    storageAccountName: storage.outputs.storageAccountName
    principalId: logicApp.outputs.logicAppPrincipalId
    roleDefinitionId: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
    principalType: 'ServicePrincipal'
  }
}

// Grant AI Search access to Storage (for indexers and debug sessions)
module searchStorageRole 'modules/storage-role-assignment.bicep' = if (deployAISearch) {
  name: 'search-storage-role'
  params: {
    storageAccountName: storage.outputs.storageAccountName
    principalId: aiSearch.outputs.searchPrincipalId
    roleDefinitionId: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor (needs write for debug sessions)
    principalType: 'ServicePrincipal'
  }
}

// Grant AI Search access to AI Services (for Content Understanding skill)
module searchAIServicesRole 'modules/role-assignment.bicep' = if (deployAISearch && deployAIServices) {
  name: 'search-ai-services-role'
  params: {
    principalId: aiSearch.?outputs.?searchPrincipalId ?? ''
    roleDefinitionId: 'a97b65f3-24c7-4388-baec-2e87135dc908' // Cognitive Services User
    principalType: 'ServicePrincipal'
  }
}

// Grant AI Services access to AI Search (for Foundry Agent to query search)
module aiServicesSearchRole 'modules/search-role-assignment.bicep' = if (deployAISearch && deployAIServices) {
  name: 'ai-services-search-role'
  params: {
    searchServiceName: aiSearch.outputs.searchServiceName
    principalId: aiServices.outputs.principalId
    roleDefinitionId: '7ca78c08-252a-4471-8644-bb5ff32d4ba0' // Search Service Contributor
    principalType: 'ServicePrincipal'
  }
}

// Grant Foundry Project access to AI Search (for Foundry Agent to query search)
module projectSearchRole 'modules/search-role-assignment.bicep' = if (deployAISearch && deployAIServices) {
  name: 'project-search-role'
  params: {
    searchServiceName: aiSearch.outputs.searchServiceName
    principalId: aiServices.outputs.projectPrincipalId
    roleDefinitionId: '7ca78c08-252a-4471-8644-bb5ff32d4ba0' // Search Service Contributor
    principalType: 'ServicePrincipal'
  }
}

// Grant deploying user access to Storage (for blob connection authorization)
module userStorageRole 'modules/storage-role-assignment.bicep' = if (!empty(deployingUserObjectId)) {
  name: 'user-storage-role'
  params: {
    storageAccountName: storage.outputs.storageAccountName
    principalId: deployingUserObjectId
    roleDefinitionId: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
    principalType: 'User'
  }
}

// ============================================================================
// Outputs
// ============================================================================

output storageAccountName string = storage.outputs.storageAccountName
output storageAccountId string = storage.outputs.storageAccountId
output storageBlobEndpoint string = storage.outputs.blobEndpoint

output aiSearchName string = aiSearch.?outputs.?searchServiceName ?? ''
output aiSearchEndpoint string = aiSearch.?outputs.?searchEndpoint ?? ''

output aiServicesName string = aiServices.?outputs.?aiServicesName ?? ''
output aiServicesEndpoint string = aiServices.?outputs.?aiServicesEndpoint ?? ''
output aiFoundryEndpoint string = aiServices.?outputs.?aiFoundryEndpoint ?? ''
output projectName string = aiServices.?outputs.?projectName ?? ''

output logicAppName string = logicApp.outputs.logicAppName
output sharePointConnectionName string = logicApp.outputs.sharePointConnectionName
output blobConnectionName string = logicApp.outputs.blobConnectionName

output postDeploymentSteps array = [
  '1. Authorize SharePoint connection in Azure Portal'
  '2. Authorize Blob connection in Azure Portal (or use managed identity)'
  '3. Enable the Logic App after connections are authorized'
  '4. Create AI Search index for contracts'
  '5. Create Foundry Agent with AI Search tool'
]
