// ============================================================================
// Logic App Standard Module - SharePoint Trigger to Function App
// Standard tier supports VNet integration and private endpoints
// Workflow definition is deployed via deploy script after resource creation
// ============================================================================

param location string
param logicAppName string
param functionAppHostname string

@description('SharePoint site URL (e.g., https://contoso.sharepoint.com/sites/ContractAI)')
param sharePointSiteUrl string

@description('SharePoint document library ID (GUID of the library)')
param sharePointLibraryId string

@description('Name of the storage account for Logic App state')
param storageAccountName string

@description('Application Insights connection string')
param appInsightsConnectionString string

@description('Subnet ID for VNet integration (outbound). Leave empty to skip.')
param virtualNetworkSubnetId string = ''

@description('Public network access setting')
param publicNetworkAccess string = 'Enabled'

param tags object

// App Service Plan for Logic App Standard (WS1 = Workflow Standard 1)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${logicAppName}-asp'
  location: location
  tags: tags
  sku: {
    name: 'WS1'
    tier: 'WorkflowStandard'
  }
  kind: 'elastic'
  properties: {
    reserved: true // Linux
  }
}

// API Connection for SharePoint Online
// Note: OAuth consent must be done in Azure Portal after deployment
// Access policy is created via az rest in deploy.ps1 (stable API, not supported in Bicep with 2016-06-01)
resource sharePointConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: '${logicAppName}-sharepoint-connection'
  location: location
  tags: tags
  properties: {
    displayName: 'SharePoint Connection for Contract Analysis'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'sharepointonline')
    }
  }
}

// Logic App Standard
resource logicApp 'Microsoft.Web/sites@2023-12-01' = {
  name: logicAppName
  location: location
  tags: union(tags, { 'hidden-link: /app-insights-resource-id': appInsightsConnectionString })
  kind: 'functionapp,linux,workflowapp'
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
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      use32BitWorkerProcess: false
      netFrameworkVersion: 'v6.0'
      appSettings: [
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storageAccountName
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~18'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name: 'APP_KIND'
          value: 'workflowapp'
        }
        {
          name: 'AzureFunctionsJobHost__extensionBundle__id'
          value: 'Microsoft.Azure.Functions.ExtensionBundle.Workflows'
        }
        {
          name: 'AzureFunctionsJobHost__extensionBundle__version'
          value: '[1.*, 2.0.0)'
        }
        // Workflow-specific settings passed as app settings for the workflow definition
        {
          name: 'SHAREPOINT_SITE_URL'
          value: sharePointSiteUrl
        }
        {
          name: 'SHAREPOINT_LIBRARY_ID'
          value: sharePointLibraryId
        }
        {
          name: 'FUNCTION_APP_HOSTNAME'
          value: functionAppHostname
        }
        {
          name: 'WORKFLOWS_SUBSCRIPTION_ID'
          value: subscription().subscriptionId
        }
        {
          name: 'WORKFLOWS_RESOURCE_GROUP_NAME'
          value: resourceGroup().name
        }
        {
          name: 'WORKFLOWS_LOCATION_NAME'
          value: location
        }
      ]
    }
  }
}

output logicAppId string = logicApp.id
output logicAppName string = logicApp.name
output logicAppPrincipalId string = logicApp.identity.principalId
output logicAppHostname string = logicApp.properties.defaultHostName
output appServicePlanId string = appServicePlan.id
output sharePointConnectionId string = sharePointConnection.id
output sharePointConnectionName string = sharePointConnection.name
