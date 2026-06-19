#!/usr/bin/env bash
#
# test-afk-lint-gate.sh — end-to-end proof of afk's pre-flight issue-graph gate.
#
# Drives the REAL scripts/afk against the stubbed `claude`, asserting:
#   1. BLOCK  — a live graph fault (a dup id that an OPEN issue depends on) makes
#               afk refuse to start *before it spawns the CLI* (no iteration runs)
#   2. PASS   — a warnings-only graph (an inert all-done dup) does NOT block; afk
#               runs the iteration and the stub marks the ready issue done
#   3. BYPASS — VALK_SKIP_ISSUE_LINT=1 skips the gate even on a broken graph
#
# This exercises the wiring (afk -> valk-issues.py resolution), the severity
# model (live error vs inert warning), and the override — the full path.

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO_ROOT:-$(dirname "$TEST_DIR")}"
AFK="$REPO/scripts/afk"
STUB_DIR="$TEST_DIR/stubs"

[ -x "$AFK" ]               || { echo "FAIL: afk missing at $AFK"; exit 1; }
[ -x "$STUB_DIR/claude" ]   || { echo "FAIL: stub claude missing at $STUB_DIR/claude"; exit 1; }

CLEAN=()
trap 'for d in "${CLEAN[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done' EXIT

status_of() { grep -m1 '^status:' "$1" | awk '{print $2}'; }

mkrepo() { local d; d="$(mktemp -d)"; CLEAN+=("$d"); mkdir -p "$d/issues" "$d/docs/prd"
           echo "stub prd" > "$d/docs/prd/dummy.md"; printf '%s' "$d"; }
mkissue() { # <dir> <file> <id> <status> <blocked_by-inline>
  cat > "$1/issues/$2" <<EOF
---
id: $3
title: "$2"
type: AFK
status: $4
blocked_by: $5
---
do the thing
EOF
}
run_afk() { # <dir> [VAR=val ...]   sets RC and writes <dir>/run.out
  OUT="$1/run.out"
  ( cd "$1" && env "${@:2}" PATH="$STUB_DIR:$PATH" "$AFK" 1 --no-confirm ) >"$OUT" 2>&1
  RC=$?
}

# --- 1. BLOCK: live fault stops afk before any spawn -----------------------
D="$(mkrepo)"
mkissue "$D" "0001-a.md" 0001 done "[]"
mkissue "$D" "0001-b.md" 0001 done "[]"
mkissue "$D" "0002-c.md" 0002 open "[0001]"   # OPEN issue depends on the dup id -> ERROR
run_afk "$D"
[ "$RC" -ne 0 ] || { echo "FAIL[block]: afk should refuse to start (rc=$RC)"; cat "$OUT"; exit 1; }
grep -q "issue-graph lint failed" "$OUT" || { echo "FAIL[block]: no lint-failed message"; cat "$OUT"; exit 1; }
grep -qE "DUPLICATE_ID|AMBIGUOUS_DEP" "$OUT" || { echo "FAIL[block]: lint errors not surfaced"; cat "$OUT"; exit 1; }
[ "$(status_of "$D/issues/0002-c.md")" = "open" ] || { echo "FAIL[block]: stub ran — afk did not block before spawn"; exit 1; }
# afk mkdir's afk-logs during setup; the proof no iteration ran is that no log
# file was written (and the stub never touched the issue, asserted above).
LOGS="$(ls "$D"/.claude/valk/afk-logs/*.log 2>/dev/null | wc -l | tr -d ' ')"
[ "$LOGS" -eq 0 ] || { echo "FAIL[block]: an iteration ran ($LOGS log file(s) written)"; cat "$OUT"; exit 1; }

# --- 2. PASS: warnings-only graph runs normally ----------------------------
D="$(mkrepo)"
mkissue "$D" "0001-a.md" 0001 done "[]"
mkissue "$D" "0001-b.md" 0001 done "[]"        # inert dup -> WARNING only
mkissue "$D" "0005-go.md" 0005 open "[]"        # clean, ready
run_afk "$D"
grep -q "issue-graph lint failed" "$OUT" && { echo "FAIL[pass]: afk blocked on a warnings-only graph"; cat "$OUT"; exit 1; }
[ "$(status_of "$D/issues/0005-go.md")" = "done" ] || \
  { echo "FAIL[pass]: afk did not run past the gate (0005 is $(status_of "$D/issues/0005-go.md"))"; cat "$OUT"; exit 1; }

# --- 3. BYPASS: env override skips the gate on a broken graph ---------------
D="$(mkrepo)"
mkissue "$D" "0001-a.md" 0001 done "[]"
mkissue "$D" "0001-b.md" 0001 done "[]"
mkissue "$D" "0002-c.md" 0002 open "[0001]"     # would ERROR without the bypass
run_afk "$D" VALK_SKIP_ISSUE_LINT=1
grep -q "issue-graph lint failed" "$OUT" && { echo "FAIL[bypass]: gate not bypassed"; cat "$OUT"; exit 1; }
[ "$(status_of "$D/issues/0002-c.md")" = "done" ] || { echo "FAIL[bypass]: afk did not proceed"; cat "$OUT"; exit 1; }

echo "PASS: afk lint-gate end-to-end (block / pass / bypass)"
exit 0
