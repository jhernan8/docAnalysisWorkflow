// ============================================================================
// Logic App Module - Blob Trigger to Function App
// ============================================================================

param location string
param logicAppName string
param storageAccountName string
param storageAccountId string
param functionAppName string
param functionAppId string
param tags object

// Reference existing storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

// Reference existing function app
resource functionApp 'Microsoft.Web/sites@2023-01-01' existing = {
  name: functionAppName
}

// API Connection for Azure Blob Storage (using managed identity)
resource blobConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: '${logicAppName}-blob-connection'
  location: location
  tags: tags
  properties: {
    displayName: 'Azure Blob Storage Connection'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureblob')
    }
    parameterValueSet: {
      name: 'managedIdentityAuth'
      values: {}
    }
  }
}

// Logic App
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Disabled' // Start disabled, enable after authorizing connections
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        'When_a_blob_is_added_or_modified': {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureblob\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${storageAccountName}\'))}/triggers/batch/onupdatedfile'
            queries: {
              folderId: 'JTJmY29udHJhY3Rz' // Base64 encoded '/contracts'
              maxFileCount: 10
            }
          }
          recurrence: {
            frequency: 'Minute'
            interval: 1
          }
          splitOn: '@triggerBody()'
          metadata: {
            'JTJmY29udHJhY3Rz': '/contracts'
          }
        }
      }
      actions: {
        'Get_blob_content': {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureblob\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${storageAccountName}\'))}/files/@{encodeURIComponent(triggerBody()?[\'Id\'])}/content'
          }
          runAfter: {}
        }
        'Call_Function_App': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: 'https://${functionApp.properties.defaultHostName}/api/analyze-and-store'
            headers: {
              'Content-Type': 'application/json'
            }
            body: {
              filename: '@{triggerBody()?[\'Name\']}'
              content: '@{base64(body(\'Get_blob_content\'))}'
            }
            authentication: {
              type: 'ManagedServiceIdentity'
              audience: 'https://management.azure.com'
            }
          }
          runAfter: {
            'Get_blob_content': ['Succeeded']
          }
        }
        'Move_to_processed': {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureblob\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${storageAccountName}\'))}/copyFile'
            queries: {
              source: '@triggerBody()?[\'Path\']'
              destination: '/processed/@{triggerBody()?[\'Name\']}'
              overwrite: true
            }
          }
          runAfter: {
            'Call_Function_App': ['Succeeded']
          }
        }
        'Delete_original': {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureblob\'][\'connectionId\']'
              }
            }
            method: 'delete'
            path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${storageAccountName}\'))}/files/@{encodeURIComponent(triggerBody()?[\'Id\'])}'
          }
          runAfter: {
            'Move_to_processed': ['Succeeded']
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          azureblob: {
            connectionId: blobConnection.id
            connectionName: blobConnection.name
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureblob')
          }
        }
      }
    }
  }
}

output logicAppId string = logicApp.id
output logicAppName string = logicApp.name
output logicAppPrincipalId string = logicApp.identity.principalId
output blobConnectionId string = blobConnection.id
