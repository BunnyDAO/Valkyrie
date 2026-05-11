#!/usr/bin/env bash
#
# Tests for issue 0007: preflight orchestrator + PRD existence gate.
# Subsequent issues (0008-0010) will append cases to this file.

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO_ROOT:-$(dirname "$TEST_DIR")}"
RALPH_AFK="$REPO/scripts/ralph-afk"
STUBS="$TEST_DIR/stubs"
COST_FIX="$TEST_DIR/fixtures/cost"
ISSUE_FIX="$TEST_DIR/fixtures/smoke/issues"

fail() { echo "FAIL: $*"; [ -n "${OUT:-}" ] && [ -f "$OUT" ] && { echo "--- stdout ---"; cat "$OUT"; }; [ -n "${ERR:-}" ] && [ -f "$ERR" ] && { echo "--- stderr ---"; cat "$ERR"; }; exit 1; }
assert_match()    { grep -q "$2" "$1" || fail "expected /$2/ in $1"; }
assert_no_match() { grep -q "$2" "$1" && fail "unexpected /$2/ in $1"; return 0; }

make_fake_home() {
  local home="$1"
  mkdir -p "$home/.claude/valkyrie"
  cp "$REPO/scripts/rates.json"      "$home/.claude/valkyrie/rates.json"
  cp "$REPO/scripts/cost-helper.py"  "$home/.claude/valkyrie/cost-helper.py"
}

# Workdir with: issues + a non-empty PRD (so preflight passes by default).
new_workdir_with_prd() {
  local w; w="$(mktemp -d)"
  mkdir -p "$w/issues" "$w/docs/prd"
  cp "$ISSUE_FIX/"*.md "$w/issues/"
  echo "stub PRD content" > "$w/docs/prd/dummy.md"
  echo "$w"
}

# Workdir with issues but NO PRD directory.
new_workdir_no_prd() {
  local w; w="$(mktemp -d)"
  mkdir -p "$w/issues"
  cp "$ISSUE_FIX/"*.md "$w/issues/"
  echo "$w"
}

run_ra() {
  ( cd "$W" && HOME="$H" PATH="$STUBS:$PATH" "$@" >"$OUT" 2>"$ERR" )
}

# Same as run_ra but auto-appends --no-confirm — for cases not testing the
# confirmation prompt behavior itself.
run_ra_no_confirm() {
  ( cd "$W" && HOME="$H" PATH="$STUBS:$PATH" "$@" --no-confirm >"$OUT" 2>"$ERR" )
}

# ---------------------------------------------------------------------------
# 1. No docs/prd/ → block with punch-list error.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir_no_prd)"; OUT="$W/run.out"; ERR="$W/run.err"
make_fake_home "$H"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra "$RALPH_AFK" 2
RC=$?
[ "$RC" -ne 0 ] || fail "case 1: should block when no docs/prd/"
assert_match "$ERR" "cannot start"
assert_match "$ERR" "no PRD found"
assert_match "$ERR" "Queue would have been"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 2. Empty docs/prd/ (no .md files) → block.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir_no_prd)"; OUT="$W/run.out"; ERR="$W/run.err"
make_fake_home "$H"
mkdir -p "$W/docs/prd"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra "$RALPH_AFK" 2
[ $? -ne 0 ] || fail "case 2: empty docs/prd/ should block"
assert_match "$ERR" "no PRD found"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 3. docs/prd/ with zero-byte file → block.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir_no_prd)"; OUT="$W/run.out"; ERR="$W/run.err"
make_fake_home "$H"
mkdir -p "$W/docs/prd"; touch "$W/docs/prd/empty.md"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra "$RALPH_AFK" 2
[ $? -ne 0 ] || fail "case 3: zero-byte PRD should block"
assert_match "$ERR" "no PRD found"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 4. docs/prd/<file>.md with content → pass, loop runs.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir_with_prd)"; OUT="$W/run.out"; ERR="$W/run.err"
make_fake_home "$H"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra_no_confirm "$RALPH_AFK" 2
[ $? -eq 0 ] || fail "case 4: should pass with non-empty PRD"
assert_match "$OUT" "iter 1/2 done"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 5. --allow-no-prd waiver works in a workdir with no PRD.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir_no_prd)"; OUT="$W/run.out"; ERR="$W/run.err"
make_fake_home "$H"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra_no_confirm "$RALPH_AFK" 2 --allow-no-prd
[ $? -eq 0 ] || fail "case 5: --allow-no-prd should pass"
assert_match "$ERR" "PRD check skipped"
assert_match "$OUT" "iter 1/2 done"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 6. Punch list goes to stderr; loop output goes to stdout.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir_no_prd)"; OUT="$W/run.out"; ERR="$W/run.err"
make_fake_home "$H"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra "$RALPH_AFK" 2
[ $? -ne 0 ] || fail "case 6: should block"
# stderr has the punch list; stdout should NOT have "cannot start"
assert_match "$ERR" "cannot start"
grep -q "cannot start" "$OUT" && fail "case 6: punch list should not appear on stdout"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 7. Queue count in punch list matches unblocked-open issue count (2 fixtures).
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir_no_prd)"; OUT="$W/run.out"; ERR="$W/run.err"
make_fake_home "$H"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra "$RALPH_AFK" 2
[ $? -ne 0 ] || fail "case 7: should block"
grep -q "Queue would have been: 2 issues" "$ERR" || fail "case 7: queue count should be 2 — got: $(grep 'Queue' "$ERR")"
rm -rf "$H" "$W"

