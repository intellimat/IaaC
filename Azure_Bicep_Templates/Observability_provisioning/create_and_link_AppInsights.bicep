/* This template creates an application insights and
 * link it to an existing VM (that has a managed-identity)
 * link it to an existing Log Analytics Workspace
*/

@description('Location for all resources')
param location string = resourceGroup().location

@description('Name of existing Virtual Machine')
param vmName string

@description('Name for the new Application Insights instance')
param appInsightsPrefix string

@description('Name of existing Log Analytics Workspace')
param logAnalyticsWorkspaceName string

@description('Resource group where Log Analytics Workspace exists')
param logAnalyticsWorkspaceResourceGroup string

@description('Tags to apply')
param tags object = {}

@description('A unique token used for resource name generation.')
@minLength(3)
param resourceToken string = toLower(uniqueString(resourceGroup().id))

// Reference existing VM
resource vm 'Microsoft.Compute/virtualMachines@2025-04-01' existing = {
  name: vmName
}

// Reference existing Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-07-01' existing = {
  name: logAnalyticsWorkspaceName
  scope: resourceGroup(logAnalyticsWorkspaceResourceGroup)
}

// Create Application Insights for your app
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${appInsightsPrefix}-${resourceToken}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    RetentionInDays: 90
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    DisableIpMasking: false
    DisableLocalAuth: true
    SamplingPercentage: 50
  }
}

// Built-in role: Monitoring Metrics Publisher
var monitoringMetricsPublisherRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '3913510d-42f4-4e42-8a64-420c390055eb'
)

// Assign monitoringMetricsPublisherRoleId to system-assigned VM identity
resource appInsightsRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(appInsights.id, vm.id, monitoringMetricsPublisherRoleId)
  scope: appInsights
  properties: {
    roleDefinitionId: monitoringMetricsPublisherRoleId
    principalId: vm.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output connectionString string = appInsights.properties.ConnectionString
output appInsightsId string = appInsights.id
