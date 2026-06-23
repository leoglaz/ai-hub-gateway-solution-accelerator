# AI Citadel Governance Hub — Infrastructure Deployment

This guide walks through the **end-to-end deployment** of the AI Hub Gateway Solution Accelerator
infrastructure in three phases:

1. **[Set up the AZD environment](#1-set-up-the-azd-environment)** — create and authenticate an Azure Developer CLI environment.
2. **[Deploy the network landing zone](#2-deploy-the-network-landing-zone)** — stand up the VNet, subnets, NSGs, route table, and private DNS zones first.
3. **[Deploy the main accelerator](#3-deploy-the-main-accelerator)** — feed the network outputs back into AZD and provision the full stack on top of the existing network.

> **Why two phases?** Deploying the network first lets you review and get sign-off on the
> landing zone (address space, subnets, DNS) before the rest of the platform is built on top of it.
> If you don't need a pre-provisioned/reviewed network, you can skip phase 2 and let `azd up`
> create the VNet for you in phase 3.

---

## Prerequisites

- Azure subscription with **Contributor** (or **Owner**) permissions
- [Azure Developer CLI (`azd`)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Azure CLI (`az`)](https://learn.microsoft.com/cli/azure/install-azure-cli) with the Bicep extension
- Git

> 💡 [Azure Cloud Shell](https://shell.azure.com) has all of these pre-installed.

---

## 1. Set up the AZD environment

From the repository root:

```bash
# Authenticate to Azure (append --tenant-id <your-tenant-id> if needed)
azd auth login

# Create a new AZD environment (this name also becomes AZURE_ENV_NAME)
azd env new ai-hub-citadel-dev-01

# Select the target subscription and region
azd env set AZURE_SUBSCRIPTION_ID <your-subscription-id>
azd env set AZURE_LOCATION canadaeast
```

Also point the Azure CLI at the same subscription (phase 2 uses `az`, not `azd`):

```bash
az account set --subscription <your-subscription-id>
```

> The AZD environment stores all `azd env set` values in `.azure/<env-name>/.env`. The accelerator's
> [`main.bicepparam`](./main.bicepparam) reads these via `readEnvironmentVariable(...)`, so anything
> you set here flows into the deployment in phase 3.

---

## 2. Deploy the network landing zone

The network-only deployment lives in [`networking-only/`](./networking-only/) and reuses the same
VNet/DNS modules and naming algorithm as the main accelerator, so names line up later.

1. Edit [`networking-only/main.bicepparam`](./networking-only/main.bicepparam) and set:
   - `environmentName` and `location` — **keep these identical to the AZD env** (`AZURE_ENV_NAME` / `AZURE_LOCATION`) so default resource names match.
   - `vnetAddressPrefix` and the subnet prefixes.
   - `apimSku` — **must match the SKU you will deploy in phase 3.** `StandardV2`/`PremiumV2` delegate the APIM subnet to `Microsoft.Web/serverFarms`; `Developer`/`Premium` do not. Changing this later requires reconfiguring the subnet.

2. (Optional) Preview what will be created:

   ```bash
   az deployment sub what-if \
     --location canadaeast \
     --template-file ./networking-only/main.bicep \
     --parameters ./networking-only/main.bicepparam
   ```

3. Deploy:

   ```bash
   az deployment sub create \
     --name aihub-networking \
     --location canadaeast \
     --template-file ./networking-only/main.bicep \
     --parameters ./networking-only/main.bicepparam
   ```

See [`networking-only/README.md`](./networking-only/README.md) for the full list of resources created.

---

## 3. Deploy the main accelerator

### 3a. Read the network outputs

Grab the values produced by phase 2:

```bash
az deployment sub show \
  --name aihub-networking \
  --query properties.outputs \
  --output json
```

Key outputs you'll reuse:

| Output | Feeds into (env var) | Purpose |
|--------|----------------------|---------|
| `vnetName` | `VNET_NAME` | Name of the existing VNet |
| `vnetRG` | `EXISTING_VNET_RG`, `DNS_ZONE_RG` | RG holding the VNet and private DNS zones |
| `apimSubnetName` | `APIM_SUBNET_NAME` | APIM subnet |
| `privateEndpointSubnetName` | `PRIVATE_ENDPOINT_SUBNET_NAME` | Private endpoints subnet |
| `functionAppSubnetName` | `FUNCTION_APP_SUBNET_NAME` | Function/Logic App subnet |
| `agentSubnetName` | `AGENT_SUBNET_NAME` | AI Foundry agent subnet (if enabled) |

> Subnet names can be omitted if you left them at their defaults in phase 2 — they already match
> what the accelerator expects. Set them explicitly only if you customized them.

### 3b. Feed the outputs into AZD

Tell the accelerator to reuse the existing network instead of creating a new one:

```bash
# Reuse the network from phase 2
azd env set USE_EXISTING_VNET true
azd env set VNET_NAME <vnetName output>
azd env set EXISTING_VNET_RG <vnetRG output>

# Reuse the private DNS zones created in phase 2 (same RG/subscription)
azd env set DNS_ZONE_RG <vnetRG output>
azd env set DNS_SUBSCRIPTION_ID <your-subscription-id>

# Match the APIM SKU you sized the network for in phase 2
azd env set APIM_SKU Developer

# (Only if you customized subnet names in phase 2)
# azd env set APIM_SUBNET_NAME <apimSubnetName output>
# azd env set PRIVATE_ENDPOINT_SUBNET_NAME <privateEndpointSubnetName output>
# azd env set FUNCTION_APP_SUBNET_NAME <functionAppSubnetName output>
# azd env set AGENT_SUBNET_NAME <agentSubnetName output>
```

### 3c. Provision and deploy

```bash
azd up
```

This provisions the full accelerator ([`main.bicep`](./main.bicep)) against the existing network and
deploys the usage-ingestion Logic App. Expected time: ~30–45 minutes.

> For the full list of tunable settings, see [`main.bicepparam`](./main.bicepparam). Each
> `readEnvironmentVariable('VAR_NAME', 'default')` maps to an `azd env set VAR_NAME <value>` you can
> apply before running `azd up`.

---

## Skipping phase 2 (let AZD create the network)

If you don't need a pre-reviewed network, skip phase 2 entirely and leave `USE_EXISTING_VNET` unset
(defaults to `false`). In phase 3, `azd up` will create the VNet, subnets, NSGs, route table, and
private DNS zones for you.

---

## Related guides

- [Quick Deployment Guide](../../guides/quick-deployment-guide.md) — fastest path for dev/test
- [Full Deployment Guide](../../guides/full-deployment-guide.md) — production guidance
- [Network Approach](../../guides/network-approach.md) — networking design details
- [Parameters Usage Guide](../../guides/parameters-usage-guide.md) — parameter reference
