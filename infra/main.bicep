targetScope = 'resourceGroup'

@description('Short lowercase deployment name, for example stmsprod.')
@minLength(3)
@maxLength(15)
param namePrefix string = 'stmsprod'

@description('Azure region for data and compute resources.')
param location string = resourceGroup().location

@description('Container image. The first deployment may use the public placeholder.')
param apiImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@allowed(['development', 'production'])
param environment string = 'production'

param azureOpenAIEndpoint string = ''
param azureOpenAIDeployment string = 'gpt-4o'
param azureFaceEndpoint string = ''

@secure()
param dataFlagApiKey string = ''

var unique = uniqueString(subscription().id, resourceGroup().id, namePrefix)
var storageName = take(toLower(replace('${namePrefix}${unique}', '-', '')), 24)
var registryName = take(toLower(replace('${namePrefix}${unique}acr', '-', '')), 50)
var blobContributorRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
var acrPullRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
var commonTags = {
  application: 'stms'
  environment: environment
  managedBy: 'bicep'
}

resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${namePrefix}-logs'
  location: location
  tags: commonTags
  properties: {
    retentionInDays: 30
    features: { enableLogAccessUsingOnlyResourcePermissions: true }
  }
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  #disable-next-line BCP334
  name: registryName
  location: location
  tags: commonTags
  sku: { name: 'Basic' }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  #disable-next-line BCP334
  name: storageName
  location: location
  tags: commonTags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {
    deleteRetentionPolicy: { enabled: true, days: 14 }
    containerDeleteRetentionPolicy: { enabled: true, days: 14 }
  }
}

resource rawVideos 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'raw-video'
  properties: { publicAccess: 'None' }
}

resource evidence 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'evidence'
  properties: { publicAccess: 'None' }
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: '${namePrefix}-cosmos-${take(unique, 5)}'
  location: location
  tags: commonTags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: { defaultConsistencyLevel: 'Session' }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true
    capabilities: [
      { name: 'EnableServerless' }
    ]
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmos
  name: 'stms'
  properties: { resource: { id: 'stms' } }
}

resource operational 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: database
  name: 'operational'
  properties: {
    resource: {
      id: 'operational'
      partitionKey: {
        paths: ['/camera']
        kind: 'Hash'
      }
    }
  }
}

resource containerEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: '${namePrefix}-cae'
  location: location
  tags: commonTags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logs.properties.customerId
        sharedKey: logs.listKeys().primarySharedKey
      }
    }
  }
}

resource api 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${namePrefix}-api'
  location: location
  tags: commonTags
  identity: { type: 'SystemAssigned' }
  properties: {
    managedEnvironmentId: containerEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      secrets: empty(dataFlagApiKey) ? [] : [
        {
          name: 'dataflag-api-key'
          value: dataFlagApiKey
        }
      ]
      registries: [
        {
          server: registry.properties.loginServer
          identity: 'system'
        }
      ]
      ingress: {
        external: true
        targetPort: 8000
        transport: 'auto'
        allowInsecure: false
      }
    }
    template: {
      containers: [
        {
          name: 'api'
          image: apiImage
          env: concat([
            { name: 'ENVIRONMENT', value: environment }
            { name: 'DEMO_PROCESSOR', value: 'false' }
            { name: 'STORAGE_ACCOUNT_URL', value: storage.properties.primaryEndpoints.blob }
            { name: 'COSMOS_ENDPOINT', value: cosmos.properties.documentEndpoint }
            { name: 'COSMOS_DATABASE', value: database.name }
            { name: 'AZURE_OPENAI_ENDPOINT', value: azureOpenAIEndpoint }
            { name: 'AZURE_OPENAI_DEPLOYMENT', value: azureOpenAIDeployment }
            { name: 'AZURE_FACE_ENDPOINT', value: azureFaceEndpoint }
            { name: 'DATAFLAG_ENDPOINT', value: 'https://api.dataflag.in/api/v3/rc-details' }
          ], empty(dataFlagApiKey) ? [] : [
            { name: 'DATAFLAG_API_KEY', secretRef: 'dataflag-api-key' }
          ])
          resources: {
            cpu: json('2.0')
            memory: '4Gi'
          }
          probes: [
            {
              type: 'Liveness'
              httpGet: { path: '/health', port: 8000 }
              initialDelaySeconds: 30
              periodSeconds: 30
            }
            {
              type: 'Readiness'
              httpGet: { path: '/health', port: 8000 }
              initialDelaySeconds: 10
              periodSeconds: 10
            }
          ]
        }
      ]
      scale: { minReplicas: 1, maxReplicas: 1 }
    }
  }
}

resource storageAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, api.id, blobContributorRole)
  scope: storage
  properties: {
    roleDefinitionId: blobContributorRole
    principalId: api.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource registryAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, api.id, acrPullRole)
  scope: registry
  properties: {
    roleDefinitionId: acrPullRole
    principalId: api.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource cosmosAccess 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: cosmos
  name: guid(cosmos.id, api.id, 'data-contributor')
  properties: {
    roleDefinitionId: '${cosmos.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    principalId: api.identity.principalId
    scope: cosmos.id
  }
}

output apiUrl string = 'https://${api.properties.configuration.ingress.fqdn}'
output apiName string = api.name
output apiPrincipalId string = api.identity.principalId
output registryName string = registry.name
output registryServer string = registry.properties.loginServer
output storageAccountName string = storage.name
output cosmosAccountName string = cosmos.name
