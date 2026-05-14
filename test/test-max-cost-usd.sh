#!/usr/bin/env bash
#
# Tests for issue 0004: --max-cost-usd cap enforcement, per-iter cost line,
# updated summary banner, exit-code-aware no-usage handling.

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO_ROOT:-$(dirname "$TEST_DIR")}"
RALPH_AFK="$REPO/scripts/afk"
STUBS="$TEST_DIR/stubs"
COST_FIX="$TEST_DIR/fixtures/cost"
ISSUE_FIX="$TEST_DIR/fixtures/smoke/issues"

fail() { echo "FAIL: $*"; [ -n "${OUT:-}" ] && [ -f "$OUT" ] && { echo "--- stdout ---"; cat "$OUT"; }; exit 1; }
assert_match()    { grep -q "$2" "$1" || fail "expected /$2/ in $1"; }
assert_no_match() { grep -q "$2" "$1" && fail "unexpected /$2/ in $1"; return 0; }

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

extra_issue() {
  local w="$1" id="$2"
  cat > "$w/issues/${id}-fake-extra.md" <<EOF
---
id: $id
title: Fake extra issue $id
type: AFK
status: open
blocked_by: []
---
EOF
}

# Run afk inside $W with $H as HOME, $STUBS first on PATH, plus extra
# env vars and CLI args. Auto-injects --no-confirm so confirmation prompt
# (issue 0010) doesn't block tests. Returns afk's exit code.
run_ra() {
  ( cd "$W" && HOME="$H" PATH="$STUBS:$PATH" "$@" --no-confirm >"$OUT" 2>&1 )
}

# ---------------------------------------------------------------------------
# 1. Default banner shows $50.00 cap when --max-cost-usd is not passed.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir)"; OUT="$W/run.out"
make_fake_home "$H"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra "$RALPH_AFK" 2
[ $? -eq 0 ] || fail "case 1: nonzero exit"
assert_match "$OUT" "caps active"
assert_match "$OUT" '\$50.00'
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 2. Per-iteration cumulative line is printed for each iter with cost.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir)"; OUT="$W/run.out"
make_fake_home "$H"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra "$RALPH_AFK" 2
[ $? -eq 0 ] || fail "case 2: nonzero exit"
assert_match "$OUT" "iter 1/2 done"
assert_match "$OUT" "iter 2/2 done"
assert_match "$OUT" "spend"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 3. Cost cap fires at boundary; iter 3 should NOT run.
#    Each iter $0.0525; cap $0.10 → after iter 2 cumulative ≈ $0.105 ≥ cap.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir)"; OUT="$W/run.out"
make_fake_home "$H"
extra_issue "$W" 0003
extra_issue "$W" 0004
extra_issue "$W" 0005
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra "$RALPH_AFK" 5 --max-cost-usd 0.10
[ $? -eq 0 ] || fail "case 3: nonzero exit"
assert_match "$OUT" "reason: cost cap hit"
grep -q "iter 2/5 done" "$OUT" || fail "case 3: iter 2 should have run"
grep -q "iter 3/5 done" "$OUT" && fail "case 3: iter 3 should NOT have run"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 4. Final summary banner includes spend.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir)"; OUT="$W/run.out"
make_fake_home "$H"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra "$RALPH_AFK" 2 --max-cost-usd 100
[ $? -eq 0 ] || fail "case 4: nonzero exit"
assert_match "$OUT" "spend:"
assert_match "$OUT" "afk: stopped"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 5. Clean exit (code 0) with no usage events → treat as $0, continue.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir)"; OUT="$W/run.out"
make_fake_home "$H"
STUB_FIXTURE="$COST_FIX/no-usage.log" run_ra "$RALPH_AFK" 2
RC=$?
[ "$RC" -eq 0 ] || fail "case 5: should continue on clean no-usage exit"
assert_match "$OUT" "iter 2/2 done"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 6. Dirty exit (non-zero) with no usage events → hard fail.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir)"; OUT="$W/run.out"
make_fake_home "$H"
STUB_FIXTURE="$COST_FIX/no-usage.log" STUB_EXIT_CODE=1 run_ra "$RALPH_AFK" 2
RC=$?
[ "$RC" -ne 0 ] || fail "case 6: should hard-fail on dirty no-usage exit"
assert_match "$OUT" "cost tracking failed"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 7. Unknown model at runtime hard-fails with the unknown-model error.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir)"; OUT="$W/run.out"
make_fake_home "$H"
STUB_FIXTURE="$COST_FIX/unknown-model.log" run_ra "$RALPH_AFK" 2
RC=$?
[ "$RC" -ne 0 ] || fail "case 7: should hard-fail on unknown model"
assert_match "$OUT" "claude-foo-bar"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 8. --max-cost-usd validation: non-numeric, zero, negative rejected.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir)"; OUT="$W/run.out"
make_fake_home "$H"
run_ra "$RALPH_AFK" 2 --max-cost-usd abc; [ $? -eq 2 ] || fail "case 8a: non-numeric"
run_ra "$RALPH_AFK" 2 --max-cost-usd 0;   [ $? -eq 2 ] || fail "case 8b: zero"
run_ra "$RALPH_AFK" 2 --max-cost-usd -5;  [ $? -eq 2 ] || fail "case 8c: negative"
rm -rf "$H" "$W"

echo "max-cost-usd tests ok"
