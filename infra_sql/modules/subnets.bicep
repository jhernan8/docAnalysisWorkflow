// ============================================================================
// Subnets Module
// Creates private endpoint, Function App, and Logic App integration subnets
// on an existing VNet
// ============================================================================

@description('Name of the existing VNet')
param vnetName string

@description('Address prefix for the private endpoint subnet')
param privateEndpointSubnetAddressPrefix string

@description('Address prefix for the VNet integration subnet (Function App outbound)')
param vnetIntegrationSubnetAddressPrefix string

@description('Address prefix for the Logic App VNet integration subnet (outbound)')
param logicAppSubnetAddressPrefix string

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' existing = {
  name: vnetName
}

// Subnet for private endpoints
resource peSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' = {
  parent: vnet
  name: 'snet-private-endpoints'
  properties: {
    addressPrefix: privateEndpointSubnetAddressPrefix
    privateEndpointNetworkPolicies: 'Enabled'
  }
}

// Subnet for Function App VNet integration (outbound)
// Must be delegated to Microsoft.Web/serverFarms
resource funcSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' = {
  parent: vnet
  name: 'snet-func-integration'
  dependsOn: [peSubnet] // Serialize subnet operations on the same VNet
  properties: {
    addressPrefix: vnetIntegrationSubnetAddressPrefix
    delegations: [
      {
        name: 'delegation-web'
        properties: {
          serviceName: 'Microsoft.Web/serverFarms'
        }
      }
    ]
  }
}

// Subnet for Logic App Standard VNet integration (outbound)
// Needs its own delegated subnet — cannot share with Function App
resource logicAppSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' = {
  parent: vnet
  name: 'snet-logic-integration'
  dependsOn: [funcSubnet] // Serialize subnet operations on the same VNet
  properties: {
    addressPrefix: logicAppSubnetAddressPrefix
    delegations: [
      {
        name: 'delegation-web'
        properties: {
          serviceName: 'Microsoft.Web/serverFarms'
        }
      }
    ]
  }
}

output peSubnetId string = peSubnet.id
output funcIntegrationSubnetId string = funcSubnet.id
output logicAppSubnetId string = logicAppSubnet.id
