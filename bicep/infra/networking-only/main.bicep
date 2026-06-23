/**
 * @module networking-only
 * @description Deploys ONLY the networking foundation for the AI Hub Gateway Solution Accelerator:
 *              - Resource Group
 *              - Private DNS Zones (privatelink.* for all backend services)
 *              - Virtual Network with subnets (APIM, Private Endpoints, Function App, optional Agent)
 *              - Network Security Groups (one per subnet)
 *              - Route Table for the APIM subnet
 *              - Private DNS Zone <-> VNet links
 *
 *              No application/PaaS resources (APIM, Cosmos, Event Hub, Foundry, Redis, etc.) are
 *              provisioned. This lets you stand up and review the network landing zone first, then
 *              run the full deployment against the existing VNet (set useExistingVnet=true in the
 *              main accelerator deployment, pointing existingVnetRG at this resource group).
 *
 * Scope: Subscription (creates the resource group, then deploys the networking modules into it).
 *
 * Naming: Uses the SAME resourceToken algorithm as the main accelerator
 *         (uniqueString(subscription().id, environmentName, location)) so default resource names
 *         line up with a later full deployment that reuses this network.
 */

targetScope = 'subscription'

// =====================================================================
//    BASIC PARAMETERS
// =====================================================================

@minLength(1)
@maxLength(64)
@description('Name of the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all networking resources.')
@allowed([ 'uaenorth', 'southafricanorth', 'westeurope', 'southcentralus', 'australiaeast', 'canadaeast', 'eastus', 'eastus2', 'francecentral', 'japaneast', 'northcentralus', 'swedencentral', 'switzerlandnorth', 'uksouth' ])
param location string

@description('Tags to be applied to resources.')
param tags object = { 'azd-env-name': environmentName, 'SecurityControl': 'Ignore' }

@description('Name of the resource group. Leave blank to use default naming conventions.')
param resourceGroupName string = ''

// =====================================================================
//    NETWORKING - NAMES
// =====================================================================

@description('Name of the Virtual Network. Leave blank to use default naming conventions.')
param vnetName string = ''

@description('Subnet name for API Management in the VNet. Leave blank to use default naming conventions.')
param apimSubnetName string = ''

@description('Subnet name for Private Endpoints in the VNet. Leave blank to use default naming conventions.')
param privateEndpointSubnetName string = ''

@description('Subnet name for Function/Logic App in the VNet. Leave blank to use default naming conventions.')
param functionAppSubnetName string = ''

@description('Subnet name for AI Foundry agent (network injection) workloads. Leave blank to use default naming conventions.')
param agentSubnetName string = ''

@description('NSG name for API Management subnet. Leave blank to use default naming conventions.')
param apimNsgName string = ''

@description('NSG name for Private Endpoint subnet. Leave blank to use default naming conventions.')
param privateEndpointNsgName string = ''

@description('NSG name for Function App subnet. Leave blank to use default naming conventions.')
param functionAppNsgName string = ''

@description('NSG name for AI Foundry agent (network injection) subnet. Leave blank to use default naming conventions.')
param agentSubnetNsgName string = ''

@description('Route Table name for API Management subnet. Leave blank to use default naming conventions.')
param apimRouteTableName string = ''

// =====================================================================
//    NETWORKING - ADDRESS SPACE
// =====================================================================

@description('Virtual Network address space.')
param vnetAddressPrefix string = '10.170.0.0/24'

@description('API Management subnet address range.')
param apimSubnetPrefix string = '10.170.0.0/26'

@description('Private Endpoint subnet address range.')
param privateEndpointSubnetPrefix string = '10.170.0.64/26'

@description('Function App subnet address range.')
param functionAppSubnetPrefix string = '10.170.0.128/26'

@description('AI Foundry agent (network injection) subnet address range. Used only when foundryNetworkInjectionEnabled is true. Subnet is delegated to Microsoft.App/environments.')
param agentSubnetPrefix string = '10.170.0.192/26'

// =====================================================================
//    NETWORKING - FEATURE FLAGS
// =====================================================================

@description('API Management service SKU the network will host. Controls whether the APIM subnet is delegated to Microsoft.Web/serverFarms (required for the V2 SKUs).')
@allowed([ 'Developer', 'Premium', 'StandardV2', 'PremiumV2' ])
param apimSku string = 'Developer'

@description('Enable the AI Foundry agent (network injection) subnet, delegated to Microsoft.App/environments. Defaults to FALSE. Only enable when you intend to use the full Foundry Standard Agent (BYO) setup.')
param foundryNetworkInjectionEnabled bool = false

@description('Use Azure Monitor Private Link Scope. When true, the privatelink.monitor.azure.com DNS zone is also created.')
param useAzureMonitorPrivateLinkScope bool = false

// =====================================================================
//    VARIABLES
// =====================================================================

var abbrs = loadJsonContent('../abbreviations.json')

// Match the main accelerator's token algorithm so default names line up with a later full deployment.
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