# ===========================================================================
# Issue 0008: dirty-tree gate
# ===========================================================================

# Workdir with PRD + git init + clean tree.
new_workdir_with_git_clean() {
  local w; w="$(new_workdir_with_prd)"
  ( cd "$w" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -q -m init )
  echo "$w"
}

# ---------------------------------------------------------------------------
# 8. Clean git tree → gate passes silently, loop runs.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir_with_git_clean)"; OUT="$W/run.out"; ERR="$W/run.err"
make_fake_home "$H"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra_no_confirm "$RALPH_AFK" 2
[ $? -eq 0 ] || fail "case 8: clean git tree should pass"
assert_match "$OUT" "iter 1/2 done"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 9. Dirty git tree (modified file) → blocked.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir_with_git_clean)"; OUT="$W/run.out"; ERR="$W/run.err"
make_fake_home "$H"
echo "modified" >> "$W/issues/0001-fake-feature-a.md"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra "$RALPH_AFK" 2
[ $? -ne 0 ] || fail "case 9: dirty tree should block"
assert_match "$ERR" "uncommitted changes"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 10. Staged-but-uncommitted changes → blocked.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir_with_git_clean)"; OUT="$W/run.out"; ERR="$W/run.err"
make_fake_home "$H"
echo "staged" >> "$W/issues/0001-fake-feature-a.md"
( cd "$W" && git add -A )
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra "$RALPH_AFK" 2
[ $? -ne 0 ] || fail "case 10: staged changes should block"
assert_match "$ERR" "uncommitted changes"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 11. Non-git workdir → skip with warning.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir_with_prd)"; OUT="$W/run.out"; ERR="$W/run.err"
make_fake_home "$H"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra_no_confirm "$RALPH_AFK" 2
[ $? -eq 0 ] || fail "case 11: non-git should pass with skip warning"
assert_match "$ERR" "git: not a repo"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 12. --allow-dirty waiver works on a dirty tree.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir_with_git_clean)"; OUT="$W/run.out"; ERR="$W/run.err"
make_fake_home "$H"
echo "modified" >> "$W/issues/0001-fake-feature-a.md"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra_no_confirm "$RALPH_AFK" 2 --allow-dirty
[ $? -eq 0 ] || fail "case 12: --allow-dirty should pass"
assert_match "$ERR" "dirty-tree check skipped"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 13. Multi-gate failure: no PRD AND dirty tree → punch list lists both.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir_no_prd)"; OUT="$W/run.out"; ERR="$W/run.err"
make_fake_home "$H"
( cd "$W" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -q -m init )
echo "dirty" >> "$W/issues/0001-fake-feature-a.md"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra "$RALPH_AFK" 2
[ $? -ne 0 ] || fail "case 13: multi-gate failure should block"
assert_match "$ERR" "no PRD found"
assert_match "$ERR" "uncommitted changes"
rm -rf "$H" "$W"

