// ============================================================================
// Azure AI Services Module (Content Understanding)
// ============================================================================

param location string
param aiServicesName string
param tags object

@description('SKU for AI Services')
@allowed(['S0', 'F0'])
param sku string = 'S0'

// Azure AI Services (multi-service account that includes Content Understanding)
resource aiServices 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: aiServicesName
  location: location
  tags: tags
  kind: 'AIServices'  // Multi-service AI Services account
  sku: {
    name: sku
  }
  properties: {
    customSubDomainName: aiServicesName
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

output aiServicesId string = aiServices.id
output aiServicesName string = aiServices.name
output endpoint string = aiServices.properties.endpoint
output principalId string = aiServices.identity.principalId
