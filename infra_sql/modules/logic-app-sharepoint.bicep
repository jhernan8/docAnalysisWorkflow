// ============================================================================
// Logic App Module - SharePoint Trigger to Function App
// Triggers when a file is created in SharePoint, sends to Function App
// Note: Function key is set post-deployment via deploy.sh
// ============================================================================

param location string
param logicAppName string
param functionAppHostname string

@description('SharePoint site URL (e.g., https://contoso.sharepoint.com/sites/ContractAI)')
param sharePointSiteUrl string

@description('SharePoint document library ID (GUID of the library)')
param sharePointLibraryId string

param tags object

// API Connection for SharePoint Online
// Note: This creates the connection resource, but OAuth consent must be done in Portal
resource sharePointConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: '${logicAppName}-sharepoint-connection'
  location: location
  tags: tags
  properties: {
    displayName: 'SharePoint Connection for Contract Analysis'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'sharepointonline')
    }
    // SharePoint connections require interactive OAuth consent after deployment
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
    state: 'Disabled' // Start disabled - enable after authorizing SharePoint connection
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
        When_a_file_is_created_properties_only: {
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
        Get_file_content: {
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
        Call_Function_App: {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: 'https://${functionAppHostname}/api/analyze-and-store'
            headers: {
              'x-functions-key': 'PLACEHOLDER_UPDATE_VIA_SCRIPT'
            }
            body: {
              filename: '@{triggerBody()?[\'{Name}\']}'
              content: '@{base64(body(\'Get_file_content\'))}'
            }
          }
          runAfter: {
            Get_file_content: ['Succeeded']
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
        }
      }
    }
  }
}

output logicAppId string = logicApp.id
output logicAppName string = logicApp.name
output logicAppPrincipalId string = logicApp.identity.principalId
output sharePointConnectionId string = sharePointConnection.id
output sharePointConnectionName string = sharePointConnection.name
