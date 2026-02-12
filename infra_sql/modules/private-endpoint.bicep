// ============================================================================
// Private Endpoint Module (Reusable)
// Creates a private endpoint and registers it with a Private DNS Zone
// ============================================================================

@description('Name of the private endpoint')
param name string

@description('Azure region')
param location string

@description('Resource ID of the subnet to place the private endpoint in')
param subnetId string

@description('Resource ID of the target resource')
param privateLinkServiceId string

@description('Group IDs for the private link service connection (e.g., blob, sqlServer, sites)')
param groupIds array

@description('Resource ID of the Private DNS Zone for automatic DNS registration')
param privateDnsZoneId string

@description('Tags')
param tags object = {}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${name}-conn'
        properties: {
          privateLinkServiceId: privateLinkServiceId
          groupIds: groupIds
        }
      }
    ]
  }
}

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: replace(last(split(privateDnsZoneId, '/')), '.', '-')
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

output privateEndpointId string = privateEndpoint.id
output privateEndpointName string = privateEndpoint.name
