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
  local def="${2:-main}"            # default branch name (issue 0028)
  local seed="$d/seed" origin="$d/origin.git" main="$d/proj"
  local wt="$d/proj-feat" other="$d/other"
  mkdir -p "$seed"
  gitc "$seed" init -q
  echo base > "$seed/file.txt"; gitc "$seed" add -A; gitc "$seed" commit -qm base
  gitc "$seed" branch -M "$def"
  git clone -q --bare "$seed" "$origin"
  git clone -q "$origin" "$main"
  gitc "$main" branch valk/feat
  gitc "$main" worktree add -q "$wt" valk/feat
  echo feature > "$wt/feature.txt"
  gitc "$wt" add -A; gitc "$wt" commit -qm "feat: add feature"
  git clone -q "$origin" "$other"
  echo other > "$other/other.txt"
  gitc "$other" add -A; gitc "$other" commit -qm "other: concurrent work"
  gitc "$other" push -q origin "$def"
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

# --- 0023a: pr_skill configured + installed → delegate, no local land ---
mkfixture s23a
SBX="$WORK/s23a/home"; mkdir -p "$SBX/.claude/skills/to-fake-pr"
: > "$SBX/.claude/skills/to-fake-pr/SKILL.md"
mkdir -p "$F_MAIN/.claude"
printf -- '---\npr_skill: to-fake-pr\n---\n' > "$F_MAIN/.claude/valk-config.md"
o_before="$(git -C "$F_ORIGIN" rev-parse main)"
m_before="$(gitc "$F_MAIN" rev-parse main)"
b_before="$(gitc "$F_WT" rev-parse valk/feat)"
out="$( cd "$F_MAIN" && HOME="$SBX" "$VL" feat 2>&1 )"; rc=$?
[ "$rc" -eq 0 ] || fail "0023a: delegation should exit 0 (got $rc: $out)"
[ "$(git -C "$F_ORIGIN" rev-parse main)" = "$o_before" ] \
  || fail "0023a: valk-land must not push when delegating to pr_skill"
[ "$(gitc "$F_MAIN" rev-parse main)" = "$m_before" ] \
  || fail "0023a: valk-land must not ff local main when delegating"
[ "$(gitc "$F_WT" rev-parse valk/feat)" = "$b_before" ] \
  || fail "0023a: valk-land must not rebase when delegating"
printf '%s' "$out" | grep -q "to-fake-pr" \
  || fail "0023a: should name the pr_skill it delegates to (got: $out)"
echo "ok: 0023 pr_skill installed — delegates, no local land/push"

# --- 0023b: pr_skill configured but NOT installed → STOP, change nothing ---
mkfixture s23b
SBX="$WORK/s23b/home"; mkdir -p "$SBX/.claude"   # no skills/to-fake-pr
mkdir -p "$F_MAIN/.claude"
printf -- '---\npr_skill: to-fake-pr\n---\n' > "$F_MAIN/.claude/valk-config.md"
o_before="$(git -C "$F_ORIGIN" rev-parse main)"
m_before="$(gitc "$F_MAIN" rev-parse main)"
out="$( cd "$F_MAIN" && HOME="$SBX" "$VL" feat 2>&1 )"; rc=$?
[ "$rc" -ne 0 ] || fail "0023b: pr_skill not installed must STOP (non-zero)"
[ "$(git -C "$F_ORIGIN" rev-parse main)" = "$o_before" ] \
  || fail "0023b: STOP must change nothing (origin)"
[ "$(gitc "$F_MAIN" rev-parse main)" = "$m_before" ] \
  || fail "0023b: STOP must change nothing (local main)"
printf '%s' "$out" | grep -q "to-fake-pr" \
  || fail "0023b: error should name the missing pr_skill"
printf '%s' "$out" | grep -qiE 'not installed|install' \
  || fail "0023b: error should say it is not installed"
echo "ok: 0023 pr_skill configured but not installed — STOP, change nothing"

