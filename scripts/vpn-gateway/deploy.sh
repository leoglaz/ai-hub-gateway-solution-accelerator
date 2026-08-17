#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

"$script_dir/preflight.sh"

echo "Creating or reconciling resource group '$HUB_RESOURCE_GROUP'..."
az group create \
    --name "$HUB_RESOURCE_GROUP" \
    --location "$LOCATION" \
    --subscription "$SUBSCRIPTION_ID" \
    --tags Environment=Development Workload=AILZ NetworkingPurpose=PointToSiteVPN \
    --output none

if ! resource_exists "$hub_vnet_id"; then
    echo "Creating hub VNet '$HUB_VNET_NAME'..."
    az network vnet create \
        --resource-group "$HUB_RESOURCE_GROUP" \
        --name "$HUB_VNET_NAME" \
        --location "$LOCATION" \
        --address-prefixes "$HUB_VNET_PREFIX" \
        --subnet-name GatewaySubnet \
        --subnet-prefixes "$GATEWAY_SUBNET_PREFIX" \
        --subscription "$SUBSCRIPTION_ID" \
        --tags Environment=Development Workload=AILZ NetworkingPurpose=PointToSiteVPN \
        --output none
else
    echo "Hub VNet '$HUB_VNET_NAME' already exists; preserving it."
fi

public_ip_id="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$HUB_RESOURCE_GROUP/providers/Microsoft.Network/publicIPAddresses/$VPN_GATEWAY_PUBLIC_IP_NAME"
if ! resource_exists "$public_ip_id"; then
    echo "Creating zone-redundant public IP '$VPN_GATEWAY_PUBLIC_IP_NAME'..."
    az network public-ip create \
        --resource-group "$HUB_RESOURCE_GROUP" \
        --name "$VPN_GATEWAY_PUBLIC_IP_NAME" \
        --location "$LOCATION" \
        --sku Standard \
        --allocation-method Static \
        --zone 1 2 3 \
        --subscription "$SUBSCRIPTION_ID" \
        --tags Environment=Development Workload=AILZ NetworkingPurpose=PointToSiteVPN \
        --output none
else
    echo "Public IP '$VPN_GATEWAY_PUBLIC_IP_NAME' already exists; preserving it."
fi

gateway_id="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$HUB_RESOURCE_GROUP/providers/Microsoft.Network/virtualNetworkGateways/$VPN_GATEWAY_NAME"
if ! resource_exists "$gateway_id"; then
    echo "Creating VPN Gateway '$VPN_GATEWAY_NAME'. This commonly takes 30-60 minutes..."
    az network vnet-gateway create \
        --resource-group "$HUB_RESOURCE_GROUP" \
        --name "$VPN_GATEWAY_NAME" \
        --location "$LOCATION" \
        --vnet "$HUB_VNET_NAME" \
        --public-ip-addresses "$VPN_GATEWAY_PUBLIC_IP_NAME" \
        --gateway-type Vpn \
        --vpn-type RouteBased \
        --sku "$VPN_GATEWAY_SKU" \
        --vpn-gateway-generation Generation2 \
        --subscription "$SUBSCRIPTION_ID" \
        --tags Environment=Development Workload=AILZ NetworkingPurpose=PointToSiteVPN \
        --output none
else
    echo "VPN Gateway '$VPN_GATEWAY_NAME' already exists; preserving it."
fi

echo "Configuring Point-to-Site OpenVPN with Microsoft Entra ID authentication..."
az network vnet-gateway update \
    --resource-group "$HUB_RESOURCE_GROUP" \
    --name "$VPN_GATEWAY_NAME" \
    --address-prefixes "$VPN_CLIENT_ADDRESS_POOL" \
    --client-protocol OpenVPN \
    --vpn-auth-type AAD \
    --aad-tenant "$VPN_AAD_TENANT_URI" \
    --aad-audience "$VPN_AAD_AUDIENCE" \
    --aad-issuer "$VPN_AAD_ISSUER_URI" \
    --subscription "$SUBSCRIPTION_ID" \
    --output none
wait_for_gateway

echo "Creating or reconciling hub-to-AILZ peering with gateway transit..."
if az network vnet peering show --resource-group "$HUB_RESOURCE_GROUP" --vnet-name "$HUB_VNET_NAME" \
    --name "$HUB_TO_SPOKE_PEERING_NAME" --subscription "$SUBSCRIPTION_ID" --output none 2>/dev/null; then
    az network vnet peering update \
        --resource-group "$HUB_RESOURCE_GROUP" \
        --vnet-name "$HUB_VNET_NAME" \
        --name "$HUB_TO_SPOKE_PEERING_NAME" \
        --set allowVirtualNetworkAccess=true allowForwardedTraffic=true allowGatewayTransit=true useRemoteGateways=false \
        --subscription "$SUBSCRIPTION_ID" \
        --output none
else
    az network vnet peering create \
        --resource-group "$HUB_RESOURCE_GROUP" \
        --vnet-name "$HUB_VNET_NAME" \
        --name "$HUB_TO_SPOKE_PEERING_NAME" \
        --remote-vnet "$spoke_vnet_id" \
        --allow-vnet-access \
        --allow-forwarded-traffic \
        --allow-gateway-transit \
        --subscription "$SUBSCRIPTION_ID" \
        --output none
fi

echo "Creating or reconciling AILZ-to-hub peering with remote gateway use..."
if az network vnet peering show --resource-group "$SPOKE_RESOURCE_GROUP" --vnet-name "$SPOKE_VNET_NAME" \
    --name "$SPOKE_TO_HUB_PEERING_NAME" --subscription "$SUBSCRIPTION_ID" --output none 2>/dev/null; then
    az network vnet peering update \
        --resource-group "$SPOKE_RESOURCE_GROUP" \
        --vnet-name "$SPOKE_VNET_NAME" \
        --name "$SPOKE_TO_HUB_PEERING_NAME" \
        --set allowVirtualNetworkAccess=true allowForwardedTraffic=true allowGatewayTransit=false useRemoteGateways=true \
        --subscription "$SUBSCRIPTION_ID" \
        --output none
else
    az network vnet peering create \
        --resource-group "$SPOKE_RESOURCE_GROUP" \
        --vnet-name "$SPOKE_VNET_NAME" \
        --name "$SPOKE_TO_HUB_PEERING_NAME" \
        --remote-vnet "$hub_vnet_id" \
        --allow-vnet-access \
        --allow-forwarded-traffic \
        --use-remote-gateways \
        --subscription "$SUBSCRIPTION_ID" \
        --output none
fi

echo "VPN Gateway and gateway-transit peerings are configured."
echo "Run '$script_dir/download-client.sh' to generate an Azure VPN Client package."
