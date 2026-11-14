targetScope = 'resourceGroup'

param virtualNetworkName string
param location string
param tags object = {}

@description('VNet CIDR. Keep the private endpoint subnet inside this range.')
param virtualNetworkAddressPrefix string = '10.40.0.0/16'

param privateEndpointSubnetAddressPrefix string = '10.40.1.0/24'

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: virtualNetworkName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        virtualNetworkAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'private-endpoints'
        properties: {
          addressPrefix: privateEndpointSubnetAddressPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

output virtualNetworkId string = virtualNetwork.id
output privateEndpointSubnetId string = resourceId(
  'Microsoft.Network/virtualNetworks/subnets',
  virtualNetwork.name,
  'private-endpoints'
)
