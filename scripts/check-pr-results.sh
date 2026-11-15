#!/usr/bin/env bash
set -euo pipefail

if [[ "${CHANGES_RESULT:-}" != success ]]; then
  echo "Change detection did not succeed." >&2
  exit 1
fi
if ! { [[ "${INFRA_SELECTED:-}" == true && "${INFRA_RESULT:-}" == success ]] ||
       [[ "${INFRA_SELECTED:-}" == false && "${INFRA_RESULT:-}" == skipped ]]; }; then
  echo "Infrastructure selection or validation result is invalid." >&2
  exit 1
fi
if ! { [[ "${CODE_FUNCTIONAPP_SELECTED:-}" == true && "${CODE_FUNCTIONAPP_RESULT:-}" == success ]] ||
       [[ "${CODE_FUNCTIONAPP_SELECTED:-}" == false && "${CODE_FUNCTIONAPP_RESULT:-}" == skipped ]]; }; then
  echo "Function App code selection or validation result is invalid." >&2
  exit 1
fi
echo "All selected checks passed."
