# Networking-only deployment

Deploys **only** the network landing zone for the AI Hub Gateway Solution Accelerator so you can
stand up and review the network first, then run the full deployment against it later.

## What gets deployed

- **Resource Group** (`rg-<environmentName>` by default)
- **Virtual Network** (`vnet-<token>`, default address space `10.170.0.0/24`)
- **Subnets**
  - `snet-apim` (`10.170.0.0/26`) – API Management
  - `snet-private-endpoint` (`10.170.0.64/26`) – Private Endpoints
  - `snet-functionapp` (`10.170.0.128/26`) – Function/Logic App (delegated to `Microsoft.Web/serverFarms`)
  - `snet-agents` (`10.170.0.192/26`) – AI Foundry agent injection (only when `foundryNetworkInjectionEnabled = true`)
- **Network Security Groups** – one per subnet (`nsg-apim-*`, `nsg-pe-*`, `nsg-functionapp-*`, `nsg-agents-*`)
- **Route Table** – `rt-apim-*` for the APIM subnet
- **Private DNS Zones** – `privatelink.*` for OpenAI, Cognitive/AI Services, Key Vault, Event Hub,
  Cosmos DB, Storage (blob/file/table/queue), API Management, and Redis
  (plus `privatelink.monitor.azure.com` when `useAzureMonitorPrivateLinkScope = true`)
- **Private DNS Zone ↔ VNet links** for every zone above

> Reuses the same `dns.bicep` and `vnet.bicep` modules as the main accelerator, and the same
> `resourceToken` naming algorithm, so default names line up with a later full deployment.

## Prerequisites

- Azure CLI with the Bicep extension
- Contributor (or equivalent) on the target subscription

## Deploy

From `bicep/infra/networking-only/`:

```bash
# 1. Set the subscription
az account set --subscription "<your-subscription-id>"

# 2. (Optional) review the names that will be created
az deployment sub what-if \
  --location swedencentral \
  --template-file main.bicep \
  --parameters main.bicepparam

# 3. Deploy
az deployment sub create \
  --name aihub-networking \
  --location swedencentral \
  --template-file main.bicep \
  --parameters main.bicepparam
```

Edit `main.bicepparam` first to set `environmentName`, `location`, address prefixes, and the
`apimSku` you plan to use later.

> **Important:** set `apimSku` to the SKU you will deploy in the full stack.
> `StandardV2`/`PremiumV2` delegate the APIM subnet to `Microsoft.Web/serverFarms`; `Developer`/`Premium` do not.
> Changing this later requires reconfiguring the subnet.

## Read the outputs (for the full deployment)

After it completes, grab the values you need to point the full accelerator at this network:

```bash
az deployment sub show \
  --name aihub-networking \
  --query properties.outputs \
  --output json
```

Then in the **main** accelerator deployment (`bicep/infra/main.bicep`), set:

```bicep
param useExistingVnet = true
param vnetName       = '<vnetName output>'
param existingVnetRG = '<vnetRG output>'
```

Subnet and NSG names can be left at their defaults (they match this deployment), or set explicitly
to the values returned in the outputs.
