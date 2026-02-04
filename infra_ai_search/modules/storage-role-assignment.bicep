// ============================================================================
// Storage Account Scoped Role Assignment Module
// ============================================================================

param storageAccountName string
param principalId string
param roleDefinitionId string

@allowed(['ServicePrincipal', 'User', 'Group', 'ForeignGroup'])
param principalType string = 'ServicePrincipal'

// Reference existing storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

// Role assignment scoped to storage account
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, principalId, roleDefinitionId)
  scope: storageAccount
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalType: principalType
  }
}

output roleAssignmentId string = roleAssignment.id
