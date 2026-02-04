// ============================================================================
// Logic App Module - SharePoint to Blob Storage
// Triggers on new files in SharePoint, copies to Azure Blob Storage
// ============================================================================

param location string
param logicAppName string
param storageAccountName string
param sharePointSiteUrl string
param sharePointLibraryId string
param tags object

// API Connection for SharePoint Online
// Note: Requires manual authorization after deployment
resource sharePointConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: '${logicAppName}-sharepoint'
  location: location
  tags: tags
  properties: {
    displayName: 'SharePoint Connection'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'sharepointonline')
    }
    // OAuth connections require manual authorization
    // The connection will be created but in "Unauthenticated" state
  }
}

// API Connection for Azure Blob Storage (using managed identity)
resource blobConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: '${logicAppName}-blob'
  location: location
  tags: tags
  properties: {
    displayName: 'Azure Blob Storage Connection'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureblob')
    }
    #disable-next-line BCP037 BCP089
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
    state: 'Disabled' // Start disabled until connections are authorized
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
        When_a_file_is_created_in_SharePoint: {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'sharepointonline\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/datasets/@{encodeURIComponent(encodeURIComponent(\'${sharePointSiteUrl}\'))}/tables/@{encodeURIComponent(encodeURIComponent(\'${sharePointLibraryId}\'))}/onnewfileitems'
          }
          recurrence: {
            frequency: 'Minute'
            interval: 1
          }
          splitOn: '@triggerBody()?[\'value\']'
        }
      }
      actions: {
        Get_file_content_from_SharePoint: {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'sharepointonline\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/datasets/@{encodeURIComponent(encodeURIComponent(\'${sharePointSiteUrl}\'))}/files/@{encodeURIComponent(triggerBody()?[\'{Identifier}\'])}/content'
            queries: {
              inferContentType: true
            }
          }
          runAfter: {}
        }
        Create_blob_in_contracts_container: {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureblob\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${storageAccountName}\'))}/files'
            queries: {
              folderPath: '/contracts'
              name: '@triggerBody()?[\'{FilenameWithExtension}\']'
              queryParametersSingleEncoded: true
            }
            body: '@body(\'Get_file_content_from_SharePoint\')'
            headers: {
              ReadFileMetadataFromServer: true
            }
          }
          runAfter: {
            Get_file_content_from_SharePoint: ['Succeeded']
          }
          runtimeConfiguration: {
            contentTransfer: {
              transferMode: 'Chunked'
            }
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          sharepointonline: {
            connectionId: sharePointConnection.id
            connectionName: sharePointConnection.name
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'sharepointonline')
          }
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

// Outputs
output logicAppId string = logicApp.id
output logicAppName string = logicApp.name
output logicAppPrincipalId string = logicApp.identity.principalId
output sharePointConnectionId string = sharePointConnection.id
output sharePointConnectionName string = sharePointConnection.name
output blobConnectionId string = blobConnection.id
output blobConnectionName string = blobConnection.name
