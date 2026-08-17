using './main.bicep'

// Development environment configuration optimized for cost and quick deployments.

// Basic configuration
param environmentName = 'dev'
param location = 'canadaeast'
param apicLocation = 'canadacentral'
param resourceGroupName = 'ailz-hub-cc-coc-dev-1-rg'
param tags = {
  'azd-env-name': 'dev'
  SecurityControl: 'Ignore'
  Environment: 'Development'
  CostCenter: 'Engineering'
}

// Lower-cost development capacity
param apimSku = 'Developer'
param apimSkuUnits = 1
param cosmosDbRUs = 400
param eventHubCapacityUnits = 1
param createAppInsightsDashboards = false

// Features enabled for development testing
param enableAPICenter = true
param enableAIGatewayPiiRedaction = true
param enableAIModelInference = true

// Azure Managed Redis
param enableManagedRedis = true
param redisPublicNetworkAccess = 'Disabled'
param redisSkuName = 'Balanced_B0'
param redisSkuCapacity = 1

// Simplified development authentication and monitoring
param entraAuth = false
param useExistingLogAnalytics = false

// Public network access for development
param cosmosDbPublicAccess = 'Enabled'
param eventHubNetworkAccess = 'Enabled'
param keyVaultExternalNetworkAccess = 'Enabled'

// Standard Key Vault is sufficient for development
param keyVaultSkuName = 'standard'

// AI Foundry instances. Model aiserviceIndex values refer to this array.
param aiFoundryInstances = [
  {
    name: ''
    location: 'canadaeast'
    customSubDomainName: ''
    defaultProjectName: 'citadel-governance-project'
    networkInjectionEnabled: false
  }
  {
    name: ''
    location: 'eastus2'
    customSubDomainName: ''
    defaultProjectName: 'citadel-governance-project'
    networkInjectionEnabled: false
  }
]

// AI Foundry model deployments
param aiFoundryModelsConfig = [
  {
    name: 'gpt-5.6-sol'
    publisher: 'OpenAI'
    version: '2026-07-09'
    sku: 'GlobalStandard'
    capacity: 100
    retirementDate: '2028-01-11'
    apiVersion: '2025-04-01-preview'
    timeout: 180
    aiserviceIndex: 0
  }
  {
    name: 'DeepSeek-V3.2'
    publisher: 'DeepSeek'
    version: '1'
    sku: 'GlobalStandard'
    capacity: 1
    retirementDate: '2099-12-31'
    inferenceApiVersion: '2024-05-01-preview'
    aiserviceIndex: 0
  }
  {
    name: 'text-embedding-3-large'
    publisher: 'OpenAI'
    version: '1'
    sku: 'GlobalStandard'
    capacity: 100
    retirementDate: '2028-02-09'
    aiserviceIndex: 0
  }
  {
    name: 'Mistral-Large-3'
    publisher: 'Mistral AI'
    version: '1'
    sku: 'GlobalStandard'
    capacity: 100
    retirementDate: '2099-12-31'
    aiserviceIndex: 0
  }
  {
    name: 'gpt-5.4-mini'
    publisher: 'OpenAI'
    version: '2026-03-17'
    sku: 'GlobalStandard'
    capacity: 100
    retirementDate: '2027-09-21'
    apiVersion: '2025-04-01-preview'
    timeout: 180
    aiserviceIndex: 0
  }
  {
    name: 'Phi-4-reasoning'
    publisher: 'Microsoft'
    version: '1'
    sku: 'GlobalStandard'
    capacity: 1
    retirementDate: '2099-12-31'
    inferenceApiVersion: '2024-05-01-preview'
    timeout: 180
    aiserviceIndex: 0
  }
  {
    name: 'Phi-4-reasoning'
    publisher: 'Microsoft'
    version: '1'
    sku: 'GlobalStandard'
    capacity: 1
    retirementDate: '2099-12-31'
    inferenceApiVersion: '2024-05-01-preview'
    timeout: 180
    aiserviceIndex: 1
  }
  {
    name: 'gpt-5.4-mini'
    publisher: 'OpenAI'
    version: '2026-03-17'
    sku: 'GlobalStandard'
    capacity: 100
    retirementDate: '2027-09-21'
    apiVersion: '2025-04-01-preview'
    timeout: 180
    aiserviceIndex: 1
  }
  {
    name: 'gpt-5.2'
    publisher: 'OpenAI'
    version: '2025-12-11'
    sku: 'GlobalStandard'
    capacity: 100
    retirementDate: '2027-06-08'
    aiserviceIndex: 1
  }
  {
    name: 'DeepSeek-V3.2'
    publisher: 'DeepSeek'
    version: '1'
    sku: 'GlobalStandard'
    capacity: 1
    retirementDate: '2099-12-31'
    inferenceApiVersion: '2024-05-01-preview'
    aiserviceIndex: 1
  }
  {
    name: 'text-embedding-3-large'
    publisher: 'OpenAI'
    version: '1'
    sku: 'GlobalStandard'
    capacity: 100
    retirementDate: '2028-02-09'
    aiserviceIndex: 1
  }
]
