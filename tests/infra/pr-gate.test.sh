#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin"
export REAL_GIT="$(command -v git)"
export FIXTURE_REPO="$test_dir/repo"
export PATH="$test_dir/bin:$PATH"
export BASE_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
export MERGE_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
export GITHUB_OUTPUT="$test_dir/output"

cat > "$test_dir/bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == 'rev-parse HEAD' ]]; then
  case "${SCENARIO:-}" in
    wrong-checkout) echo cccccccccccccccccccccccccccccccccccccccc ;;
    rev-error) exit 1 ;;
    *) echo "$MERGE_SHA" ;;
  esac
  exit
fi
if [[ "${SCENARIO:-}" == real ]]; then
  exec "$REAL_GIT" -C "$FIXTURE_REPO" "$@"
fi
if [[ "$*" == "diff --no-renames --name-only -z $BASE_SHA $MERGE_SHA -- src .github/workflows/ci-code.yml .github/workflows/ci-code-reusable.yml .github/workflows/cd-code.yml .github/workflows/cd-code-reusable.yml scripts/detect-code-changes.sh" ]]; then
  case "${SCENARIO:-}" in
    none) ;;
    code) printf '%s\0' 'src/HelloFunction/Hello.cs' ;;
    code-test) printf '%s\0' 'src/HelloFunction.Tests/HelloTests.cs' ;;
    code-workflow) printf '%s\0' '.github/workflows/ci-code-reusable.yml' ;;
    code-deployment) printf '%s\0' '.github/workflows/cd-code-reusable.yml' ;;
    code-detection) printf '%s\0' 'scripts/detect-code-changes.sh' ;;
    rename-out) printf '%s\0' 'src/old.cs' 'docs/old.cs' ;;
    other) printf '%s\0' 'infra/main.bicep' ;;
    diff-error) exit 1 ;;
    *) exit 1 ;;
  esac
  exit
fi
[[ "$*" == "diff --no-renames --name-only -z $BASE_SHA $MERGE_SHA -- infra" ]] || exit 1
case "${SCENARIO:-}" in
  none) ;;
  bicep) printf '%s\0' 'infra/main.bicep' ;;
  params) printf '%s\0' 'infra/nested/main.bicepparam' ;;
  spaces) printf '%s\0' 'infra/a file.bicep' ;;
  deleted) printf '%s\0' 'infra/deleted.bicep' ;;
  rename-out) printf '%s\0' 'infra/old.bicep' 'docs/old.bicep' ;;
  rename-in) printf '%s\0' 'docs/new.bicep' 'infra/new.bicep' ;;
  other) printf '%s\0' 'infra/readme.md' 'infra/main.bicep.txt' ;;
  diff-error) exit 1 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$test_dir/bin/git"

detect() {
  local scenario="$1" expected="$2"
  rm -f "$GITHUB_OUTPUT"
  if SCENARIO="$scenario" bash "$root/scripts/detect-infra-bicep-changes.sh" > "$test_dir/log" 2>&1; then
    [[ "$expected" != failure ]] || { echo "$scenario unexpectedly succeeded"; exit 1; }
    [[ "$(cat "$GITHUB_OUTPUT")" == "infra=$expected" ]] || { echo "$scenario selected the wrong paths"; exit 1; }
  else
    [[ "$expected" == failure ]] || { cat "$test_dir/log"; exit 1; }
    [[ ! -e "$GITHUB_OUTPUT" ]] || { echo "$scenario emitted a result after failure"; exit 1; }
  fi
}

detect none false
detect other false
for scenario in bicep params spaces deleted rename-out rename-in; do
  detect "$scenario" true
done
for scenario in wrong-checkout rev-error diff-error; do
  detect "$scenario" failure
done
BASE_SHA=invalid detect invalid-base failure
MERGE_SHA=invalid detect invalid-merge failure
BASE_SHA='' detect missing-base failure
MERGE_SHA='' detect missing-merge failure

detect_code() {
  local scenario="$1" expected="$2"
  rm -f "$GITHUB_OUTPUT"
  if SCENARIO="$scenario" bash "$root/scripts/detect-code-changes.sh" > "$test_dir/log" 2>&1; then
    [[ "$expected" != failure ]] || { echo "Code $scenario unexpectedly succeeded"; exit 1; }
    [[ "$(cat "$GITHUB_OUTPUT")" == "code=$expected" ]] || { echo "Code $scenario selected the wrong paths"; exit 1; }
  else
    [[ "$expected" == failure ]] || { cat "$test_dir/log"; exit 1; }
    [[ ! -e "$GITHUB_OUTPUT" ]] || { echo "Code $scenario emitted a result after failure"; exit 1; }
  fi
}