// Private DNS zone names (kept in sync with the main accelerator's privateDnsZoneNames)
var openAiPrivateDnsZoneName = 'privatelink.openai.azure.com'
var keyVaultPrivateDnsZoneName = 'privatelink.vaultcore.azure.net'
var monitorPrivateDnsZoneName = 'privatelink.monitor.azure.com'
var eventHubPrivateDnsZoneName = 'privatelink.servicebus.windows.net'
var cosmosDbPrivateDnsZoneName = 'privatelink.documents.azure.com'
var storageBlobPrivateDnsZoneName = 'privatelink.blob.core.windows.net'
var storageFilePrivateDnsZoneName = 'privatelink.file.core.windows.net'
var storageTablePrivateDnsZoneName = 'privatelink.table.core.windows.net'
var storageQueuePrivateDnsZoneName = 'privatelink.queue.core.windows.net'
var aiCogntiveServicesDnsZoneName = 'privatelink.cognitiveservices.azure.com'
var apimV2SkuDnsZoneName = 'privatelink.azure-api.net'
var aiServicesDnsZoneName = 'privatelink.services.ai.azure.com'
var redisPrivateDnsZoneName = 'privatelink.redis.azure.net'

var baseDnsZoneNames = [
  openAiPrivateDnsZoneName
  aiCogntiveServicesDnsZoneName
  keyVaultPrivateDnsZoneName
  eventHubPrivateDnsZoneName
  cosmosDbPrivateDnsZoneName
  storageBlobPrivateDnsZoneName
  storageFilePrivateDnsZoneName
  storageTablePrivateDnsZoneName
  storageQueuePrivateDnsZoneName
  apimV2SkuDnsZoneName
  aiServicesDnsZoneName
  redisPrivateDnsZoneName
]

// Only include the Azure Monitor DNS zone when Private Link Scope is enabled
var privateDnsZoneNames = useAzureMonitorPrivateLinkScope ? concat(baseDnsZoneNames, [monitorPrivateDnsZoneName]) : baseDnsZoneNames

// =====================================================================
//    RESOURCE GROUP
// =====================================================================

resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// =====================================================================
//    PRIVATE DNS ZONES
// =====================================================================

module dnsDeployment '../modules/networking/dns.bicep' = [for privateDnsZoneName in privateDnsZoneNames: {
  name: 'dns-deployment-${privateDnsZoneName}'
  scope: resourceGroup
  params: {
    name: privateDnsZoneName
    tags: tags
  }
}]

// =====================================================================
//    VIRTUAL NETWORK (subnets, NSGs, route table, DNS links)
// =====================================================================

module vnet '../modules/networking/vnet.bicep' = {
  name: 'vnet'
  scope: resourceGroup
  params: {
    name: !empty(vnetName) ? vnetName : 'vnet-${resourceToken}'
    apimSubnetName: !empty(apimSubnetName) ? apimSubnetName : 'snet-apim'
    apimNsgName: !empty(apimNsgName) ? apimNsgName : 'nsg-apim-${resourceToken}'
    privateEndpointSubnetName: !empty(privateEndpointSubnetName) ? privateEndpointSubnetName : 'snet-private-endpoint'
    privateEndpointNsgName: !empty(privateEndpointNsgName) ? privateEndpointNsgName : 'nsg-pe-${resourceToken}'
    functionAppSubnetName: !empty(functionAppSubnetName) ? functionAppSubnetName : 'snet-functionapp'
    functionAppNsgName: !empty(functionAppNsgName) ? functionAppNsgName : 'nsg-functionapp-${resourceToken}'
    enableAgentSubnet: foundryNetworkInjectionEnabled
    agentSubnetName: !empty(agentSubnetName) ? agentSubnetName : 'snet-agents'
    agentSubnetNsgName: !empty(agentSubnetNsgName) ? agentSubnetNsgName : 'nsg-agents-${resourceToken}'
    agentSubnetAddressPrefix: agentSubnetPrefix
    vnetAddressPrefix: vnetAddressPrefix
    apimSubnetAddressPrefix: apimSubnetPrefix
    isAPIMV2SKU: apimSku == 'StandardV2' || apimSku == 'PremiumV2'
    privateEndpointSubnetAddressPrefix: privateEndpointSubnetPrefix
    functionAppSubnetAddressPrefix: functionAppSubnetPrefix
    location: location
    tags: tags
    privateDnsZoneNames: privateDnsZoneNames
    apimRouteTableName: !empty(apimRouteTableName) ? apimRouteTableName : 'rt-apim-${resourceToken}'
  }
  dependsOn: [
    dnsDeployment
  ]
}

// =====================================================================
//    OUTPUTS
// =====================================================================

@description('Name of the resource group containing the network.')
output resourceGroupName string = resourceGroup.name

@description('Resource ID of the Virtual Network.')
output virtualNetworkId string = vnet.outputs.virtualNetworkId

@description('Name of the Virtual Network. Use this as vnetName (with useExistingVnet=true) in the full deployment.')
output vnetName string = vnet.outputs.vnetName

@description('Resource group of the Virtual Network. Use this as existingVnetRG in the full deployment.')
output vnetRG string = vnet.outputs.vnetRG

output apimSubnetName string = vnet.outputs.apimSubnetName
output apimSubnetId string = vnet.outputs.apimSubnetId
output privateEndpointSubnetName string = vnet.outputs.privateEndpointSubnetName
output privateEndpointSubnetId string = vnet.outputs.privateEndpointSubnetId
output functionAppSubnetName string = vnet.outputs.functionAppSubnetName
output functionAppSubnetId string = vnet.outputs.functionAppSubnetId
output agentSubnetName string = vnet.outputs.agentSubnetName
output agentSubnetId string = vnet.outputs.agentSubnetId

@description('Names of the private DNS zones created in the resource group.')
output privateDnsZoneNames array = privateDnsZoneNames
