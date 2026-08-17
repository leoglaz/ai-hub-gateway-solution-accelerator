#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

echo "VPN Gateway:"
az network vnet-gateway show \
    --resource-group "$HUB_RESOURCE_GROUP" \
    --name "$VPN_GATEWAY_NAME" \
    --subscription "$SUBSCRIPTION_ID" \
    --query '{name:name,state:provisioningState,sku:sku.name,clientPool:vpnClientConfiguration.vpnClientAddressPool.addressPrefixes,protocols:vpnClientConfiguration.vpnClientProtocols,auth:vpnClientConfiguration.vpnAuthenticationTypes}' \
    --output table

echo "Hub-to-AILZ peering:"
az network vnet peering show \
    --resource-group "$HUB_RESOURCE_GROUP" \
    --vnet-name "$HUB_VNET_NAME" \
    --name "$HUB_TO_SPOKE_PEERING_NAME" \
    --subscription "$SUBSCRIPTION_ID" \
    --query '{state:peeringState,sync:peeringSyncLevel,gatewayTransit:allowGatewayTransit,remoteGateway:useRemoteGateways,vnetAccess:allowVirtualNetworkAccess,forwardedTraffic:allowForwardedTraffic}' \
    --output table

echo "AILZ-to-hub peering:"
az network vnet peering show \
    --resource-group "$SPOKE_RESOURCE_GROUP" \
    --vnet-name "$SPOKE_VNET_NAME" \
    --name "$SPOKE_TO_HUB_PEERING_NAME" \
    --subscription "$SUBSCRIPTION_ID" \
    --query '{state:peeringState,sync:peeringSyncLevel,gatewayTransit:allowGatewayTransit,remoteGateway:useRemoteGateways,vnetAccess:allowVirtualNetworkAccess,forwardedTraffic:allowForwardedTraffic}' \
    --output table

echo "Expected VPN client route to the AILZ VNet: 10.170.0.0/24"
echo "After importing a newly generated client profile and connecting, verify that route locally."