# ===========================================================================
# Issue 0009: dangerous-path gate
# ===========================================================================

# Make a workdir whose path contains a given keyword. Uses /tmp directly so
# the keyword is in $PWD.
new_workdir_named() {
  local keyword="$1"
  local w="/tmp/ralph-test-${keyword}-$$-$RANDOM"
  mkdir -p "$w/issues" "$w/docs/prd"
  cp "$ISSUE_FIX/"*.md "$w/issues/"
  echo "stub PRD content" > "$w/docs/prd/dummy.md"
  echo "$w"
}

# ---------------------------------------------------------------------------
# 14. Path containing 'auth' → block, name the keyword.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir_named auth-service)"; OUT="$W/run.out"; ERR="$W/run.err"
make_fake_home "$H"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra "$RALPH_AFK" 2
[ $? -ne 0 ] || fail "case 14: auth path should block"
assert_match "$ERR" "looks dangerous"
assert_match "$ERR" "auth"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 15. Path containing 'production' → block.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir_named production-cfg)"; OUT="$W/run.out"; ERR="$W/run.err"
make_fake_home "$H"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra "$RALPH_AFK" 2
[ $? -ne 0 ] || fail "case 15: production path should block"
assert_match "$ERR" "production"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 16. Safe path → gate passes.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir_named safe-feature)"; OUT="$W/run.out"; ERR="$W/run.err"
make_fake_home "$H"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra_no_confirm "$RALPH_AFK" 2
[ $? -eq 0 ] || fail "case 16: safe path should pass"
assert_match "$OUT" "iter 1/2 done"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 17. --i-know-this-is-dangerous waiver, includes would-have-matched keyword.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir_named auth-feature)"; OUT="$W/run.out"; ERR="$W/run.err"
make_fake_home "$H"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra_no_confirm "$RALPH_AFK" 2 --i-know-this-is-dangerous
[ $? -eq 0 ] || fail "case 17: --i-know-this-is-dangerous should pass"
assert_match "$ERR" "dangerous-path check skipped"
assert_match "$ERR" "auth"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 18. Case-insensitive matching: PRODUCTION, Production, production all match.
# ---------------------------------------------------------------------------
for variant in PRODUCTION Production production; do
  H="$(mktemp -d)"; W="$(new_workdir_named "$variant-cfg")"; OUT="$W/run.out"; ERR="$W/run.err"
  make_fake_home "$H"
  STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra "$RALPH_AFK" 2
  [ $? -ne 0 ] || fail "case 18/$variant: should block"
  assert_match "$ERR" "looks dangerous"
  rm -rf "$H" "$W"
done

# ---------------------------------------------------------------------------
# 19. Multi-gate: dangerous path + no PRD → both in punch list.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="/tmp/ralph-test-payment-$$-$RANDOM"; OUT="$W/run.out"; ERR="$W/run.err"
mkdir -p "$W/issues"
cp "$ISSUE_FIX/"*.md "$W/issues/"
make_fake_home "$H"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra "$RALPH_AFK" 2
[ $? -ne 0 ] || fail "case 19: multi-gate failure should block"
assert_match "$ERR" "no PRD found"
assert_match "$ERR" "looks dangerous"
rm -rf "$H" "$W"

# ===========================================================================
# Issue 0010: confirmation prompt + queue summary
# ===========================================================================

