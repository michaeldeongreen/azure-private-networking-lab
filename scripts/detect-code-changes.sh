#!/usr/bin/env bash
set -euo pipefail

if [[ ! "${BASE_SHA:-}" =~ ^[0-9a-f]{40}$ || ! "${MERGE_SHA:-}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Expected valid pull request base and merge revisions." >&2
  exit 1
fi
if [[ "$(git rev-parse HEAD)" != "$MERGE_SHA" ]]; then
  echo "Checked-out revision does not match the pull request merge." >&2
  exit 1
fi

changes="$(mktemp)"
trap 'rm -f "$changes"' EXIT
git diff --no-renames --name-only -z "$BASE_SHA" "$MERGE_SHA" -- \
  src .github/workflows/ci-code.yml .github/workflows/ci-code-reusable.yml \
  .github/workflows/cd-code.yml .github/workflows/cd-code-reusable.yml \
  scripts/detect-code-changes.sh > "$changes"

code=false
while IFS= read -r -d '' path; do
  case "$path" in
    src/*|.github/workflows/ci-code.yml|.github/workflows/ci-code-reusable.yml|.github/workflows/cd-code.yml|.github/workflows/cd-code-reusable.yml|scripts/detect-code-changes.sh) code=true ;;
  esac
done < "$changes"
echo "code=$code" >> "$GITHUB_OUTPUT"
