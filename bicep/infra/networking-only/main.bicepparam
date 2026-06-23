using './main.bicep'

/*
 * Networking-only deployment parameters
 * Deploys VNet, subnets, NSGs, route table and private DNS zones only.
 *
 * Keep environmentName / location identical to your eventual full deployment
 * so default resource names (which include a hash of these values) line up.
 */

// Basic Configuration
param environmentName = 'ailz-hub-networking-dev'
param location = 'canadaeast'
param resourceGroupName = 'ailz-hub-networking-dev-rg' // Explicit name (no rg- prefix)

param tags = {
  'azd-env-name': 'ailz-hub-networking-dev'
  SecurityControl: 'Ignore'
  Environment: 'Development'
  CostCenter: 'Engineering'
}

// Network address space — VNet 10.170.0.0/20 spans 10.170.0.0 - 10.170.15.255 (4096 addresses).
// Subnets are aligned to valid network boundaries with no overlaps:
//   apim          10.170.0.0/26   -> 10.170.0.0   - 10.170.0.63    (64 addr)
//   functionApp   10.170.0.64/26  -> 10.170.0.64  - 10.170.0.127   (64 addr, delegated to Microsoft.Web/serverFarms)
//   privateEndpt  10.170.1.0/24   -> 10.170.1.0   - 10.170.1.255   (256 addr, room for all private endpoints)
//   agent         10.170.2.0/24   -> 10.170.2.0   - 10.170.2.255   (256 addr; /24 is the AI Foundry agent-injection minimum)
//   free          10.170.3.0/24 .. 10.170.15.0/24 reserved for future growth
param vnetAddressPrefix = '10.170.0.0/20'
param apimSubnetPrefix = '10.170.0.0/26'
param functionAppSubnetPrefix = '10.170.0.64/26'
param privateEndpointSubnetPrefix = '10.170.1.0/24'
param agentSubnetPrefix = '10.170.2.0/24'

// Must match the APIM SKU you intend to deploy later.
// Developer/Premium => APIM subnet has no delegation.
// StandardV2/PremiumV2 => APIM subnet is delegated to Microsoft.Web/serverFarms.
param apimSku = 'Developer'

// Leave false unless using the full Foundry Standard Agent (BYO) setup.
param foundryNetworkInjectionEnabled = false

// Set true to also create privatelink.monitor.azure.com (Azure Monitor Private Link Scope).
param useAzureMonitorPrivateLinkScope = false
