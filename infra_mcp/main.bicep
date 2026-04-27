// ============================================================================
// DAB MCP Server - Additive Deployment
// Deploys a VNet-integrated Container Apps environment + DAB MCP Server
// that connects to the existing Contract Analysis SQL Database
//
// This is a standalone deployment — it does NOT modify any existing
// infra_sql resources. It references them by name.
// ============================================================================

targetScope = 'resourceGroup'

// ============================================================================
// Parameters — Existing Infrastructure References
// ============================================================================

@description('Name of the existing SQL Server (e.g., contracts-dev-sql-a1b2c3d4)')
param sqlServerName string

@description('Name of the existing SQL Database')
param sqlDatabaseName string = 'contractsdb'

@description('Name of the existing VNet')
param vnetName string

@description('Resource group containing the existing VNet')
param vnetResourceGroupName string

@description('Subscription ID where Private DNS Zones are deployed')
param dnsZoneSubscriptionId string

@description('Resource group containing the Private DNS Zones')
param dnsZoneResourceGroupName string

// ============================================================================
// Parameters — New Resources
// ============================================================================

@description('Azure region for the Container Apps environment')
param location string = resourceGroup().location

@description('Address prefix for the Container Apps subnet (min /23)')
param containerAppSubnetAddressPrefix string

@description('Name of the ACR that holds the DAB MCP image')
param acrName string

@description('ACR image name with tag')
param acrImageName string = 'contracts-mcp-server:1'

@description('Tags')
param tags object = {
  solution: 'contract-analysis'
  component: 'mcp-server'
  deployedBy: 'bicep'
}

// ============================================================================
// Variables
// ============================================================================

var containerAppEnvName = 'contracts-mcp-env'
var containerAppName = 'contracts-mcp-server'
var subnetName = 'snet-containerapp'

// Reference the existing SQL Server to get its FQDN
resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' existing = {
  name: sqlServerName
}

// Reference the existing ACR to get login server + credentials
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

// Private DNS Zone ID for SQL (cross-subscription)
var sqlDnsZoneId = '/subscriptions/${dnsZoneSubscriptionId}/resourceGroups/${dnsZoneResourceGroupName}/providers/Microsoft.Network/privateDnsZones/privatelink${az.environment().suffixes.sqlServerHostname}'

// ============================================================================
// Subnet on existing VNet
// ============================================================================

module subnet 'modules/subnet.bicep' = {
  name: 'mcp-subnet-deployment'
  scope: resourceGroup(vnetResourceGroupName)
  params: {
    vnetName: vnetName
    subnetName: subnetName
    addressPrefix: containerAppSubnetAddressPrefix
  }
}

// ============================================================================
// Container Apps Environment (VNet-integrated)
// ============================================================================

resource containerAppEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppEnvName
  location: location
  tags: tags
  properties: {
    vnetConfiguration: {
      infrastructureSubnetId: subnet.outputs.subnetId
      internal: false
    }
    zoneRedundant: false
  }
}

// ============================================================================
// Container App — DAB MCP Server
// ============================================================================

var acrLoginServer = acr.properties.loginServer
var acrCreds = acr.listCredentials()

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
          username: acrCreds.username
          passwordSecretRef: 'acr-password'
        }
      ]
      secrets: [
        {
          name: 'acr-password'
          value: acrCreds.passwords[0].value
        }
        {
          name: 'mssql-connection-string'
          value: 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Database=${sqlDatabaseName};Authentication=Active Directory Managed Identity;Encrypt=true;TrustServerCertificate=false;Connection Timeout=30;'
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
// Private DNS Zone VNet Link (so Container App can resolve SQL private endpoint)
// ============================================================================

module dnsLink 'modules/dns-zone-link.bicep' = {
  name: 'mcp-dns-link-deployment'
  scope: resourceGroup(dnsZoneSubscriptionId, dnsZoneResourceGroupName)
  params: {
    dnsZoneName: 'privatelink${az.environment().suffixes.sqlServerHostname}'
    vnetId: subnet.outputs.vnetId
    linkName: 'vnetlink-containerapp-sql'
  }
}

// ============================================================================
// Outputs
// ============================================================================

output containerAppName string = containerApp.name
output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
output mcpEndpointUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}/mcp'
output healthEndpointUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}/health'
output containerAppPrincipalId string = containerApp.identity.principalId

output postDeploymentSteps string = '''
================================================================================
POST-DEPLOYMENT STEPS:
================================================================================

1. GRANT SQL ACCESS to the MCP Server managed identity:
   Connect to the SQL database as the Azure AD admin and run:

   CREATE USER [contracts-mcp-server] FROM EXTERNAL PROVIDER;
   ALTER ROLE db_datareader ADD MEMBER [contracts-mcp-server];

2. VERIFY HEALTH:
   curl https://<containerAppFqdn>/health

3. CONNECT FROM FOUNDRY AGENT (Portal — no code):
   a. Go to https://ai.azure.com → select your project → Playground
   b. Create or open an agent → Tools → Add → Custom → MCP
   c. Name: contracts-mcp
   d. Remote MCP Server endpoint: https://<containerAppFqdn>/mcp
   e. Authentication: Unauthenticated
   f. Require approval: never

4. OR CONNECT VIA PYTHON SDK:
   mcp_connection = McpToolConnection(
       server_label="contracts-mcp",
       server_url="https://<containerAppFqdn>/mcp",
       server_type="sse"
   )
   agent = client.agents.create_agent(
       model="gpt-4o", name="contract-analyst",
       tool_resources=ToolConnectionList(mcp_tool_connections=[mcp_connection])
   )

5. OR CONNECT FROM VS CODE (.vscode/mcp.json):
   { "mcpServers": { "contracts-mcp": { "type": "sse", "url": "https://<containerAppFqdn>/mcp" } } }
================================================================================
'''
