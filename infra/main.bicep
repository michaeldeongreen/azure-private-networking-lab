targetScope = 'resourceGroup'

@description('Application label: one to three lowercase letters or digits.')
@minLength(1)
@maxLength(3)
param appName string

@description('Environment label.')
@allowed([
  'dev'
  'test'
])
param environmentName string

@description('Region for regional lab resources. The eus name suffix corresponds to eastus.')
@allowed([
  'eastus'
])
param location string

var tags = {
  application: appName
  environment: environmentName
  project: 'azure-private-networking-lab'
}

var suffix = uniqueString(resourceGroup().id, environmentName)
var vaultName = environmentName == 'dev'
  ? 'kv-${appName}-dev-eus-${substring(suffix, 0, 9)}'
  : 'kv-${appName}-test-eus-${substring(suffix, 0, 8)}'

module network './modules/network.bicep' = {
  name: 'network-${environmentName}'
  params: {
    virtualNetworkName: 'vnet-${appName}-${environmentName}-eus-${suffix}'
    location: location
    tags: tags
  }
}

module keyVault './modules/key-vault.bicep' = {
  name: 'key-vault-${environmentName}'
  params: {
    keyVaultName: vaultName
    location: location
    virtualNetworkId: network.outputs.virtualNetworkId
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    tags: tags
  }
}

var workspaceName = 'law-${appName}-${environmentName}-eus-${suffix}'
var applicationInsightsName = 'appi-${appName}-${environmentName}-eus-${suffix}'
var containerRegistryName = 'cr${appName}${environmentName}eus${suffix}'

module logAnalytics './modules/log-analytics.bicep' = {
  name: 'log-analytics-${environmentName}'
  params: {
    workspaceName: workspaceName
    location: location
    tags: tags
  }
}

module applicationInsights './modules/application-insights.bicep' = {
  name: 'application-insights-${environmentName}'
  params: {
    componentName: applicationInsightsName
    location: location
    workspaceId: logAnalytics.outputs.workspaceId
    tags: tags
  }
}

module containerRegistry './modules/container-registry.bicep' = {
  name: 'container-registry-${environmentName}'
  params: {
    registryName: containerRegistryName
    location: location
    tags: tags
  }
}

output resourceGroupName string = resourceGroup().name
output resourceGroupId string = resourceGroup().id
output keyVaultName string = keyVault.outputs.keyVaultName
output keyVaultId string = keyVault.outputs.keyVaultId
output keyVaultUri string = keyVault.outputs.keyVaultUri
output virtualNetworkId string = network.outputs.virtualNetworkId
output privateEndpointSubnetId string = network.outputs.privateEndpointSubnetId
output privateEndpointId string = keyVault.outputs.privateEndpointId
output privateDnsZoneName string = keyVault.outputs.privateDnsZoneName
output logAnalyticsWorkspaceName string = logAnalytics.outputs.workspaceName
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
output applicationInsightsName string = applicationInsights.outputs.componentName
output applicationInsightsId string = applicationInsights.outputs.componentId
output containerRegistryName string = containerRegistry.outputs.registryName
output containerRegistryId string = containerRegistry.outputs.registryId
