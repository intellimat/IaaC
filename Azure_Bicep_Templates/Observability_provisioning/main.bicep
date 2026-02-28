@description('Primary region for all Azure resources.')
@minLength(1)
param location string = resourceGroup().location

@description('A unique token used for resource name generation.')
@minLength(3)
param resourceToken string = toLower(uniqueString(resourceGroup().id))
@description('Log Analytics Prefix name.')
@minLength(3)
param prefix string

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2025-07-01' = {
  name: '${prefix}-${resourceToken}'
  location: location
  properties: {
    retentionInDays: 30
    workspaceCapping: {
      dailyQuotaGb: 1 // stops ingestion after 1GB in a day
    }
    sku: {
      name: 'PerGB2018'
    }
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

output workspaceId string = logAnalytics.id
output workspaceName string = logAnalytics.name
