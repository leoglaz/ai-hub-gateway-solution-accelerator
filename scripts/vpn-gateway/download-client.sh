#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

output_file="${1:-$PWD/ailz-vpn-client.zip}"
require_command curl

echo "Generating Azure VPN Client package..."
package_url="$(az network vnet-gateway vpn-client generate \
    --resource-group "$HUB_RESOURCE_GROUP" \
    --name "$VPN_GATEWAY_NAME" \
    --processor-architecture Amd64 \
    --subscription "$SUBSCRIPTION_ID" \
    --output tsv)"

[[ -n "$package_url" ]] || { echo "Error: Azure did not return a VPN client package URL." >&2; exit 1; }
curl --fail --location "$package_url" --output "$output_file"
echo "VPN client package downloaded to: $output_file"
