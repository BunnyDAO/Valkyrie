#!/usr/bin/env bash
#
# Tests for --max-hours time cap (issue 0002).
#
# Each test sets up its own temp workdir; first failure exits 1.

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO_ROOT:-$(dirname "$TEST_DIR")}"
RALPH_AFK="$REPO/scripts/afk"
STUBS="$TEST_DIR/stubs"
FIXTURE_ISSUES="$TEST_DIR/fixtures/smoke/issues"

new_workdir() {
  WORKDIR="$(mktemp -d)"
  mkdir -p "$WORKDIR/issues" "$WORKDIR/docs/prd"
  cp "$FIXTURE_ISSUES/"*.md "$WORKDIR/issues/"
  echo "stub PRD content" > "$WORKDIR/docs/prd/dummy.md"
  echo "$WORKDIR"
}

fail() { echo "FAIL: $*"; [ -n "${OUT:-}" ] && [ -f "$OUT" ] && { echo "--- stdout ---"; cat "$OUT"; }; exit 1; }
assert_match() { grep -q "$2" "$1" || fail "expected /$2/ in $1"; }
assert_no_match() { grep -q "$2" "$1" && fail "unexpected /$2/ in $1"; return 0; }

# ---------------------------------------------------------------------------
# 1. Time cap fires at iteration boundary, not mid-iter.
#    Stub sleeps 2s; deadline is ~2.88s from start; one iter completes,
#    second is not started.
# ---------------------------------------------------------------------------
W="$(new_workdir)"; OUT="$W/run.out"
( cd "$W" && STUB_SLEEP_SEC=2 PATH="$STUBS:$PATH" "$RALPH_AFK" --no-confirm 5 --max-hours 0.0008 >"$OUT" 2>&1 )
RC=$?
[ "$RC" -eq 0 ]                                                           || fail "case 1: exit $RC"
assert_match "$OUT" "reason: time cap hit"
grep -q '^status: done' "$W/issues/0001-fake-feature-a.md"                || fail "case 1: 0001 should be done"
grep -q '^status: open' "$W/issues/0002-fake-feature-b.md"                || fail "case 1: 0002 should be untouched"
rm -rf "$W"

# ---------------------------------------------------------------------------
# 2. Default banner shows the default cap when no flag passed.
# ---------------------------------------------------------------------------
W="$(new_workdir)"; OUT="$W/run.out"
( cd "$W" && PATH="$STUBS:$PATH" "$RALPH_AFK" --no-confirm 2 >"$OUT" 2>&1 )
[ $? -eq 0 ] || fail "case 2: nonzero exit"
assert_match "$OUT" "caps active"
assert_match "$OUT" "4h00m"
rm -rf "$W"

# ---------------------------------------------------------------------------
# 3. Custom --max-hours appears in the banner and elapsed in summary.
# ---------------------------------------------------------------------------
W="$(new_workdir)"; OUT="$W/run.out"
( cd "$W" && PATH="$STUBS:$PATH" "$RALPH_AFK" --no-confirm 2 --max-hours 0.5 >"$OUT" 2>&1 )
[ $? -eq 0 ] || fail "case 3: nonzero exit"
assert_match "$OUT" "0h30m"
assert_match "$OUT" "afk: stopped"
assert_match "$OUT" "reason:"
rm -rf "$W"

# ---------------------------------------------------------------------------
# 4. Final summary banner appears on natural exit (no more issues).
# ---------------------------------------------------------------------------
W="$(new_workdir)"; OUT="$W/run.out"
# Only 2 fixture issues; ask for 5 iterations → exits via "no more issues".
( cd "$W" && PATH="$STUBS:$PATH" "$RALPH_AFK" --no-confirm 5 >"$OUT" 2>&1 )
[ $? -eq 0 ] || fail "case 4: nonzero exit"
assert_match "$OUT" "reason: no more issues"
assert_match "$OUT" "iterations:"
assert_match "$OUT" "elapsed:"
rm -rf "$W"

# ---------------------------------------------------------------------------
# 5. Iteration cap reason fires when N issues complete and we wanted more.
#    Make 3 issues; max iters = 2; expect "iteration cap hit".
# ---------------------------------------------------------------------------
W="$(new_workdir)"; OUT="$W/run.out"
cat > "$W/issues/0003-fake-feature-c.md" <<'EOF'
---
id: 0003
title: Fake feature C
type: AFK
status: open
blocked_by: []
---
EOF
( cd "$W" && PATH="$STUBS:$PATH" "$RALPH_AFK" --no-confirm 2 >"$OUT" 2>&1 )
[ $? -eq 0 ] || fail "case 5: nonzero exit"
assert_match "$OUT" "reason: iteration cap hit"
rm -rf "$W"

# ---------------------------------------------------------------------------
# 6. Bad --max-hours rejected.
# ---------------------------------------------------------------------------
W="$(new_workdir)"; OUT="$W/run.out"
( cd "$W" && PATH="$STUBS:$PATH" "$RALPH_AFK" --no-confirm 2 --max-hours abc >"$OUT" 2>&1 )
[ $? -eq 2 ] || fail "case 6a: expected exit 2 for non-numeric"
( cd "$W" && PATH="$STUBS:$PATH" "$RALPH_AFK" --no-confirm 2 --max-hours -1 >"$OUT" 2>&1 )
[ $? -eq 2 ] || fail "case 6b: expected exit 2 for negative"
( cd "$W" && PATH="$STUBS:$PATH" "$RALPH_AFK" --no-confirm 2 --max-hours 0 >"$OUT" 2>&1 )
[ $? -eq 2 ] || fail "case 6c: expected exit 2 for zero"
rm -rf "$W"

# ---------------------------------------------------------------------------
# 7. SIGTERM/SIGINT prints summary banner with reason: interrupted.
#    Tests use SIGTERM because bash ignores SIGINT for backgrounded jobs;
#    both signals run the same INT|TERM trap, and real user Ctrl-C (in a
#    foreground tty) delivers SIGINT to the same handler.
# ---------------------------------------------------------------------------
W="$(new_workdir)"; OUT="$W/run.out"
(
  cd "$W"
  STUB_SLEEP_SEC=5 PATH="$STUBS:$PATH" "$RALPH_AFK" --no-confirm 5 >"$OUT" 2>&1 &
  RAFK_PID=$!
  sleep 1
  kill -TERM "$RAFK_PID" 2>/dev/null
  wait "$RAFK_PID" 2>/dev/null
  exit 0
)
assert_match "$OUT" "reason: interrupted"
rm -rf "$W"

echo "max-hours tests ok"
