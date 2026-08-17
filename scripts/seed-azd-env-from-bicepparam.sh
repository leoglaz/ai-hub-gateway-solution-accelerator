#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
default_source="$repo_root/bicep/infra/main.parameters.dev.bicepparam"
mapping_source="$repo_root/bicep/infra/main.bicepparam"

source_file="$default_source"
environment_name=""
dry_run=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Seeds an azd environment from parameters in a Bicep parameters file.

Options:
  -f, --file <path>          Source .bicepparam file
                            (default: bicep/infra/main.parameters.dev.bicepparam)
  -e, --environment <name>  Destination azd environment
                            (default: source environmentName parameter)
  -n, --dry-run             Print values without changing the azd environment
  -h, --help                Show this help

Single-line string, integer, and boolean literals are read directly. Mapped arrays
and objects are compiled with Bicep and stored as compact JSON.
EOF
}

while (($# > 0)); do
    case "$1" in
        -f|--file)
            [[ $# -ge 2 ]] || { echo "Error: $1 requires a path." >&2; exit 1; }
            source_file="$2"
            shift 2
            ;;
        -e|--environment)
            [[ $# -ge 2 ]] || { echo "Error: $1 requires a name." >&2; exit 1; }
            environment_name="$2"
            shift 2
            ;;
        -n|--dry-run)
            dry_run=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown option '$1'." >&2
            usage >&2
            exit 1
            ;;
    esac
done

[[ -f "$source_file" ]] || { echo "Error: Parameter file not found: $source_file" >&2; exit 1; }
[[ -f "$mapping_source" ]] || { echo "Error: Mapping parameter file not found: $mapping_source" >&2; exit 1; }

declare -A environment_names=()
while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ $line =~ ^[[:space:]]*param[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=.*readEnvironmentVariable\(\'([A-Z0-9_]+)\' ]]; then
        environment_names["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
    fi
done < "$mapping_source"

parameter_names=()
parameter_values=()
azd_variable_names=()
structured_parameter_names=()

while IFS= read -r line || [[ -n "$line" ]]; do
    [[ $line =~ ^[[:space:]]*param[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=(.*)$ ]] || continue

    parameter_name="${BASH_REMATCH[1]}"
    raw_value="${BASH_REMATCH[2]}"
    value=""

    if [[ $raw_value =~ ^[[:space:]]*\'(.*)\'[[:space:]]*(//.*)?$ ]]; then
        value="${BASH_REMATCH[1]//\'\'/\'}"
    elif [[ $raw_value =~ ^[[:space:]]*(-?[0-9]+|true|false)[[:space:]]*(//.*)?$ ]]; then
        value="${BASH_REMATCH[1]}"
    else
        if [[ $raw_value =~ ^[[:space:]]*[\[\{] ]] && [[ -n "${environment_names[$parameter_name]:-}" ]]; then
            structured_parameter_names+=("$parameter_name")
        fi
        continue
    fi

    azd_variable_name="${environment_names[$parameter_name]:-}"
    if [[ -z "$azd_variable_name" ]]; then
        echo "Warning: No azd environment mapping for parameter '$parameter_name'; skipping." >&2
        continue
    fi

    parameter_names+=("$parameter_name")
    parameter_values+=("$value")
    azd_variable_names+=("$azd_variable_name")

    if [[ -z "$environment_name" && "$parameter_name" == "environmentName" ]]; then
        environment_name="$value"
    fi
done < "$source_file"

if [[ ${#structured_parameter_names[@]} -gt 0 ]]; then
    command -v az >/dev/null 2>&1 || { echo "Error: Azure CLI is required to compile structured parameters." >&2; exit 1; }
    command -v jq >/dev/null 2>&1 || { echo "Error: jq is required to serialize structured parameters." >&2; exit 1; }

    compiled_parameters="$(az bicep build-params --file "$source_file" --stdout)"

    for parameter_name in "${structured_parameter_names[@]}"; do
        if ! value="$(jq -cer --arg name "$parameter_name" \
            '.parametersJson | fromjson | .parameters[$name].value | select(type == "array" or type == "object") | tojson' \
            <<< "$compiled_parameters")"; then
            echo "Error: Could not extract structured parameter '$parameter_name' from compiled Bicep parameters." >&2
            exit 1
        fi

        parameter_names+=("$parameter_name")
        parameter_values+=("$value")
        azd_variable_names+=("${environment_names[$parameter_name]}")
    done
fi

[[ ${#parameter_names[@]} -gt 0 ]] || { echo "Error: No supported mapped parameters found in $source_file" >&2; exit 1; }
[[ -n "$environment_name" ]] || { echo "Error: Pass --environment or define a literal environmentName parameter." >&2; exit 1; }

if [[ "$dry_run" == false ]]; then
    command -v azd >/dev/null 2>&1 || { echo "Error: azd is not installed or not on PATH." >&2; exit 1; }
fi

echo "Source: $source_file"
echo "Destination azd environment: $environment_name"

for index in "${!parameter_names[@]}"; do
    parameter_name="${parameter_names[$index]}"
    value="${parameter_values[$index]}"
    azd_variable_name="${azd_variable_names[$index]}"

    if [[ "$dry_run" == true ]]; then
        printf '%s=%q  # %s\n' "$azd_variable_name" "$value" "$parameter_name"
    else
        echo "Setting $azd_variable_name from $parameter_name..."
        azd env set --environment "$environment_name" "$azd_variable_name" "$value" --no-prompt
    fi
done

if [[ "$dry_run" == true ]]; then
    echo "Dry run complete; no azd values were changed."
else
    echo "Seeded ${#parameter_names[@]} values into azd environment '$environment_name'."
fi