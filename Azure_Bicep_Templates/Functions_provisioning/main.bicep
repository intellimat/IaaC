/* This Bicep file creates a function app running in a Consumption plan
that connects to Azure Storage by using managed identities with Microsoft Entra ID. */

//********************************************
// Parameters
//********************************************

@description('Primary region for all Azure resources.')
@minLength(1)
param location string = resourceGroup().location

@description('A unique token used for resource name generation.')
@minLength(3)
param resourceToken string = toLower(uniqueString(resourceGroup().id))

@description('A globally unique name for your deployed function app.')
param appName string = 'fnapp-${resourceToken}'

@description('Name of the existing Log Analytics Workspace in a resource group')
param logAnalyticsWorkspaceName string

@description('Resource group where the Log Analytics Workspace exists')
param logsResourceGroupName string

//********************************************
// Variables
//********************************************

// Generates a unique container name for deployments.
var deploymentStorageContainerName = 'app-package-${take(appName, 32)}-${take(resourceToken, 7)}'

// Define the IDs of the roles we need to assign to our managed identities.
var storageBlobDataOwnerRoleId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var storageQueueDataContributorId = '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
var storageTableDataContributorId = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
var monitoringMetricsPublisherId = '3913510d-42f4-4e42-8a64-420c390055eb'

//********************************************
// Link App Insights to existing Log Analytics Workspace
//********************************************

// Reference the existing workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2025-07-01' existing = {
  name: logAnalyticsWorkspaceName
  scope: resourceGroup(logsResourceGroupName)
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${resourceToken}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    DisableLocalAuth: true
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2025-06-01' = {
  name: 'sa${resourceToken}'
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true // we need it because Azure Files does not support using managed identity when accessing the file share.
    dnsEndpointType: 'Standard'
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    publicNetworkAccess: 'Enabled'
  }
  resource blobServices 'blobServices' = {
    name: 'default'
    properties: {
      deleteRetentionPolicy: {}
    }
    resource deploymentContainer 'containers' = {
      name: deploymentStorageContainerName
      properties: {
        publicAccess: 'None'
      }
    }
  }

  resource tableServices 'tableServices' = {
    name: 'default'
    resource tables 'tables' = {
      name: 'DeploymentInfo'
    }
  }
}

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'uai-data-owner-${resourceToken}'
  location: location
}

resource roleAssignmentBlobDataOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, storage.id, userAssignedIdentity.id, 'Storage Blob Data Owner')
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource roleAssignmentBlob 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, storage.id, userAssignedIdentity.id, 'Storage Blob Data Contributor')
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      storageBlobDataContributorRoleId
    )
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource roleAssignmentQueueStorage 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, storage.id, userAssignedIdentity.id, 'Storage Queue Data Contributor')
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageQueueDataContributorId)
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource roleAssignmentTableStorage 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, storage.id, userAssignedIdentity.id, 'Storage Table Data Contributor')
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorId)
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource roleAssignmentAppInsights 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, applicationInsights.id, userAssignedIdentity.id, 'Monitoring Metrics Publisher')
  scope: applicationInsights
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherId)
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

//********************************************
// Function app and Flex Consumption plan definitions
//********************************************

resource appServicePlan 'Microsoft.Web/serverfarms@2025-03-01' = {
  name: 'svcplan-${resourceToken}'
  location: location
  kind: 'functionapp'
  // Consumption-plan
  sku: {
    tier: 'Dynamic'
    name: 'Y1'
  }
  properties: {
    reserved: true // required for Linux App Service plan
  }
}

resource functionApp 'Microsoft.Web/sites@2025-03-01' = {
  name: appName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      minTlsVersion: '1.2'
      linuxFxVersion: 'Python|3.12'
      functionAppScaleLimit: 2 // max 2 instances ever
    }
  }

  resource configAppSettings 'config' = {
    name: 'appsettings'
    properties: {
      AzureWebJobsStorage__accountName: storage.name
      AzureWebJobsStorage__clientId: userAssignedIdentity.properties.clientId
      AzureWebJobsStorage__credential: 'managedidentity'
      WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
      WEBSITE_CONTENTSHARE: toLower(appName)
      APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.properties.ConnectionString
      APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'ClientId=${userAssignedIdentity.properties.clientId};Authorization=AAD'
      FUNCTIONS_WORKER_RUNTIME: 'python'
      FUNCTIONS_EXTENSION_VERSION: '~4'
      SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
    }
  }
}
