param name string
param location string = resourceGroup().location
param sku string = 'Standard'
param capacity int = 1
param tags object = {}
param eventHubName string = 'ai-usage'

param eventHubPrivateEndpointName string
param vNetName string
param privateEndpointSubnetName string
param eventHubDnsZoneName string

param publicNetworkAccess string = 'Disabled'
param virtualNetworkRules array = []

// Use existing network/dns zone
param dnsZoneRG string
param dnsSubscriptionId string
param vNetRG string

resource vnet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = {
  name: vNetName
  scope: resourceGroup(vNetRG)
}

// Get existing subnet
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' existing = {
  name: privateEndpointSubnetName
  parent: vnet
}

resource eventHubNamespace 'Microsoft.EventHub/namespaces@2024-05-01-preview' = {
  name: name
  location: location
  tags: union(tags, { 'azd-service-name': name })
  sku: {
    name: sku
    tier: sku
    capacity: capacity
  }
  properties: {
    isAutoInflateEnabled: false
    maximumThroughputUnits: 0
    publicNetworkAccess: publicNetworkAccess
  }

  resource network 'networkRuleSets' = if (publicNetworkAccess == 'Enabled') {
    name: 'default'
    properties: {
      defaultAction: 'Deny'
      trustedServiceAccessEnabled: true
      publicNetworkAccess: publicNetworkAccess
      virtualNetworkRules: virtualNetworkRules
    }
  }

  resource eventHub 'eventhubs' = {
    name: 'ai-usage'
    properties: {
      messageRetentionInDays: 7
      partitionCount: 2
      status: 'Active'
    }
  }
}

module privateEndpoint '../networking/private-endpoint.bicep' = {
  name: '${eventHubName}-privateEndpoint'
  params: {
    groupIds: [
      'namespace'
    ]
    dnsZoneName: eventHubDnsZoneName
    name: eventHubPrivateEndpointName
    privateLinkServiceId: eventHubNamespace.id
    location: location
    dnsZoneRG: dnsZoneRG
    privateEndpointSubnetId: subnet.id
    dnsSubId: dnsSubscriptionId
  }
}

output eventHubNamespaceName string = eventHubNamespace.name
output eventHubName string = eventHubNamespace::eventHub.name
output eventHubEndpoint string = eventHubNamespace.properties.serviceBusEndpoint
