// ============================================================================
// Function App Module - Flex Consumption Plan
// Uses Managed Identity for Storage connection (fully supported on Flex)
// ============================================================================

param location string
param functionAppName string
param appServicePlanName string
param storageAccountName string
param appInsightsConnectionString string
param sqlServerName string
param sqlDatabaseName string
param tags object

// Flex Consumption Plan (supports managed identity for storage)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  kind: 'functionapp'
  properties: {
    reserved: true // Required for Linux
  }
}

// Function App on Flex Consumption
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
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: 'https://${storageAccountName}.blob.${environment().suffixes.storage}/deployments'
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 100
        instanceMemoryMB: 2048
      }
      runtime: {
        name: 'python'
        version: '3.12'
      }
    }
    siteConfig: {
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: [
        // ============================================
        // Storage - Using Managed Identity (Flex supports this!)
        // ============================================
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storageAccountName
        }
        // ============================================
        // Function Runtime
        // ============================================
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
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
