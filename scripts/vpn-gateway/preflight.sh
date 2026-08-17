#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

if [[ ! "$VPN_AAD_AUDIENCE" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
    echo "Error: VPN_AAD_AUDIENCE must be an exact UUID without leading or trailing whitespace." >&2
    exit 1
fi

echo "Checking target VNet and network ranges..."

spoke_json="$(az network vnet show \
    --resource-group "$SPOKE_RESOURCE_GROUP" \
    --name "$SPOKE_VNET_NAME" \
    --subscription "$SUBSCRIPTION_ID" \
    --output json)" || {
        echo "Error: Existing AILZ VNet '$SPOKE_VNET_NAME' was not found." >&2
        exit 1
    }

all_vnet_prefixes="$(az network vnet list \
    --subscription "$SUBSCRIPTION_ID" \
    --query '[].{id:id,prefixes:addressSpace.addressPrefixes}' \
    --output json)"

python3 - "$HUB_VNET_PREFIX" "$GATEWAY_SUBNET_PREFIX" "$VPN_CLIENT_ADDRESS_POOL" \
    "$hub_vnet_id" "$all_vnet_prefixes" <<'PY'
import ipaddress
import json
import sys

hub = ipaddress.ip_network(sys.argv[1])
gateway = ipaddress.ip_network(sys.argv[2])
clients = ipaddress.ip_network(sys.argv[3])
hub_id = sys.argv[4].lower()
vnets = json.loads(sys.argv[5])

if not gateway.subnet_of(hub):
    raise SystemExit(f"Error: GatewaySubnet {gateway} must be contained in hub VNet {hub}.")
if gateway.prefixlen > 27:
    raise SystemExit(f"Error: GatewaySubnet {gateway} must be /27 or larger; /26 is recommended.")
if hub.overlaps(clients):
    raise SystemExit(f"Error: Hub VNet {hub} overlaps VPN client pool {clients}.")

for vnet in vnets:
    if vnet["id"].lower() == hub_id:
        continue
    for prefix in vnet.get("prefixes") or []:
        network = ipaddress.ip_network(prefix)
        if hub.overlaps(network):
            raise SystemExit(f"Error: Hub VNet {hub} overlaps {network} on {vnet['id']}.")
        if clients.overlaps(network):
            raise SystemExit(f"Error: VPN client pool {clients} overlaps {network} on {vnet['id']}.")
PY

if resource_exists "$hub_vnet_id"; then
    hub_json="$(az network vnet show \
        --resource-group "$HUB_RESOURCE_GROUP" \
        --name "$HUB_VNET_NAME" \
        --subscription "$SUBSCRIPTION_ID" \
        --output json)"
    actual_hub_location="$(jq -r '.location' <<< "$hub_json")"
    actual_hub_prefixes="$(jq -r '.addressSpace.addressPrefixes | sort | join(",")' <<< "$hub_json")"
    actual_gateway_prefix="$(jq -r '.subnets[]? | select(.name == "GatewaySubnet") | .addressPrefix' <<< "$hub_json")"

    [[ "$actual_hub_location" == "$LOCATION" ]] || {
        echo "Error: Existing hub VNet location '$actual_hub_location' does not match '$LOCATION'." >&2
        exit 1
    }
    [[ "$actual_hub_prefixes" == "$HUB_VNET_PREFIX" ]] || {
        echo "Error: Existing hub VNet prefix '$actual_hub_prefixes' does not match '$HUB_VNET_PREFIX'." >&2
        exit 1
    }
    [[ "$actual_gateway_prefix" == "$GATEWAY_SUBNET_PREFIX" ]] || {
        echo "Error: Existing GatewaySubnet '$actual_gateway_prefix' does not match '$GATEWAY_SUBNET_PREFIX'." >&2
        exit 1
    }
fi

existing_spoke_gateways=""
conflicting_hub_gateways=""
while IFS= read -r gateway_id; do
    [[ -n "$gateway_id" ]] || continue
    gateway_subnet_id="$(az resource show \
        --ids "$gateway_id" \
        --subscription "$SUBSCRIPTION_ID" \
        --query 'properties.ipConfigurations[0].properties.subnet.id' \
        --output tsv)"
    if [[ "${gateway_subnet_id,,}" == *"/virtualnetworks/${SPOKE_VNET_NAME,,}/"* ]]; then
        existing_spoke_gateways+="$gateway_id"$'\n'
    fi
    if [[ "${gateway_subnet_id,,}" == *"/virtualnetworks/${HUB_VNET_NAME,,}/"* ]] \
        && [[ "${gateway_id##*/}" != "$VPN_GATEWAY_NAME" ]]; then
        conflicting_hub_gateways+="$gateway_id"$'\n'
    fi
done < <(az resource list \
    --subscription "$SUBSCRIPTION_ID" \
    --resource-type Microsoft.Network/virtualNetworkGateways \
    --query '[].id' \
    --output tsv)
if [[ -n "$existing_spoke_gateways" ]]; then
    echo "Error: The AILZ VNet already has a virtual network gateway and cannot use a remote gateway:" >&2
    echo "$existing_spoke_gateways" >&2
    exit 1
fi
if [[ -n "$conflicting_hub_gateways" ]]; then
    echo "Error: The hub VNet already has a differently named virtual network gateway:" >&2
    echo "$conflicting_hub_gateways" >&2
    exit 1
fi

remote_gateway_peering="$(jq -r '.virtualNetworkPeerings[]? | select(.useRemoteGateways == true) | .name' <<< "$spoke_json")"
if [[ -n "$remote_gateway_peering" && "$remote_gateway_peering" != "$SPOKE_TO_HUB_PEERING_NAME" ]]; then
    echo "Error: The AILZ VNet already uses a remote gateway through peering '$remote_gateway_peering'." >&2
    exit 1
fi

conflicting_spoke_peering="$(jq -r --arg hub "${hub_vnet_id,,}" --arg expected "$SPOKE_TO_HUB_PEERING_NAME" \
    '.virtualNetworkPeerings[]? | select((.remoteVirtualNetwork.id | ascii_downcase) == $hub and .name != $expected) | .name' \
    <<< "$spoke_json")"
if [[ -n "$conflicting_spoke_peering" ]]; then
    echo "Error: Peering '$conflicting_spoke_peering' already connects the AILZ VNet to the proposed hub." >&2
    exit 1
fi

provider_state="$(az provider show \
    --namespace Microsoft.Network \
    --subscription "$SUBSCRIPTION_ID" \
    --query registrationState \
    --output tsv)"
if [[ "$provider_state" != "Registered" ]]; then
    echo "Error: Microsoft.Network provider state is '$provider_state'; register it before deployment." >&2
    exit 1
fi

echo "Preflight passed."
echo "  Hub:       $HUB_VNET_NAME ($HUB_VNET_PREFIX), $LOCATION"
echo "  Gateway:   $VPN_GATEWAY_NAME ($VPN_GATEWAY_SKU)"
echo "  P2S pool:  $VPN_CLIENT_ADDRESS_POOL"
echo "  AILZ VNet: $SPOKE_VNET_NAME ($(jq -r '.addressSpace.addressPrefixes | join(", ")' <<< "$spoke_json"))"