for scenario in none other; do detect_code "$scenario" false; done
for scenario in code code-test code-workflow code-deployment code-detection rename-out; do detect_code "$scenario" true; done
for scenario in wrong-checkout rev-error diff-error; do detect_code "$scenario" failure; done
BASE_SHA=invalid detect_code invalid-base failure
MERGE_SHA=invalid detect_code invalid-merge failure

"$REAL_GIT" init --quiet "$FIXTURE_REPO"
blob_one="$(printf 'one' | "$REAL_GIT" -C "$FIXTURE_REPO" hash-object -w --stdin)"
blob_two="$(printf 'two' | "$REAL_GIT" -C "$FIXTURE_REPO" hash-object -w --stdin)"
tree() { "$REAL_GIT" -C "$FIXTURE_REPO" mktree; }
infra_one="$(printf '100644 blob %s\tmain.bicep\n' "$blob_one" | tree)"
infra_two="$(printf '100644 blob %s\tmain.bicep\n' "$blob_two" | tree)"
docs="$(printf '100644 blob %s\tmain.bicep\n' "$blob_one" | tree)"
root_infra="$(printf '040000 tree %s\tinfra\n' "$infra_one" | tree)"
root_modified="$(printf '040000 tree %s\tinfra\n' "$infra_two" | tree)"
root_docs="$(printf '040000 tree %s\tdocs\n' "$docs" | tree)"
root_both="$(printf '040000 tree %s\tdocs\n040000 tree %s\tinfra\n' "$docs" "$infra_one" | tree)"
root_empty="$(printf '' | tree)"
root_src="$(printf '040000 tree %s\tsrc\n' "$infra_one" | tree)"
BASE_SHA="$root_infra" MERGE_SHA="$root_both" detect real false
BASE_SHA="$root_infra" MERGE_SHA="$root_modified" detect real true
BASE_SHA="$root_infra" MERGE_SHA="$root_empty" detect real true
BASE_SHA="$root_infra" MERGE_SHA="$root_docs" detect real true
BASE_SHA="$root_docs" MERGE_SHA="$root_infra" detect real true
BASE_SHA="$root_docs" MERGE_SHA="$root_src" detect_code real true
BASE_SHA="$root_src" MERGE_SHA="$root_docs" detect_code real true
BASE_SHA="$root_infra" MERGE_SHA="$root_docs" detect_code real false

check_result() {
  local expected="$1" changes="$2" selected="$3" result="$4"
  if CHANGES_RESULT="$changes" INFRA_SELECTED="$selected" INFRA_RESULT="$result" \
    CODE_SELECTED=false CODE_RESULT=skipped \
    bash "$root/scripts/check-pr-results.sh" > "$test_dir/log" 2>&1; then
    [[ "$expected" == success ]] || { echo "Unexpected gate success: $changes/$selected/$result"; exit 1; }
  else
    [[ "$expected" == failure ]] || { cat "$test_dir/log"; exit 1; }
  fi
}

check_result success success true success
check_result success success false skipped
for result in failure cancelled skipped '' unknown; do
  check_result failure success true "$result"
done
for result in success failure cancelled '' unknown; do
  check_result failure success false "$result"
done
for changes in failure cancelled skipped '' unknown; do
  check_result failure "$changes" false skipped
done
check_result failure success '' skipped
check_result failure success unknown skipped

check_code_result() {
  local expected="$1" selected="$2" result="$3"
  if CHANGES_RESULT=success INFRA_SELECTED=false INFRA_RESULT=skipped \
    CODE_SELECTED="$selected" CODE_RESULT="$result" \
    bash "$root/scripts/check-pr-results.sh" > "$test_dir/log" 2>&1; then
    [[ "$expected" == success ]] || { echo "Unexpected code gate success: $selected/$result"; exit 1; }
  else
    [[ "$expected" == failure ]] || { cat "$test_dir/log"; exit 1; }
  fi
}

check_code_result success true success
check_code_result success false skipped
for result in failure cancelled skipped '' unknown; do
  check_code_result failure true "$result"
done
for result in success failure cancelled '' unknown; do
  check_code_result failure false "$result"
done
check_code_result failure '' skipped
check_code_result failure unknown skipped
echo "PR gate tests passed."
