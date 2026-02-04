// ============================================================================
// Azure AI Search Module
// ============================================================================

param location string
param searchServiceName string
param tags object

@allowed(['free', 'basic', 'standard', 'standard2', 'standard3'])
param sku string = 'basic'

@description('Number of replicas (1-12 for standard, 1-3 for basic)')
param replicaCount int = 1

@description('Number of partitions (1, 2, 3, 4, 6, or 12 for standard)')
param partitionCount int = 1

// AI Search Service
resource searchService 'Microsoft.Search/searchServices@2024-03-01-preview' = {
  name: searchServiceName
  location: location
  tags: tags
  sku: {
    name: sku
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    replicaCount: replicaCount
    partitionCount: partitionCount
    hostingMode: 'default'
    publicNetworkAccess: 'enabled'
    semanticSearch: 'free'  // Enable semantic search (free tier)
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
  }
}

// Outputs
output searchServiceId string = searchService.id
output searchServiceName string = searchService.name
output searchEndpoint string = 'https://${searchService.name}.search.windows.net'
output searchPrincipalId string = searchService.identity.principalId
