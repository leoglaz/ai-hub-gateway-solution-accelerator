using './main.bicep'

/*
 * Development Environment Configuration
 * Optimized for cost and quick deployments
 */

// Basic Configuration
param environmentName = 'ai-hub-citadel-dev'
param location = 'canadacentral'
param apicLocation = 'canadacentral'  // APIC in same region for lower latency
param resourceGroupName = 'ailz-apim-dev'  // New RG in canadacentral
param tags = {
  'azd-env-name': 'ai-hub-citadel-dev'
  SecurityControl: 'Ignore'
  Environment: 'Development'
  CostCenter: 'Engineering'
}

// Use Developer SKU for lower cost
param apimSku = 'Developer'
param apimSkuUnits = 1

// Minimal capacity for dev
param cosmosDbRUs = 400
param eventHubCapacityUnits = 1

// Enable dashboards for monitoring during development
param createAppInsightsDashboards = false

// API Center (custom name to avoid global name collision)
param enableAPICenter = true
//param apicServiceName = 'apic-citadel-dev-cc'

// Enable features for testing
param enableAIFoundry = true
param enableAIGatewayPiiRedaction = true
param enableAIModelInference = true

// Azure Managed Redis (AMR)
param enableManagedRedis = true
param redisPublicNetworkAccess = 'Disabled'
param redisSkuName = 'Balanced_B0'
param redisSkuCapacity = 1

// No Entra ID auth in dev (simplifies testing)
param entraAuth = false

// Use new Log Analytics workspace (don't use existing)
param useExistingLogAnalytics = false

// Public network access for easier development
param cosmosDbPublicAccess = 'Enabled'
param eventHubNetworkAccess = 'Enabled'
param keyVaultExternalNetworkAccess = 'Enabled'

// Key Vault SKU (standard is sufficient for dev)
param keyVaultSkuName = 'standard'

// Content Safety F0 (S0 not available in canadacentral)
param aiContentSafetySkuName = 'F0'

// Use existing VNet (canadacentral)
param useExistingVnet = true
param existingVnetRG = 'rg-aiml2-lz-dev-canadcentral3'
param vnetName = 'vnet-aiml-lz-cc3'
param apimSubnetName = 'APIMSubnet'
param privateEndpointSubnetName = 'PrivateEndpointSubnet'
param functionAppSubnetName = 'LogicAppSubnet'

// AI Foundry instances in canadaeast (Azure OpenAI available region)
param aiFoundryInstances = [
  {
    name: ''
    location: 'canadaeast'
    customSubDomainName: ''
    defaultProjectName: 'citadel-governance-project'
  }
  {
    name: ''
    location: 'eastus2'
    customSubDomainName: ''
    defaultProjectName: 'citadel-governance-project'
  }
]
