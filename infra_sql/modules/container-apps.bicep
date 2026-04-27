// ============================================================================
// Container Apps Module - DAB MCP Server
// Deploys a VNet-integrated Container Apps environment + app with
// system-assigned managed identity for Azure AD SQL auth
// ============================================================================

@description('Azure region')
param location string

@description('Name for the Container Apps environment')
param containerAppEnvName string

@description('Name for the Container App')
param containerAppName string

@description('Resource ID of the subnet for the Container Apps environment (min /23)')
param infrastructureSubnetId string

@description('ACR login server (e.g., myacr.azurecr.io)')
param acrLoginServer string

@description('ACR image name with tag (e.g., contracts-mcp-server:1)')
param acrImageName string

@description('ACR admin username')
@secure()
param acrUsername string

@description('ACR admin password')
@secure()
param acrPassword string

@description('SQL Server FQDN (e.g., myserver.database.windows.net)')
param sqlServerFqdn string

@description('SQL Database name')
param sqlDatabaseName string

@description('Tags')
param tags object = {}

// ============================================================================
// Container Apps Environment (VNet-integrated)
// ============================================================================

resource containerAppEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppEnvName
  location: location
  tags: tags
  properties: {
    vnetConfiguration: {
      infrastructureSubnetId: infrastructureSubnetId
      internal: false
    }
    zoneRedundant: false
  }
}

// ============================================================================
// Container App (DAB MCP Server)
// ============================================================================

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 5000
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: acrLoginServer
          username: acrUsername
          passwordSecretRef: 'acr-password'
        }
      ]
      secrets: [
        {
          name: 'acr-password'
          value: acrPassword
        }
        {
          name: 'mssql-connection-string'
          value: 'Server=tcp:${sqlServerFqdn},1433;Database=${sqlDatabaseName};Authentication=Active Directory Managed Identity;Encrypt=true;TrustServerCertificate=false;Connection Timeout=30;'
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'dab-mcp-server'
          image: '${acrLoginServer}/${acrImageName}'
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'MSSQL_CONNECTION_STRING'
              secretRef: 'mssql-connection-string'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
    }
  }
}

// ============================================================================
// Outputs
// ============================================================================

output containerAppId string = containerApp.id
output containerAppName string = containerApp.name
output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
output containerAppPrincipalId string = containerApp.identity.principalId
output mcpEndpointUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}/mcp'
output healthEndpointUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}/health'
