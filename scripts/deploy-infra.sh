#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C
if [[ ! "${APP_NAME:-}" =~ ^[a-z0-9]{1,3}$ ]]; then
  echo "APP_NAME must be 1-3 lowercase letters or digits." >&2
  exit 1
fi
if [[ ! "${INFRA_ENVIRONMENT:-}" =~ ^[a-z0-9]{1,8}$ ]]; then
  echo "INFRA_ENVIRONMENT must be 1-8 lowercase letters or digits." >&2
  exit 1
fi
if [[ "${INFRA_ENVIRONMENT:-}:${DEPLOY_BRANCH:-}" != "dev:develop" ]]; then
  echo "Deployment is enabled only for the Dev environment from develop." >&2
  exit 1
fi
if [[ ! "${AZURE_RESOURCE_GROUP:-}" =~ ^[a-zA-Z0-9._()-]{1,90}$ || "${AZURE_RESOURCE_GROUP:-}" == *. ]]; then
  echo "AZURE_RESOURCE_GROUP must be a valid Azure resource group name." >&2
  exit 1
fi
if [[ ! "${CI_HEAD_SHA:-}" =~ ^[0-9a-f]{40}$ || -z "${AZURE_SUBSCRIPTION_ID:-}" || -z "${GITHUB_REPOSITORY:-}" ]]; then
  echo "The CI revision, subscription, and repository must be set." >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$(git -C "$repo_root" rev-parse HEAD)" != "$CI_HEAD_SHA" ]]; then
  echo "Checked-out revision does not match the successful CI revision." >&2
  exit 1
fi

check_branch() {
  local branch_sha
  branch_sha="$(gh api "repos/$GITHUB_REPOSITORY/git/ref/heads/$DEPLOY_BRANCH" --jq .object.sha)"
  if [[ "$branch_sha" != "$CI_HEAD_SHA" ]]; then
    echo "The successful CI revision is no longer the deployment branch head." >&2
    exit 1
  fi
}

output_dir="$(mktemp -d)"
trap 'rm -rf "$output_dir"' EXIT
export LAB_APP_NAME="$APP_NAME"
export INFRA_ENVIRONMENT
export AZURE_BICEP_USE_BINARY_FROM_PATH=false

az bicep install --version v0.49.2
az bicep version
az bicep build --file "$repo_root/infra/main.bicep" --outfile "$output_dir/main.json"
az bicep build-params --file "$repo_root/infra/main.bicepparam" --outfile "$output_dir/main.parameters.json"

check_branch
az deployment group what-if \
  --subscription "$AZURE_SUBSCRIPTION_ID" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --mode Incremental \
  --template-file "$output_dir/main.json" \
  --parameters "@$output_dir/main.parameters.json" \
  --result-format ResourceIdOnly

check_branch
az deployment group create \
  --subscription "$AZURE_SUBSCRIPTION_ID" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --mode Incremental \
  --template-file "$output_dir/main.json" \
  --parameters "@$output_dir/main.parameters.json" \
  --output none
