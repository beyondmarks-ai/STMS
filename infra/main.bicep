targetScope = 'resourceGroup'

@description('Short lowercase deployment name, for example maxtrafficdev.')
@minLength(3)
@maxLength(15)
param namePrefix string = 'maxtrafficdev'

@description('Azure region for data and compute resources.')
param location string = resourceGroup().location

@description('Container image containing the FastAPI backend.')
param apiImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@allowed(['development', 'production'])
param environment string = 'development'

var unique = uniqueString(subscription().id, resourceGroup().id, namePrefix)
var storageName = take(toLower(replace('${namePrefix}${unique}', '-', '')), 24)
var commonTags = {
  application: 'max-smart-traffic'
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

resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${namePrefix}-appi'
  location: location
  kind: 'web'
  tags: commonTags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logs.id
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
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
    encryption: {
      keySource: 'Microsoft.Storage'
      services: { blob: { enabled: true }, file: { enabled: true } }
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {
    deleteRetentionPolicy: { enabled: true, days: 7 }
    containerDeleteRetentionPolicy: { enabled: true, days: 7 }
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

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: '${namePrefix}-kv-${take(unique, 5)}'
  location: location
  tags: commonTags
  properties: {
    tenantId: tenant().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 30
    publicNetworkAccess: 'Enabled'
  }
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: '${namePrefix}-cosmos-${take(unique, 5)}'
  location: location
  tags: commonTags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: { defaultConsistencyLevel: 'Session' }
    locations: [{ locationName: location, failoverPriority: 0, isZoneRedundant: false }]
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true
    enableFreeTier: environment == 'development'
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmos
  name: 'max-traffic'
  properties: { resource: { id: 'max-traffic' } }
}

resource incidents 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: database
  name: 'operational'
  properties: {
    resource: {
      id: 'operational'
      partitionKey: { paths: ['/camera'], kind: 'Hash' }
      defaultTtl: 2592000
    }
  }
}

resource vision 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: '${namePrefix}-vision-${take(unique, 5)}'
  location: location
  tags: commonTags
  kind: 'ComputerVision'
  sku: { name: 'S1' }
  properties: {
    customSubDomainName: '${namePrefix}-vision-${take(unique, 5)}'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true
  }
}

resource mlWorkspace 'Microsoft.MachineLearningServices/workspaces@2024-10-01' = {
  name: '${namePrefix}-ml'
  location: location
  tags: commonTags
  identity: { type: 'SystemAssigned' }
  properties: {
    friendlyName: 'STMS ML'
    description: 'Training, registry, and batch inference for traffic vision models.'
    storageAccount: storage.id
    keyVault: keyVault.id
    applicationInsights: insights.id
    publicNetworkAccess: 'Enabled'
  }
}

resource signalR 'Microsoft.SignalRService/signalR@2024-03-01' = {
  name: '${namePrefix}-signalr'
  location: location
  tags: commonTags
  kind: 'SignalR'
  sku: { name: 'Free_F1', tier: 'Free', capacity: 1 }
  properties: {
    features: [{ flag: 'ServiceMode', value: 'Serverless' }]
    cors: { allowedOrigins: [] }
    publicNetworkAccess: 'Enabled'
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
      ingress: { external: true, targetPort: 8000, transport: 'auto', allowInsecure: false }
    }
    template: {
      containers: [{
        name: 'api'
        image: apiImage
        env: [
          { name: 'ENVIRONMENT', value: environment }
          { name: 'DEMO_PROCESSOR', value: 'false' }
          { name: 'STORAGE_ACCOUNT_URL', value: storage.properties.primaryEndpoints.blob }
          { name: 'COSMOS_ENDPOINT', value: cosmos.properties.documentEndpoint }
          { name: 'VISION_ENDPOINT', value: vision.properties.endpoint }
        ]
        resources: { cpu: json('0.5'), memory: '1Gi' }
      }]
      scale: { minReplicas: 0, maxReplicas: 3 }
    }
  }
}

output apiUrl string = 'https://${api.properties.configuration.ingress.fqdn}'
output storageAccountName string = storage.name
output cosmosEndpoint string = cosmos.properties.documentEndpoint
output visionEndpoint string = vision.properties.endpoint
output machineLearningWorkspace string = mlWorkspace.name