# ---------------------------------------------------------------------------
# 20. --no-confirm: queue prints to stdout, no prompt, loop runs.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir_with_prd)"; OUT="$W/run.out"; ERR="$W/run.err"
make_fake_home "$H"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra "$RALPH_AFK" 2 --no-confirm
[ $? -eq 0 ] || fail "case 20: --no-confirm should pass"
assert_match "$OUT" "Queue"
assert_match "$OUT" "0001 — Fake feature A"
grep -q "Proceed?" "$OUT" && fail "case 20: --no-confirm should suppress prompt"
assert_match "$OUT" "iter 1/2 done"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 21. /dev/null stdin without --no-confirm → abort.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir_with_prd)"; OUT="$W/run.out"; ERR="$W/run.err"
make_fake_home "$H"
( cd "$W" && HOME="$H" PATH="$STUBS:$PATH" STUB_FIXTURE="$COST_FIX/opus-simple.log" \
    "$RALPH_AFK" 2 </dev/null >"$OUT" 2>"$ERR" )
[ $? -ne 0 ] || fail "case 21: closed stdin without --no-confirm should abort"
assert_match "$ERR" "aborted at confirmation prompt"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 22. y/Y/yes/YES on stdin all proceed.
# ---------------------------------------------------------------------------
for ans in y Y yes YES Yes; do
  H="$(mktemp -d)"; W="$(new_workdir_with_prd)"; OUT="$W/run.out"; ERR="$W/run.err"
  make_fake_home "$H"
  ( cd "$W" && HOME="$H" PATH="$STUBS:$PATH" STUB_FIXTURE="$COST_FIX/opus-simple.log" \
      bash -c "echo $ans | '$RALPH_AFK' 2" >"$OUT" 2>"$ERR" )
  [ $? -eq 0 ] || fail "case 22/$ans: should proceed"
  assert_match "$OUT" "iter 1/2 done"
  rm -rf "$H" "$W"
done

# ---------------------------------------------------------------------------
# 23. Anything else aborts (n, no, garbage, empty).
# ---------------------------------------------------------------------------
for ans in n no q garbage ""; do
  H="$(mktemp -d)"; W="$(new_workdir_with_prd)"; OUT="$W/run.out"; ERR="$W/run.err"
  make_fake_home "$H"
  ( cd "$W" && HOME="$H" PATH="$STUBS:$PATH" STUB_FIXTURE="$COST_FIX/opus-simple.log" \
      bash -c "echo '$ans' | '$RALPH_AFK' 2" >"$OUT" 2>"$ERR" )
  [ $? -ne 0 ] || fail "case 23/$ans: should abort"
  assert_match "$ERR" "aborted at confirmation prompt"
  rm -rf "$H" "$W"
done

# ---------------------------------------------------------------------------
# 24. Queue summary lists ids + titles in dependency order.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir_with_prd)"; OUT="$W/run.out"; ERR="$W/run.err"
make_fake_home "$H"
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra "$RALPH_AFK" 2 --no-confirm
[ $? -eq 0 ] || fail "case 24: nonzero exit"
# Both fixture issues should appear, in 0001-then-0002 order.
line1=$(grep -nE '0001 — Fake feature A' "$OUT" | head -1 | cut -d: -f1)
line2=$(grep -nE '0002 — Fake feature B' "$OUT" | head -1 | cut -d: -f1)
[ -n "$line1" ] && [ -n "$line2" ] && [ "$line1" -lt "$line2" ] \
  || fail "case 24: expected 0001 before 0002 — got '$line1' / '$line2'"
rm -rf "$H" "$W"

# ---------------------------------------------------------------------------
# 25. Zero queued issues: queue line says "nothing to do", no prompt, clean exit.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; W="$(new_workdir_with_prd)"; OUT="$W/run.out"; ERR="$W/run.err"
make_fake_home "$H"
# Mark all fixture issues done so the queue is empty.
for f in "$W/issues/"*.md; do sed -i.bak 's/^status: open/status: done/' "$f"; done; rm -f "$W/issues/"*.bak
STUB_FIXTURE="$COST_FIX/opus-simple.log" run_ra "$RALPH_AFK" 2
[ $? -eq 0 ] || fail "case 25: empty queue should exit cleanly"
assert_match "$OUT" "nothing to do"
grep -q "Proceed?" "$OUT" && fail "case 25: empty queue should not prompt"
rm -rf "$H" "$W"

echo "guardrails tests ok"
