// ============================================================================
// Private DNS Zone VNet Link Module
// Links a VNet to an existing Private DNS Zone (idempotent)
// ============================================================================

@description('Name of the existing Private DNS Zone')
param dnsZoneName string

@description('Resource ID of the VNet to link')
param vnetId string

@description('Name for the VNet link')
param linkName string

resource dnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: dnsZoneName
}

resource vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: dnsZone
  name: linkName
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

output linkId string = vnetLink.id
