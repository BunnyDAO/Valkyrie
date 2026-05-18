#!/usr/bin/env bash
# test-valk-land.sh — issue 0019. valk-land lands a finished valk/<name>
# branch onto origin/main via the local path (rebase → ff → push) in the
# REAL topology: valk/<name> checked out in a LINKED WORKTREE, valk-land run
# from the MAIN checkout, origin/main moved underneath. Observable git /
# filesystem / exit only — never internals.
set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO_ROOT:-$(dirname "$TEST_DIR")}"
VL="$REPO/scripts/valk-land"

[ -x "$VL" ] || { echo "FAIL: valk-land missing/not exec at $VL"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
gitc() { git -C "$1" -c user.email=t@t.t -c user.name=t "${@:2}"; }

# --- simulated origin (bare clone) + a main checkout cloned from it ---
SEED="$WORK/seed"; mkdir -p "$SEED"
gitc "$SEED" init -q
echo base > "$SEED/file.txt"
gitc "$SEED" add -A && gitc "$SEED" commit -qm base
gitc "$SEED" branch -M main
ORIGIN="$WORK/origin.git"
git clone -q --bare "$SEED" "$ORIGIN"
MAIN="$WORK/proj"
git clone -q "$ORIGIN" "$MAIN"

# --- a finished valk/feat branch, checked out in a LINKED worktree ---
gitc "$MAIN" branch valk/feat
gitc "$MAIN" worktree add -q "$WORK/proj-feat" valk/feat
WT="$WORK/proj-feat"
echo feature > "$WT/feature.txt"
gitc "$WT" add -A && gitc "$WT" commit -qm "feat: add feature"

# --- origin/main advances independently (non-conflicting concurrent work) ---
OTHER="$WORK/other"
git clone -q "$ORIGIN" "$OTHER"
echo other > "$OTHER/other.txt"
gitc "$OTHER" add -A && gitc "$OTHER" commit -qm "other: concurrent work"
gitc "$OTHER" push -q origin main

# --- land it from the MAIN checkout ---
( cd "$MAIN" && "$VL" feat ) || fail "valk-land feat exited non-zero"

gitc "$MAIN" fetch -q origin
LOG="$(gitc "$MAIN" log --format=%s origin/main)"
printf '%s\n' "$LOG" | grep -q "feat: add feature"   || fail "origin/main missing the landed feature commit"
printf '%s\n' "$LOG" | grep -q "other: concurrent work" || fail "origin/main lost the concurrent commit"
[ -z "$(gitc "$MAIN" log --merges --format=%H origin/main)" ] \
  || fail "history is not linear (merge commit present)"
[ "$(gitc "$MAIN" rev-parse main)" = "$(gitc "$MAIN" rev-parse origin/main)" ] \
  || fail "local main not fast-forwarded to origin/main"

echo "ok: valk-land lands a worktree's valk/<name> onto origin/main — linear, ff, pushed"
exit 0
