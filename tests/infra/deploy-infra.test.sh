#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin"
export TEST_DIR="$test_dir"
export CI_HEAD_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
export GITHUB_REPOSITORY=example/repository
export AZURE_SUBSCRIPTION_ID=subscription
export AZURE_RESOURCE_GROUP=rg-lab-dev-eus
export INFRA_ENVIRONMENT=dev
export DEPLOY_BRANCH=develop
export APP_NAME=lab
export PATH="$test_dir/bin:$PATH"

cat > "$test_dir/bin/git" <<'EOF'
#!/usr/bin/env bash
[[ "${SCENARIO:-}" == mismatch ]] && { echo bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; exit; }
echo "$CI_HEAD_SHA"
EOF
cat > "$test_dir/bin/gh" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == *"/git/ref/heads/$DEPLOY_BRANCH"* ]] || exit 1
count=0
[[ ! -f "$TEST_DIR/gh-count" ]] || count="$(cat "$TEST_DIR/gh-count")"
count=$((count + 1))
echo "$count" > "$TEST_DIR/gh-count"
[[ "${SCENARIO:-}" == gh-error || ( "${SCENARIO:-}" == gh-error-second && $count -eq 2 ) ]] && exit 1
if [[ "${SCENARIO:-}" == stale-first || ( "${SCENARIO:-}" == stale-second && $count -eq 2 ) ]]; then
  echo bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
else
  echo "$CI_HEAD_SHA"
fi
EOF
cat > "$test_dir/bin/az" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_DIR/az-log"
if [[ "$1 $2" == 'bicep build' || "$1 $2" == 'bicep build-params' ]]; then
  [[ "${SCENARIO:-}" != build-error ]] || exit 1
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == --outfile ]]; then
      printf '{"app":"%s","environment":"%s"}\n' "$LAB_APP_NAME" "$INFRA_ENVIRONMENT" > "$2"
      exit
    fi
    shift
  done
  exit 1
fi
if [[ "$1 $2 $3" == 'deployment group what-if' ]]; then
  [[ "${SCENARIO:-}" != whatif-error ]] || exit 1
  printf '%s\n' "$*" > "$TEST_DIR/whatif"
fi
if [[ "$1 $2 $3" == 'deployment group create' ]]; then
  printf '%s\n' "$*" > "$TEST_DIR/create"
  [[ "${SCENARIO:-}" != create-error ]] || exit 1
fi
EOF
chmod +x "$test_dir/bin/git" "$test_dir/bin/gh" "$test_dir/bin/az"

run_case() {
  local scenario="$1" expected="$2"
  rm -f "$test_dir/az-log" "$test_dir/gh-count" "$test_dir/whatif" "$test_dir/create"
  if SCENARIO="$scenario" bash "$root/scripts/deploy-infra.sh" > "$test_dir/output" 2>&1; then
    [[ "$expected" == success ]] || { echo "$scenario unexpectedly succeeded"; exit 1; }
  else
    [[ "$expected" == failure ]] || { cat "$test_dir/output"; exit 1; }
  fi
}

run_case success success
[[ "$(cat "$test_dir/gh-count")" == 2 ]]
whatif="$(cat "$test_dir/whatif")"
create="$(cat "$test_dir/create")"
[[ "$whatif" == *'--resource-group rg-lab-dev-eus'* && "$create" == *'--resource-group rg-lab-dev-eus'* ]]
[[ "$whatif" == *'--mode Incremental'* && "$create" == *'--mode Incremental'* ]]
[[ "$whatif" == *'--result-format ResourceIdOnly'* && "$create" == *'--output none'* ]]
whatif_files="${whatif#*--template-file }"
whatif_files="${whatif_files%% --result-format*}"
create_files="${create#*--template-file }"
create_files="${create_files%% --output*}"
[[ "$whatif_files" == "$create_files" ]]
[[ ! -e "${whatif_files%% --parameters*}" ]]

for scenario in mismatch stale-first stale-second gh-error gh-error-second build-error whatif-error; do
  run_case "$scenario" failure
  [[ ! -e "$test_dir/create" ]] || { echo "$scenario attempted a deployment"; exit 1; }
done
run_case create-error failure
[[ -f "$test_dir/create" ]]

INFRA_ENVIRONMENT=test DEPLOY_BRANCH=test run_case test-is-disabled failure
[[ ! -e "$test_dir/az-log" ]]
DEPLOY_BRANCH=main run_case wrong-branch failure
[[ ! -e "$test_dir/az-log" ]]
APP_NAME=BAD run_case invalid-app failure
[[ ! -e "$test_dir/az-log" ]]
AZURE_SUBSCRIPTION_ID='' run_case no-subscription failure
[[ ! -e "$test_dir/az-log" ]]
AZURE_RESOURCE_GROUP='' run_case no-resource-group failure
[[ ! -e "$test_dir/az-log" ]]
echo "Mock deployment tests passed."
