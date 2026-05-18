#!/usr/bin/env bash
#
# test-valk-worktree.sh — issue 0013. valk-worktree is the cure for
# concurrent Valkyrie flows on one project: one command → an isolated git
# worktree+branch per terminal. Behavior is observed via git/filesystem
# only (never internals); the helper is language-agnostic and works with no
# consumer hook present (standalone).

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO_ROOT:-$(dirname "$TEST_DIR")}"
VWT="$REPO/scripts/valk-worktree"

[ -x "$VWT" ] || { echo "FAIL: valk-worktree missing/not exec at $VWT"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

# A throwaway git repo with one commit (worktree add needs a HEAD).
mkproj() {
  local p="$WORK/$1"
  mkdir -p "$p"
  git -C "$p" init -q
  git -C "$p" config user.email t@t.t
  git -C "$p" config user.name t
  echo seed > "$p/seed.txt"
  git -C "$p" add -A && git -C "$p" commit -qm seed
  echo "$p"
}

# --- create: makes a linked worktree dir + valk/<name> branch ---
P="$(mkproj proj)"
( cd "$P" && "$VWT" wt1 ) >/dev/null 2>&1 || fail "valk-worktree wt1 exited non-zero"

WT="$WORK/proj-wt1"
[ -d "$WT" ] || fail "expected worktree dir $WT to exist"
git -C "$P" worktree list | grep -q "proj-wt1" \
  || fail "git worktree list does not show proj-wt1"
git -C "$P" branch --list valk/wt1 | grep -q valk/wt1 \
  || fail "branch valk/wt1 was not created"
[ "$(git -C "$WT" rev-parse --abbrev-ref HEAD)" = "valk/wt1" ] \
  || fail "worktree is not on branch valk/wt1"

# --- runs an executable .valk-worktree-setup, cwd = the new worktree root ---
P2="$(mkproj proj2)"
cat > "$P2/.valk-worktree-setup" <<'EOF'
#!/usr/bin/env bash
echo "ran in $(pwd)" > .valk-setup-sentinel
EOF
chmod +x "$P2/.valk-worktree-setup"
( cd "$P2" && "$VWT" wt1 ) >/dev/null 2>&1 || fail "create with hook exited non-zero"
[ -f "$WORK/proj2-wt1/.valk-setup-sentinel" ] \
  || fail ".valk-worktree-setup did not run in the new worktree"

# --- standalone: a NON-executable hook must NOT run; create still succeeds ---
P3="$(mkproj proj3)"
echo 'echo NOPE > should-not-exist' > "$P3/.valk-worktree-setup"  # not +x
( cd "$P3" && "$VWT" wt1 ) >/dev/null 2>&1 || fail "create w/o exec hook non-zero"
[ -d "$WORK/proj3-wt1" ] || fail "worktree not created when hook non-executable"
[ ! -f "$WORK/proj3-wt1/should-not-exist" ] \
  || fail "non-executable .valk-worktree-setup must NOT run"

# --- idempotent: re-running for an existing worktree is a safe no-op ---
P4="$(mkproj proj4)"
( cd "$P4" && "$VWT" wt1 ) >/dev/null 2>&1 || fail "first create non-zero"
out="$( cd "$P4" && "$VWT" wt1 2>&1 )"; rc=$?
[ "$rc" -eq 0 ] || fail "re-run for existing worktree must exit 0 (got $rc)"
printf '%s' "$out" | grep -qi "exist" \
  || fail "re-run should report it already exists (got: $out)"

# --- --remove tears down the worktree and drops the merged branch ---
P5="$(mkproj proj5)"
( cd "$P5" && "$VWT" wt1 ) >/dev/null 2>&1 || fail "create non-zero"
[ -d "$WORK/proj5-wt1" ] || fail "precondition: worktree should exist"
( cd "$P5" && "$VWT" --remove wt1 ) >/dev/null 2>&1 || fail "--remove exited non-zero"
[ ! -d "$WORK/proj5-wt1" ] || fail "--remove did not remove the worktree dir"
git -C "$P5" worktree list | grep -q "proj5-wt1" \
  && fail "--remove left a registered worktree"
git -C "$P5" branch --list valk/wt1 | grep -q valk/wt1 \
  && fail "--remove did not drop the merged valk/wt1 branch"

# --- --remove of a non-existent name is safe/clear, not a crash ---
( cd "$P5" && "$VWT" --remove nope ) >/dev/null 2>&1 \
  || fail "--remove of a non-existent worktree should exit 0"

# --- the installer PATH-registers valk-worktree, exactly like afk ----------
# Sandbox HOME so a *global* install is fully isolated: temp ~/.claude AND
# temp ~/.local/bin — the dev machine is never touched.
SBX="$WORK/home"; mkdir -p "$SBX"
HOME="$SBX" bash "$REPO/install.sh" >/dev/null 2>&1 \
  || fail "install.sh (global, sandboxed HOME) exited non-zero"
[ -L "$SBX/.local/bin/valk-worktree" ] \
  || fail "install.sh did not PATH-symlink valk-worktree into ~/.local/bin"
[ "$(readlink "$SBX/.local/bin/valk-worktree")" = "$REPO/scripts/valk-worktree" ] \
  || fail "valk-worktree symlink does not point at scripts/valk-worktree"
[ -L "$SBX/.local/bin/afk" ] \
  || fail "install.sh regression: afk no longer PATH-registered"

echo "ok: valk-worktree <name> creates an isolated worktree + valk/<name> branch"
echo "ok: runs an executable .valk-worktree-setup (cwd=worktree); standalone otherwise"
echo "ok: idempotent — re-run for an existing worktree is a safe no-op"
echo "ok: --remove tears down the worktree + merged branch; safe when absent"
echo "ok: installer PATH-registers valk-worktree (and still afk), HOME-sandboxed"
exit 0
