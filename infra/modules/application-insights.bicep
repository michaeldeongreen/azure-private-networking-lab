targetScope = 'resourceGroup'

param componentName string
param location string
param workspaceId string
param tags object = {}

resource component 'Microsoft.Insights/components@2020-02-02' = {
  name: componentName
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspaceId
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: 'Disabled'
  }
}

output componentName string = component.name
output componentId string = component.id
