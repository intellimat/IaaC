@description('Resource location. By default it will be the resourceGroup location.')
param location string = resourceGroup().location

@description('Network Security Group name.')
param nsgName string

resource nsg 'Microsoft.Network/networkSecurityGroups@2025-05-01' = {
  location: location
  name: nsgName
}
