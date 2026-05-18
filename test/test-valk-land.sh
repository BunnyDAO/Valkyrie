#!/usr/bin/env bash
# test-valk-land.sh — issues 0019, 0020. valk-land lands a finished
# valk/<name> branch (checked out in a LINKED WORKTREE) onto origin/main via
# the local path, run from the MAIN checkout. Observable git / filesystem /
# exit only — never internals.
set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO_ROOT:-$(dirname "$TEST_DIR")}"
VL="$REPO/scripts/valk-land"

[ -x "$VL" ] || { echo "FAIL: valk-land missing/not exec at $VL"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
gitc() { git -C "$1" -c user.email=t@t.t -c user.name=t "${@:2}"; }

# Fresh fixture in $WORK/<tag>: bare origin, a main checkout, a valk/feat
# branch checked out in a linked worktree (one commit), and origin/main
# advanced by an independent non-conflicting commit. Sets F_MAIN F_WT
# F_ORIGIN.
mkfixture() {
  local d="$WORK/$1"
  local seed="$d/seed" origin="$d/origin.git" main="$d/proj"
  local wt="$d/proj-feat" other="$d/other"
  mkdir -p "$seed"
  gitc "$seed" init -q
  echo base > "$seed/file.txt"; gitc "$seed" add -A; gitc "$seed" commit -qm base
  gitc "$seed" branch -M main
  git clone -q --bare "$seed" "$origin"
  git clone -q "$origin" "$main"
  gitc "$main" branch valk/feat
  gitc "$main" worktree add -q "$wt" valk/feat
  echo feature > "$wt/feature.txt"
  gitc "$wt" add -A; gitc "$wt" commit -qm "feat: add feature"
  git clone -q "$origin" "$other"
  echo other > "$other/other.txt"
  gitc "$other" add -A; gitc "$other" commit -qm "other: concurrent work"
  gitc "$other" push -q origin main
  F_MAIN="$main"; F_WT="$wt"; F_ORIGIN="$origin"
}

# --- 0019: clean local land in the worktree topology ---
mkfixture s19
# no test_skill in these push/rebase scenarios → --force skips the gate
# (the gate itself is exercised by the 0022* cases below)
( cd "$F_MAIN" && "$VL" feat --force ) || fail "0019: valk-land feat exited non-zero"
gitc "$F_MAIN" fetch -q origin
L="$(gitc "$F_MAIN" log --format=%s origin/main)"
printf '%s\n' "$L" | grep -q "feat: add feature"     || fail "0019: origin/main missing feature commit"
printf '%s\n' "$L" | grep -q "other: concurrent work" || fail "0019: origin/main lost concurrent commit"
[ -z "$(gitc "$F_MAIN" log --merges --format=%H origin/main)" ] || fail "0019: history not linear"
[ "$(gitc "$F_MAIN" rev-parse main)" = "$(gitc "$F_MAIN" rev-parse origin/main)" ] \
  || fail "0019: local main not fast-forwarded to origin/main"
echo "ok: 0019 — clean local land (worktree topology): linear, ff, pushed"

# --- 0020a: --no-push lands locally, origin provably untouched ---
mkfixture s20a
o_before="$(git -C "$F_ORIGIN" rev-parse main)"
( cd "$F_MAIN" && "$VL" feat --no-push --force ) || fail "0020a: --no-push exited non-zero"
gitc "$F_MAIN" log --format=%s main | grep -q "feat: add feature" \
  || fail "0020a: --no-push did not advance local main"
[ "$(git -C "$F_ORIGIN" rev-parse main)" = "$o_before" ] \
  || fail "0020a: --no-push must NOT touch origin"
echo "ok: 0020 --no-push — lands locally, origin untouched"

# --- 0020b: origin moved under us (push rejected) → abort, preserve, re-run ---
mkfixture s20b
# Simulate a concurrent flow having won the race: origin rejects the push.
mkdir -p "$F_ORIGIN/hooks"
printf '#!/bin/sh\necho "remote: main moved (concurrent land)" >&2\nexit 1\n' \
  > "$F_ORIGIN/hooks/pre-receive"
chmod +x "$F_ORIGIN/hooks/pre-receive"
o_before="$(git -C "$F_ORIGIN" rev-parse main)"
m_before="$(gitc "$F_MAIN" rev-parse main)"
out="$( cd "$F_MAIN" && "$VL" feat --force 2>&1 )"; rc=$?
[ "$rc" -ne 0 ] || fail "0020b: a rejected push must make valk-land exit non-zero"
[ "$(git -C "$F_ORIGIN" rev-parse main)" = "$o_before" ] \
  || fail "0020b: origin/main must keep the concurrent work (no force-push)"
printf '%s' "$out" | grep -qiE 're-?run|try again' \
  || fail "0020b: missing re-run guidance (got: $out)"
gitc "$F_WT" log --format=%s valk/feat | grep -q "feat: add feature" \
  || fail "0020b: valk/feat lost its work — not preserved"
[ "$(gitc "$F_MAIN" rev-parse main)" = "$m_before" ] \
  || fail "0020b: local main not restored after the refused push"
echo "ok: 0020 origin-moved — abort, preserve branch+main, re-run; never force"

# --- 0021: rebase conflict → abort clean, byte-untouched, precise guidance --
mkfixture s21
echo "feat side"  > "$F_WT/file.txt"          # valk/feat edits the shared file
gitc "$F_WT" add -A; gitc "$F_WT" commit -qm "feat: edit shared file"
oc="$WORK/s21/oclone"; git clone -q "$F_ORIGIN" "$oc"
echo "main side" > "$oc/file.txt"             # origin/main edits it differently
gitc "$oc" add -A; gitc "$oc" commit -qm "main: edit shared file"
gitc "$oc" push -q origin main
b_before="$(gitc "$F_WT" rev-parse valk/feat)"
o_before="$(git -C "$F_ORIGIN" rev-parse main)"
out="$( cd "$F_MAIN" && "$VL" feat 2>&1 )"; rc=$?
[ "$rc" -ne 0 ] || fail "0021: a conflict must make valk-land exit non-zero"
[ "$(gitc "$F_WT" rev-parse valk/feat)" = "$b_before" ] \
  || fail "0021: valk/feat not byte-unchanged (rebase not aborted)"
[ "$(git -C "$F_WT" symbolic-ref --short -q HEAD)" = "valk/feat" ] \
  || fail "0021: worktree left detached / mid-rebase (not aborted cleanly)"
git -C "$F_WT" status --porcelain | grep -q '^UU' \
  && fail "0021: conflict markers left in the worktree"
[ "$(cat "$F_WT/file.txt")" = "feat side" ] \
  || fail "0021: worktree file not restored to pre-call content"
[ "$(git -C "$F_ORIGIN" rev-parse main)" = "$o_before" ] \
  || fail "0021: origin modified during a conflicting land"
printf '%s' "$out" | grep -qF "$F_WT"        || fail "0021: guidance must name the worktree"
printf '%s' "$out" | grep -qE '(^|[^a-z])cd ' || fail "0021: guidance must give the explicit cd step"
printf '%s' "$out" | grep -q 'git rebase'    || fail "0021: guidance must give the rebase command"
printf '%s' "$out" | grep -q 'valk-land feat' || fail "0021: guidance must say to re-run valk-land"
echo "ok: 0021 conflict — abort clean, byte-untouched, precise guidance, no push"

# --- 0022b: configured test_skill FAILS → abort, nothing pushed ---
mkfixture s22b
mkdir -p "$F_MAIN/.claude"
printf -- '---\ntest_skill: vgate\n---\n' > "$F_MAIN/.claude/valk-config.md"
BIN="$WORK/s22b/bin"; mkdir -p "$BIN"
printf '#!/bin/sh\nexit 1\n' > "$BIN/vgate"; chmod +x "$BIN/vgate"
o_before="$(git -C "$F_ORIGIN" rev-parse main)"
m_before="$(gitc "$F_MAIN" rev-parse main)"
out="$( cd "$F_MAIN" && PATH="$BIN:$PATH" "$VL" feat 2>&1 )"; rc=$?
[ "$rc" -ne 0 ] || fail "0022b: a failing test_skill must make valk-land exit non-zero"
[ "$(git -C "$F_ORIGIN" rev-parse main)" = "$o_before" ] \
  || fail "0022b: nothing must be pushed when the gate is red"
[ "$(gitc "$F_MAIN" rev-parse main)" = "$m_before" ] \
  || fail "0022b: local main must not advance when the gate is red"
gitc "$F_WT" log --format=%s valk/feat | grep -q "feat: add feature" \
  || fail "0022b: valk/feat work lost"
printf '%s' "$out" | grep -qiE 'test|gate|verif' \
  || fail "0022b: message should explain the gate failed (got: $out)"
echo "ok: 0022 test gate red — abort, nothing pushed, work preserved"

# --- 0022c: no test signal + no --force → refuse to land ---
mkfixture s22c
o_before="$(git -C "$F_ORIGIN" rev-parse main)"
out="$( cd "$F_MAIN" && "$VL" feat 2>&1 )"; rc=$?
[ "$rc" -ne 0 ] || fail "0022c: no test signal without --force must refuse (non-zero)"
[ "$(git -C "$F_ORIGIN" rev-parse main)" = "$o_before" ] \
  || fail "0022c: refused land must not push"
printf '%s' "$out" | grep -qF -- '--force' \
  || fail "0022c: refusal must tell the user about --force (got: $out)"
echo "ok: 0022 no-signal — refuses without --force"

# --- 0022d: no test signal + --force → lands with a loud warning ---
mkfixture s22d
out="$( cd "$F_MAIN" && "$VL" feat --force 2>&1 )" || fail "0022d: --force must land despite no signal"
gitc "$F_MAIN" fetch -q origin
gitc "$F_MAIN" log --format=%s origin/main | grep -q "feat: add feature" \
  || fail "0022d: --force did not land the work"
printf '%s' "$out" | grep -qiE 'unverified|no test|warn' \
  || fail "0022d: --force land must warn loudly it is unverified (got: $out)"
echo "ok: 0022 no-signal + --force — lands with a loud unverified warning"

# --- 0022a: configured test_skill that PASSES → land completes ---
mkfixture s22a
mkdir -p "$F_MAIN/.claude"
printf -- '---\ntest_skill: vgate\n---\n' > "$F_MAIN/.claude/valk-config.md"
BIN="$WORK/s22a/bin"; mkdir -p "$BIN"
printf '#!/bin/sh\nexit 0\n' > "$BIN/vgate"; chmod +x "$BIN/vgate"
( cd "$F_MAIN" && PATH="$BIN:$PATH" "$VL" feat ) || fail "0022a: passing gate must land"
gitc "$F_MAIN" fetch -q origin
gitc "$F_MAIN" log --format=%s origin/main | grep -q "feat: add feature" \
  || fail "0022a: passing gate did not land the work"
echo "ok: 0022 test gate green — land completes"

exit 0
