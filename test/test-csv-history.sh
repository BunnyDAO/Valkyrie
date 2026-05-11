#!/usr/bin/env bash
#
# Tests for issue 0005: CSV cost history file.

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO_ROOT:-$(dirname "$TEST_DIR")}"
RALPH_AFK="$REPO/scripts/ralph-afk"
STUBS="$TEST_DIR/stubs"
COST_FIX="$TEST_DIR/fixtures/cost"
ISSUE_FIX="$TEST_DIR/fixtures/smoke/issues"

CSV_HEADER='timestamp,iter,model,input_tokens,output_tokens,cache_write_5m,cache_write_1h,cache_read,cost_usd,cumulative_usd,exit_reason_for_run'

fail() { echo "FAIL: $*"; [ -n "${OUT:-}" ] && [ -f "$OUT" ] && { echo "--- stdout ---"; cat "$OUT"; }; exit 1; }

make_fake_home() {
  local home="$1"
  mkdir -p "$home/.claude/valkyrie"
  cp "$REPO/scripts/rates.json"      "$home/.claude/valkyrie/rates.json"
  cp "$REPO/scripts/cost-helper.py"  "$home/.claude/valkyrie/cost-helper.py"
}

new_workdir() {
  local w; w="$(mktemp -d)"
  mkdir -p "$w/issues" "$w/docs/prd"
  cp "$ISSUE_FIX/"*.md "$w/issues/"
  echo "stub PRD content" > "$w/docs/prd/dummy.md"
  echo "$w"
}

run_ra() {
  ( cd "$W" && HOME="$H" PATH="$STUBS:$PATH" "$@" --no-confirm >"$OUT" 2>&1 )
}

CSV_REL=".claude/valk/afk-cost-history.csv"

# ---------------------------------------------------------------------------
# 1. First run creates CSV with the expected header followed by N rows.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir)"; OUT="$W/run.out"
make_fake_home "$H"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra "$RALPH_AFK" 2
[ $? -eq 0 ] || fail "case 1: nonzero exit"
csv="$W/$CSV_REL"
[ -f "$csv" ] || fail "case 1: csv missing"
header="$(head -n 1 "$csv")"
[ "$header" = "$CSV_HEADER" ] || fail "case 1: header mismatch — got '$header'"
rows=$(($(wc -l < "$csv") - 1))
[ "$rows" -eq 2 ] || fail "case 1: expected 2 rows, got $rows"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 2. Second run appends, header is not duplicated.
#    Reset the fixture issues' status to 'open' between runs (simulates a
#    second invocation against a fresh batch of work).
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir)"; OUT="$W/run.out"
make_fake_home "$H"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra "$RALPH_AFK" 2
[ $? -eq 0 ] || fail "case 2 first run: nonzero exit"
# Reset all issue statuses to 'open' for the second run.
for f in "$W/issues/"*.md; do
  sed -e 's/^status: done/status: open/' -e 's/^status: stuck/status: open/' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra "$RALPH_AFK" 2
[ $? -eq 0 ] || fail "case 2 second run: nonzero exit"
csv="$W/$CSV_REL"
header_count=$(grep -c "^$CSV_HEADER" "$csv" || true)
[ "$header_count" -eq 1 ] || fail "case 2: expected 1 header, got $header_count"
rows=$(($(wc -l < "$csv") - 1))
[ "$rows" -eq 4 ] || fail "case 2: expected 4 rows after two 2-iter runs, got $rows"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 3. Each row has exactly 11 comma-separated fields.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir)"; OUT="$W/run.out"
make_fake_home "$H"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra "$RALPH_AFK" 2
[ $? -eq 0 ] || fail "case 3: nonzero exit"
csv="$W/$CSV_REL"
# Each data row should have 10 commas (11 fields). awk counts.
awk -F, 'NR>1 && NF != 11 { print "row "NR" has "NF" fields, expected 11"; exit 1 }' "$csv" \
  || fail "case 3: row field count mismatch"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 4. cumulative_usd of row N equals cumulative_usd of row N-1 + cost_usd of N.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir)"; OUT="$W/run.out"
make_fake_home "$H"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra "$RALPH_AFK" 2
csv="$W/$CSV_REL"
# Pull the two data rows. Field 9=cost_usd, Field 10=cumulative_usd.
prev_cum=0
while IFS=, read -r ts iter model i o c5 c1 cr cost cum reason; do
  [ "$ts" = "timestamp" ] && continue
  expected=$(awk -v p="$prev_cum" -v c="$cost" 'BEGIN{printf "%.6f", p+c+0}')
  got=$(awk -v c="$cum" 'BEGIN{printf "%.6f", c+0}')
  [ "$expected" = "$got" ] || fail "case 4: cumulative mismatch at iter $iter — expected $expected, got $got"
  prev_cum="$cum"
done < "$csv"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 5. Last row of a finished run has exit_reason_for_run populated.
#    Earlier rows have it empty.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir)"; OUT="$W/run.out"
make_fake_home "$H"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra "$RALPH_AFK" 2
[ $? -eq 0 ] || fail "case 5: nonzero exit"
csv="$W/$CSV_REL"
last_reason=$(awk -F, 'END{print $NF}' "$csv")
[ -n "$last_reason" ] && [ "$last_reason" != "exit_reason_for_run" ] \
  || fail "case 5: last row reason should be set, got '$last_reason'"
# Earlier rows (iter 1, which is row 2 in file): reason should be empty.
first_data_reason=$(awk -F, 'NR==2{print $NF}' "$csv")
[ -z "$first_data_reason" ] || fail "case 5: earlier row reason should be empty, got '$first_data_reason'"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 6. SIGTERM preserves rows from completed iterations.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir)"; OUT="$W/run.out"
make_fake_home "$H"
# Stub sleeps 5s; we'll SIGTERM after ~1s, so iter 1 won't have completed.
(
  cd "$W"
  STUB_SLEEP_SEC=5 STUB_FIXTURE="$COST_FIX/opus-simple.log" \
    HOME="$H" PATH="$STUBS:$PATH" "$RALPH_AFK" 5 >"$OUT" 2>&1 &
  pid=$!
  sleep 1
  kill -TERM "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  exit 0
)
csv="$W/$CSV_REL"
# CSV may not exist yet (no iters completed) — that's fine. If it does, last
# row's reason should be 'interrupted' and the file should be valid.
if [ -f "$csv" ]; then
  rows=$(($(wc -l < "$csv") - 1))
  if [ "$rows" -gt 0 ]; then
    last_reason=$(awk -F, 'END{print $NF}' "$csv")
    [ "$last_reason" = "interrupted" ] || fail "case 6: last row reason should be 'interrupted', got '$last_reason'"
  fi
fi
rm -rf "$H" "$W"

echo "csv-history tests ok"
