#!/usr/bin/env bash
#
# test/run-tests.sh — discover and run all test-*.sh files in this directory.
#
# Each test is a standalone bash script that exits 0 on pass, non-zero on fail.
# Tests run sequentially; first failure does NOT abort the suite (so you see
# all failures in one go).

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$TEST_DIR")"

PASS=0
FAIL=0
FAILED_NAMES=()

# Filter: if args were passed, only run tests whose names contain any arg.
filter_match() {
  [ "$#" -eq 0 ] && return 0
  local needle name="$1"; shift
  for needle in "$@"; do
    [[ "$name" == *"$needle"* ]] && return 0
  done
  return 1
}

START=$(date +%s)

shopt -s nullglob
for test in "$TEST_DIR"/test-*.sh; do
  name="$(basename "$test" .sh)"
  if [ "$#" -gt 0 ]; then
    matched=0
    for arg in "$@"; do [[ "$name" == *"$arg"* ]] && matched=1; done
    [ "$matched" -eq 1 ] || continue
  fi

  printf "\n=== %s ===\n" "$name"
  if ( cd "$TEST_DIR" && REPO_ROOT="$REPO" bash "$test" ); then
    printf "PASS: %s\n" "$name"
    PASS=$((PASS+1))
  else
    printf "FAIL: %s\n" "$name"
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("$name")
  fi
done

ELAPSED=$(( $(date +%s) - START ))

echo
echo "------------------------------------------------------------"
printf "Results: %d passed, %d failed (%ds)\n" "$PASS" "$FAIL" "$ELAPSED"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed: ${FAILED_NAMES[*]}"
fi

exit "$FAIL"
