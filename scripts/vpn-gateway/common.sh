#!/usr/bin/env bash

set -euo pipefail

vpn_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$vpn_script_dir/config.sh"

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Error: Required command '$1' is not installed or not on PATH." >&2
        exit 1
    }
}

require_command az
require_command jq
require_command python3

if ! az account show --output none 2>/dev/null; then
    echo "Error: Azure CLI is not authenticated. Run 'az login' first." >&2
    exit 1
fi

if ! az account show --subscription "$SUBSCRIPTION_ID" --output none 2>/dev/null; then
    echo "Error: Subscription '$SUBSCRIPTION_ID' is not accessible to the current Azure CLI identity." >&2
    exit 1
fi

TENANT_ID="${TENANT_ID:-$(az account show --subscription "$SUBSCRIPTION_ID" --query tenantId --output tsv)}"
VPN_AAD_TENANT_URI="${VPN_AAD_TENANT_URI:-https://login.microsoftonline.com/$TENANT_ID/}"
VPN_AAD_ISSUER_URI="${VPN_AAD_ISSUER_URI:-https://sts.windows.net/$TENANT_ID/}"

hub_vnet_id="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$HUB_RESOURCE_GROUP/providers/Microsoft.Network/virtualNetworks/$HUB_VNET_NAME"
spoke_vnet_id="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$SPOKE_RESOURCE_GROUP/providers/Microsoft.Network/virtualNetworks/$SPOKE_VNET_NAME"

resource_exists() {
    az resource show --ids "$1" --subscription "$SUBSCRIPTION_ID" --output none 2>/dev/null
}

wait_for_gateway() {
    echo "Waiting for VPN Gateway '$VPN_GATEWAY_NAME' to finish provisioning..."
    az network vnet-gateway wait \
        --resource-group "$HUB_RESOURCE_GROUP" \
        --name "$VPN_GATEWAY_NAME" \
        --subscription "$SUBSCRIPTION_ID" \
        --updated \
        --interval 30 \
        --timeout 3600
}
