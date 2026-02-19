// ============================================================================
// Function App Module - Elastic Premium Plan (EP1)
// Uses Managed Identity for Storage and SQL connections
// ============================================================================

param location string
param functionAppName string
param appServicePlanName string
param storageAccountName string
param appInsightsConnectionString string
param sqlServerName string
param sqlDatabaseName string
param tags object

@description('Subnet ID for VNet integration (outbound). Leave empty to skip VNet integration.')
param virtualNetworkSubnetId string = ''

@description('Public network access setting')
param publicNetworkAccess string = 'Enabled'

// Reference existing storage account to retrieve connection string
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

var storageConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

// Elastic Premium Plan - supports VNet integration with Microsoft.Web/serverFarms delegation
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: 'EP1'
    tier: 'ElasticPremium'
    family: 'EP'
  }
  kind: 'elastic'
  properties: {
    reserved: true // Required for Linux
    maximumElasticWorkerCount: 20
  }
}

// Function App on Elastic Premium
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    reserved: true
    httpsOnly: true
    publicNetworkAccess: publicNetworkAccess
    virtualNetworkSubnetId: !empty(virtualNetworkSubnetId) ? virtualNetworkSubnetId : null
    vnetRouteAllEnabled: !empty(virtualNetworkSubnetId)
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.12'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: [
        // ============================================
        // Storage - Connection string with account key (required for EP1)
        // ============================================
        {
          name: 'AzureWebJobsStorage'
          value: storageConnectionString
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: storageConnectionString
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        // ============================================
        // Function Runtime
        // ============================================
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        // ============================================
        // Monitoring
        // ============================================
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        // ============================================
        // Content Understanding (set manually after AI Foundry creation)
        // ============================================
        {
          name: 'CONTENT_UNDERSTANDING_ENDPOINT'
          value: 'PLACEHOLDER_SET_AFTER_FOUNDRY_CREATION'
        }
        {
          name: 'CONTENT_UNDERSTANDING_ANALYZER_ID'
          value: 'PLACEHOLDER_SET_AFTER_FOUNDRY_CREATION'
        }
        {
          name: 'CONTENT_UNDERSTANDING_API_VERSION'
          value: '2025-11-01'
        }
        // ============================================
        // SQL configuration
        // ============================================
        {
          name: 'SQL_SERVER'
          value: sqlServerName
        }
        {
          name: 'SQL_DATABASE'
          value: sqlDatabaseName
        }
      ]
    }
  }
}

output functionAppId string = functionApp.id
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output functionAppPrincipalId string = functionApp.identity.principalId
