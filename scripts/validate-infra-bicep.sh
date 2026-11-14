#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 || ( "${1:-}" != "dev" && "${1:-}" != "test" ) ]]; then
  echo "Usage: bash scripts/validate-infra-bicep.sh <dev|test> <app-name>" >&2
  exit 1
fi

export LC_ALL=C
if [[ ! "$2" =~ ^[a-z0-9]{1,3}$ ]]; then
  echo "App name must be 1-3 lowercase letters or digits; set the APP_NAME repository variable." >&2
  exit 1
fi

environment_name="$1"
export LAB_APP_NAME="$2"
export INFRA_ENVIRONMENT="$environment_name"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="$(mktemp -d)"
trap 'rm -rf "$output_dir"' EXIT

export AZURE_BICEP_USE_BINARY_FROM_PATH=false
az bicep install --version v0.49.2
az bicep version

echo "Validating infrastructure for environment: $environment_name"
az bicep build \
  --file "$repo_root/infra/main.bicep" \
  --outfile "$output_dir/main.json"
az bicep build-params \
  --file "$repo_root/infra/main.bicepparam" \
  --outfile "$output_dir/main.parameters.json"
