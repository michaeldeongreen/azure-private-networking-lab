using './main.bicep'

param appName = readEnvironmentVariable('LAB_APP_NAME')
param environmentName = readEnvironmentVariable('INFRA_ENVIRONMENT')
param location = 'eastus'
