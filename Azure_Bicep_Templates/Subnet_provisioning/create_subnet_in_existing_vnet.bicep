@description('Resource location. By default it will be the resourceGroup location.')
param location string = resourceGroup().location

@description('Subnet CIDR address (i.e. 10.0.1.0/24)')
param subnetAddrPrefix string

@description('Name of the parent virtual network that this subent should belong to.')
param parentVnetName string

@description('Subnet name.')
param subnetName string

@description('Network Security Group name.')
param nsgName string

resource nsg 'Microsoft.Network/networkSecurityGroups@2025-05-01' = {
  location: location
  name: nsgName
}

// Reference to the existing Virtual Network
resource vNet 'Microsoft.Network/virtualNetworks@2025-05-01' existing = {
  name: parentVnetName
  // scope: resourceGroup('otherRgName') // Use if VNet is in a different resource group
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2025-05-01' = {
  name: subnetName
  parent: vNet
  properties: {
    // prevent resource in this subnet to access the internet
    defaultOutboundAccess: false
    addressPrefix: subnetAddrPrefix
    networkSecurityGroup: {
      id: nsg.id
      location: location
    }
  }
}
