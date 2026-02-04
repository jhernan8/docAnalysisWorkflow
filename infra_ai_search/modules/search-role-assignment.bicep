// ============================================================================
// AI Search Scoped Role Assignment Module
// ============================================================================

param searchServiceName string
param principalId string
param roleDefinitionId string

@allowed(['ServicePrincipal', 'User', 'Group', 'ForeignGroup'])
param principalType string = 'ServicePrincipal'

// Reference existing search service
resource searchService 'Microsoft.Search/searchServices@2024-03-01-preview' existing = {
  name: searchServiceName
}

// Role assignment scoped to search service
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, principalId, roleDefinitionId)
  scope: searchService
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalType: principalType
  }
}

output roleAssignmentId string = roleAssignment.id
