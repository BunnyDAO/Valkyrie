#!/usr/bin/env bash
#
# test-valk-revisit.sh — loop-back script for mid-stream requirement changes.
# Behavior observed via filesystem + stage helper (never internals); each
# case runs in its own tempdir so stage.py state is isolated.

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO_ROOT:-$(dirname "$TEST_DIR")}"
VR="$REPO/scripts/valk-revisit"
STAGE_PY="$REPO/statusline/stage.py"

[ -x "$VR" ] || { echo "FAIL: valk-revisit missing/not exec at $VR"; exit 1; }
[ -f "$STAGE_PY" ] || { echo "FAIL: stage.py missing at $STAGE_PY"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

mkproj() { local p="$WORK/$1"; mkdir -p "$p"; echo "$p"; }
set_stage() { ( cd "$1" && python3 "$STAGE_PY" set "$2" >/dev/null ); }
get_stage() { ( cd "$1" && python3 "$STAGE_PY" get 2>/dev/null | tr -d '[:space:]' ); }

# --- 1. usage: no args → exit 2 ------------------------------------------
P="$(mkproj usage1)"
( cd "$P" && STAGE_PY="$STAGE_PY" "$VR" ) >/dev/null 2>&1
[ "$?" -eq 2 ] || fail "no-args should exit 2"

# --- 2. usage: invalid target → exit 2 -----------------------------------
P="$(mkproj badtgt)"
( cd "$P" && STAGE_PY="$STAGE_PY" "$VR" tdd "x" ) >/dev/null 2>&1
[ "$?" -eq 2 ] || fail "invalid target (tdd) should exit 2"

# --- 3. usage: empty / whitespace description → exit 2 -------------------
P="$(mkproj empty)"
( cd "$P" && STAGE_PY="$STAGE_PY" "$VR" prd "   " ) >/dev/null 2>&1
[ "$?" -eq 2 ] || fail "whitespace-only description should exit 2"

# --- 4. happy path: from issues → prd writes change note + sets stage ---
P="$(mkproj happy)"
set_stage "$P" issues
( cd "$P" && STAGE_PY="$STAGE_PY" "$VR" prd "auth needs OIDC, not local password" ) >/dev/null 2>&1
[ "$?" -eq 0 ] || fail "happy path should exit 0"
[ -d "$P/docs/changes" ] || fail "docs/changes/ not created"
NOTES="$(ls "$P/docs/changes" 2>/dev/null | wc -l | tr -d ' ')"
[ "$NOTES" -eq 1 ] || fail "expected 1 change note, got $NOTES"
NOTE="$P/docs/changes/$(ls "$P/docs/changes" | head -1)"
grep -q "from_stage: issues" "$NOTE" || fail "note missing from_stage frontmatter"
grep -q "to_stage: prd"      "$NOTE" || fail "note missing to_stage frontmatter"
grep -q "auth needs OIDC"    "$NOTE" || fail "note body missing change description"
[ "$(get_stage "$P")" = "prd" ] || fail "stage should now be prd, got '$(get_stage "$P")'"

# --- 5. downstream-target rule: from design → issues is rejected ---------
P="$(mkproj downstream)"
set_stage "$P" design
( cd "$P" && STAGE_PY="$STAGE_PY" "$VR" issues "x" ) >/dev/null 2>&1
[ "$?" -eq 2 ] || fail "downstream target from design should exit 2"
[ "$(get_stage "$P")" = "design" ] || fail "rejected revisit must not change stage"
[ ! -d "$P/docs/changes" ] || fail "rejected revisit must not write a change note"

# --- 6. idle is permissive (no active flow → any target allowed) --------
P="$(mkproj idleok)"
( cd "$P" && STAGE_PY="$STAGE_PY" "$VR" design "starter brief" ) >/dev/null 2>&1
[ "$?" -eq 0 ] || fail "from-idle should be allowed"
[ "$(get_stage "$P")" = "design" ] || fail "stage should now be design"

echo "valk-revisit tests ok"
