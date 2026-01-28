// ============================================================================
// Role Assignment Module
// Grants RBAC permissions to a principal on a specific resource
// ============================================================================

@description('Principal ID to grant the role to')
param principalId string

@description('Role Definition ID (GUID of the built-in role)')
param roleDefinitionId string

@description('Principal type')
@allowed(['ServicePrincipal', 'User', 'Group'])
param principalType string = 'ServicePrincipal'

@description('Resource ID to scope the role assignment to')
param resourceId string

// Built-in Role IDs for reference:
// - Cognitive Services User: a97b65f3-24c7-4388-baec-2e87135dc908
// - Storage Blob Data Contributor: ba92f5b4-2d11-453d-a403-e96b0029c9fe
// - Storage Blob Data Reader: 2a2b9908-6ea1-4ae2-8e65-a410df84e7d1
// - SQL DB Contributor: 9b7fa17d-e63e-47b0-bb0a-15c516ac86ec

var roleAssignmentName = guid(resourceId, principalId, roleDefinitionId)

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: roleAssignmentName
  scope: resourceGroup()
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalType: principalType
  }
}

output roleAssignmentId string = roleAssignment.id