# --- 0024a: default green land removes nothing, prints the remove hint ---
mkfixture s24a
out="$( cd "$F_MAIN" && "$VL" feat --force 2>&1 )" || fail "0024a: land should succeed"
[ -d "$F_WT" ] || fail "0024a: default land must NOT remove the worktree"
gitc "$F_MAIN" rev-parse --verify -q valk/feat >/dev/null \
  || fail "0024a: default land must NOT drop the branch"
printf '%s' "$out" | grep -qF "valk-worktree --remove feat" \
  || fail "0024a: default land must print the exact remove hint (got: $out)"
echo "ok: 0024 default — keeps worktree, prints exact remove hint"

# --- 0024b: --clean tears down the worktree + merged branch ---
mkfixture s24b
( cd "$F_MAIN" && "$VL" feat --force --clean ) || fail "0024b: --clean land should succeed"
gitc "$F_MAIN" fetch -q origin
gitc "$F_MAIN" log --format=%s origin/main | grep -q "feat: add feature" \
  || fail "0024b: --clean must still land the work first"
[ ! -d "$F_WT" ] || fail "0024b: --clean must remove the worktree"
gitc "$F_MAIN" rev-parse --verify -q valk/feat >/dev/null \
  && fail "0024b: --clean must drop the merged valk/feat branch"
echo "ok: 0024 --clean — lands then tears down worktree + merged branch"

# --- 0024c: --clean from inside the target worktree refuses, removes nothing ---
mkfixture s24c
out="$( cd "$F_WT" && "$VL" feat --force --clean 2>&1 )"; rc=$?
[ "$rc" -ne 0 ] || fail "0024c: --clean from inside the worktree must refuse (non-zero)"
[ -d "$F_WT" ] || fail "0024c: refusal must not remove the worktree"
printf '%s' "$out" | grep -qi "main checkout" \
  || fail "0024c: refusal should tell the user to run from the main checkout"
echo "ok: 0024 --clean from inside worktree — refuses, removes nothing"

# --- 0024d: --clean does nothing destructive if the land did not succeed ---
mkfixture s24d   # no test_skill, no --force → gate refuses before landing
out="$( cd "$F_MAIN" && "$VL" feat --clean 2>&1 )"; rc=$?
[ "$rc" -ne 0 ] || fail "0024d: failed land must be non-zero"
[ -d "$F_WT" ] || fail "0024d: failed land must not have removed the worktree"
gitc "$F_MAIN" rev-parse --verify -q valk/feat >/dev/null \
  || fail "0024d: failed land must not have dropped the branch"
echo "ok: 0024 --clean + failed land — nothing destructive"

# --- 0025: installer PATH-registers valk-land, like afk/valk-worktree ---
# Sandbox HOME so a *global* install is fully isolated (temp ~/.claude AND
# temp ~/.local/bin) — the dev machine is never mutated.
SBX="$WORK/inst-home"; mkdir -p "$SBX"
HOME="$SBX" bash "$REPO/install.sh" >/dev/null 2>&1 \
  || fail "0025: install.sh (global, sandboxed HOME) exited non-zero"
[ -L "$SBX/.local/bin/valk-land" ] \
  || fail "0025: install.sh did not PATH-symlink valk-land"
[ "$(readlink "$SBX/.local/bin/valk-land")" = "$REPO/scripts/valk-land" ] \
  || fail "0025: valk-land symlink does not point at scripts/valk-land"
[ -L "$SBX/.local/bin/valk-worktree" ] \
  || fail "0025: regression — valk-worktree no longer PATH-registered"
[ -L "$SBX/.local/bin/afk" ] \
  || fail "0025: regression — afk no longer PATH-registered"
echo "ok: 0025 installer PATH-registers valk-land (afk + valk-worktree intact)"

# --- 0028a: a master-default repo lands (default branch resolved, not assumed) ---
mkfixture s28a master
( cd "$F_MAIN" && "$VL" feat --force ) || fail "0028a: valk-land on a master-default repo exited non-zero"
gitc "$F_MAIN" fetch -q origin
L="$(gitc "$F_MAIN" log --format=%s origin/master)"
printf '%s\n' "$L" | grep -q "feat: add feature"     || fail "0028a: origin/master missing feature commit"
printf '%s\n' "$L" | grep -q "other: concurrent work" || fail "0028a: origin/master lost concurrent commit"
[ -z "$(gitc "$F_MAIN" log --merges --format=%H origin/master)" ] || fail "0028a: history not linear"
[ "$(gitc "$F_MAIN" rev-parse master)" = "$(gitc "$F_MAIN" rev-parse origin/master)" ] \
  || fail "0028a: local master not fast-forwarded to origin/master"
