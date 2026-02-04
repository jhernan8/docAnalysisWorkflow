// ============================================================================
// Azure AI Services Module (Foundry-compatible)
// Creates AI Services account with project for Azure AI Foundry
// ============================================================================

param location string
param aiServicesName string
param projectName string
param tags object

@allowed(['S0'])
param sku string = 'S0'

// AI Services Account (AIServices kind for Foundry)
resource aiServices 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: aiServicesName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: sku
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: aiServicesName
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false  // Allow key-based auth for development
    allowProjectManagement: true  // Required for creating projects
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// Foundry Project
resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  parent: aiServices
  name: projectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

// Model Deployments
// GPT-4.1 - Primary reasoning model
resource gpt41Deployment 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = {
  parent: aiServices
  name: 'gpt-4-1'
  sku: {
    name: 'GlobalStandard'
    capacity: 150
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4.1'
      version: '2025-04-14'
    }
    versionUpgradeOption: 'OnceCurrentVersionExpired'
    raiPolicyName: 'Microsoft.DefaultV2'
  }
  dependsOn: [project]
}

// GPT-4.1-mini - Cost-effective model
resource gpt41MiniDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = {
  parent: aiServices
  name: 'gpt-4-1-mini'
  sku: {
    name: 'GlobalStandard'
    capacity: 250
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4.1-mini'
      version: '2025-04-14'
    }
    versionUpgradeOption: 'OnceCurrentVersionExpired'
    raiPolicyName: 'Microsoft.DefaultV2'
  }
  dependsOn: [gpt41Deployment]
}

// Text Embedding 3 Large - Primary embedding model
resource embeddingLargeDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = {
  parent: aiServices
  name: 'text-embedding-3-large'
  sku: {
    name: 'GlobalStandard'
    capacity: 500
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'text-embedding-3-large'
      version: '1'
    }
    versionUpgradeOption: 'OnceCurrentVersionExpired'
  }
  dependsOn: [gpt41MiniDeployment]
}

// Text Embedding 3 Small - Lightweight embedding model
resource embeddingSmallDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = {
  parent: aiServices
  name: 'text-embedding-3-small'
  sku: {
    name: 'Standard'
    capacity: 120
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'text-embedding-3-small'
      version: '1'
    }
    versionUpgradeOption: 'OnceCurrentVersionExpired'
  }
  dependsOn: [embeddingLargeDeployment]
}

// Outputs
output aiServicesId string = aiServices.id
output aiServicesName string = aiServices.name
output aiServicesEndpoint string = aiServices.properties.endpoint
output aiFoundryEndpoint string = 'https://${aiServices.name}.services.ai.azure.com/'
output aiOpenAIEndpoint string = 'https://${aiServices.name}.openai.azure.com/'
output projectName string = project.name
output projectId string = project.id
output principalId string = aiServices.identity.principalId
output projectPrincipalId string = project.identity.principalId

// Model deployment names for reference
output modelDeployments object = {
  gpt41: gpt41Deployment.name
  gpt41Mini: gpt41MiniDeployment.name
  embeddingLarge: embeddingLargeDeployment.name
  embeddingSmall: embeddingSmallDeployment.name
}
