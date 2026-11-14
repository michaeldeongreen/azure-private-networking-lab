#!/usr/bin/env bash
set -euo pipefail

if [[ "${CHANGES_RESULT:-}" != success ]]; then
  echo "Change detection did not succeed." >&2
  exit 1
fi
if [[ "${INFRA_SELECTED:-}" == true && "${INFRA_RESULT:-}" == success ]] ||
   [[ "${INFRA_SELECTED:-}" == false && "${INFRA_RESULT:-}" == skipped ]]; then
  echo "All selected checks passed."
else
  echo "Infrastructure selection or validation result is invalid." >&2
  exit 1
fi