echo "ok: 0028 — master-default repo lands (resolved default branch, linear, ff, pushed)"

# --- 0028b: origin/HEAD genuinely unresolvable (bad remote HEAD; git fetch
#     cannot derive it) → abort + set-head hint, nothing touched. Inlined
#     because mkfixture presumes a valid default branch. ---
d28="$WORK/s28b"; s="$d28/seed"; og="$d28/origin.git"; mn="$d28/proj"; w="$d28/proj-feat"
mkdir -p "$s"
gitc "$s" init -q
echo base > "$s/file.txt"; gitc "$s" add -A; gitc "$s" commit -qm base
gitc "$s" branch -M master
git clone -q --bare "$s" "$og"
git -C "$og" symbolic-ref HEAD refs/heads/nonexistent   # remote HEAD invalid → origin/HEAD unresolvable
git clone -q "$og" "$mn" 2>/dev/null
gitc "$mn" fetch -q origin
gitc "$mn" branch master origin/master
gitc "$mn" checkout -q master
gitc "$mn" branch valk/feat
gitc "$mn" worktree add -q "$w" valk/feat
echo feature > "$w/feature.txt"; gitc "$w" add -A; gitc "$w" commit -qm "feat: add feature"
o_before="$(git -C "$og" rev-parse master)"
m_before="$(gitc "$mn" rev-parse master)"
b_before="$(gitc "$w" rev-parse valk/feat)"
out="$( cd "$mn" && "$VL" feat --force 2>&1 )"; rc=$?
[ "$rc" -ne 0 ] || fail "0028b: unresolvable origin/HEAD must exit non-zero (got: $out)"
[ "$(git -C "$og" rev-parse master)" = "$o_before" ] || fail "0028b: origin must be untouched"
[ "$(gitc "$mn" rev-parse master)" = "$m_before" ] || fail "0028b: local must be untouched"
[ "$(gitc "$w" rev-parse valk/feat)" = "$b_before" ] || fail "0028b: valk/feat must be preserved"
printf '%s' "$out" | grep -q 'set-head' \
  || fail "0028b: hint must name 'git remote set-head origin -a' (got: $out)"
echo "ok: 0028 unresolvable origin/HEAD — abort, preserve, set-head hint"

# --- 0029a: --base lets a genuinely-unresolvable-origin/HEAD repo land ---
d29="$WORK/s29a"; s="$d29/seed"; og="$d29/origin.git"; mn="$d29/proj"; w="$d29/proj-feat"; ot="$d29/other"
mkdir -p "$s"
gitc "$s" init -q
echo base > "$s/file.txt"; gitc "$s" add -A; gitc "$s" commit -qm base
gitc "$s" branch -M master
git clone -q --bare "$s" "$og"
git -C "$og" symbolic-ref HEAD refs/heads/nonexistent       # origin/HEAD unresolvable
git clone -q "$og" "$mn" 2>/dev/null
gitc "$mn" fetch -q origin
gitc "$mn" branch master origin/master
gitc "$mn" checkout -q master
gitc "$mn" branch valk/feat
gitc "$mn" worktree add -q "$w" valk/feat
echo feature > "$w/feature.txt"; gitc "$w" add -A; gitc "$w" commit -qm "feat: add feature"
git clone -q "$og" "$ot" 2>/dev/null
gitc "$ot" fetch -q origin; gitc "$ot" checkout -q -B master origin/master
echo other > "$ot/other.txt"; gitc "$ot" add -A; gitc "$ot" commit -qm "other: concurrent work"
gitc "$ot" push -q origin master
( cd "$mn" && "$VL" feat --base master --force ) \
  || fail "0029a: --base master must let an unresolvable-origin/HEAD repo land"
