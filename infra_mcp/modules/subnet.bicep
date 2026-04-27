// ============================================================================
// Subnet Module — Creates a single delegated subnet for Container Apps
// ============================================================================

@description('Name of the existing VNet')
param vnetName string

@description('Name for the new subnet')
param subnetName string

@description('Address prefix (min /23 for Container Apps)')
param addressPrefix string

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' existing = {
  name: vnetName
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' = {
  parent: vnet
  name: subnetName
  properties: {
    addressPrefix: addressPrefix
    delegations: [
      {
        name: 'delegation-containerapp'
        properties: {
          serviceName: 'Microsoft.App/environments'
        }
      }
    ]
  }
}

output subnetId string = subnet.id
output vnetId string = vnet.id
