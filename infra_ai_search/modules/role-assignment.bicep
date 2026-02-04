// ============================================================================
// Role Assignment Module
// ============================================================================

param principalId string
param roleDefinitionId string

@allowed(['ServicePrincipal', 'User', 'Group', 'ForeignGroup'])
param principalType string = 'ServicePrincipal'

// Role assignment at resource group level
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, principalId, roleDefinitionId)
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalType: principalType
  }
}

output roleAssignmentId string = roleAssignment.id