gitc "$mn" fetch -q origin
L="$(gitc "$mn" log --format=%s origin/master)"
printf '%s\n' "$L" | grep -q "feat: add feature"     || fail "0029a: origin/master missing feature commit"
printf '%s\n' "$L" | grep -q "other: concurrent work" || fail "0029a: origin/master lost concurrent commit"
[ -z "$(gitc "$mn" log --merges --format=%H origin/master)" ] || fail "0029a: history not linear"
echo "ok: 0029 --base — unresolvable origin/HEAD repo lands via --base"

# --- 0029c: unresolved + no --base → abort, hint names BOTH remedies ---
d29c="$WORK/s29c"; s="$d29c/seed"; og="$d29c/origin.git"; mn="$d29c/proj"; w="$d29c/proj-feat"
mkdir -p "$s"
gitc "$s" init -q
echo base > "$s/file.txt"; gitc "$s" add -A; gitc "$s" commit -qm base
gitc "$s" branch -M master
git clone -q --bare "$s" "$og"
git -C "$og" symbolic-ref HEAD refs/heads/nonexistent
git clone -q "$og" "$mn" 2>/dev/null
gitc "$mn" fetch -q origin
gitc "$mn" branch master origin/master
gitc "$mn" checkout -q master
gitc "$mn" branch valk/feat
gitc "$mn" worktree add -q "$w" valk/feat
echo feature > "$w/feature.txt"; gitc "$w" add -A; gitc "$w" commit -qm "feat: add feature"
o_before="$(git -C "$og" rev-parse master)"
out="$( cd "$mn" && "$VL" feat --force 2>&1 )"; rc=$?
[ "$rc" -ne 0 ] || fail "0029c: unresolved + no --base must exit non-zero"
[ "$(git -C "$og" rev-parse master)" = "$o_before" ] || fail "0029c: origin must be untouched"
printf '%s' "$out" | grep -q 'set-head'    || fail "0029c: hint must still name set-head (got: $out)"
printf '%s' "$out" | grep -q -- '--base'   || fail "0029c: hint must also name --base (got: $out)"
echo "ok: 0029 unresolved + no --base — hint names both remedies"

# --- 0029b: --base is honored even when origin/HEAD is resolvable ---
mkfixture s29b            # normal main-default repo (origin/HEAD resolvable)
( cd "$F_MAIN" && "$VL" feat --base main --force ) \
  || fail "0029b: explicit --base main must land on a normal repo"
gitc "$F_MAIN" fetch -q origin
L="$(gitc "$F_MAIN" log --format=%s origin/main)"
printf '%s\n' "$L" | grep -q "feat: add feature"     || fail "0029b: origin/main missing feature"
printf '%s\n' "$L" | grep -q "other: concurrent work" || fail "0029b: origin/main lost concurrent"
echo "ok: 0029 --base honored even when origin/HEAD resolvable"

# --- 0029d: parser regression — --base needs a value; old errors intact ---
mkfixture s29d
out="$( cd "$F_MAIN" && "$VL" feat --base 2>&1 )"; rc=$?
[ "$rc" -ne 0 ] || fail "0029d: --base with no value must exit non-zero"
printf '%s' "$out" | grep -qi 'branch name' || fail "0029d: --base error should say it needs a branch name (got: $out)"
out="$( cd "$F_MAIN" && "$VL" feat --bogus 2>&1 )"; rc=$?
[ "$rc" -ne 0 ] || fail "0029d: unknown option must still exit non-zero"
printf '%s' "$out" | grep -q 'unknown option' || fail "0029d: unknown-option message regressed (got: $out)"
out="$( cd "$F_MAIN" && "$VL" feat extra 2>&1 )"; rc=$?
[ "$rc" -ne 0 ] || fail "0029d: a 2nd positional must still exit non-zero"
printf '%s' "$out" | grep -q 'unexpected argument' || fail "0029d: unexpected-argument message regressed (got: $out)"
echo "ok: 0029 parser — --base needs value; unknown-option & 2nd-positional intact"

exit 0
