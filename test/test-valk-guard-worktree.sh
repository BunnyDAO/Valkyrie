#!/usr/bin/env bash
#
# test-valk-guard-worktree.sh — issue 0014. The UserPromptSubmit guard nudges
# toward valk-worktree when run from the shared MAIN checkout, and is silent
# once the terminal is in a linked worktree (self-extinguishing, stateless,
# warn-only). Behaviour observed only through the guard's stdout/exit — never
# internals.
set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO_ROOT:-$(dirname "$TEST_DIR")}"
GUARD="$REPO/scripts/valk-guard.sh"

[ -f "$GUARD" ] || { echo "FAIL: valk-guard.sh missing at $GUARD"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

# Empty sandbox HOME ⇒ guard's `python3 $HOME/.claude/valkyrie/stage.py get`
# fails ⇒ its `|| echo idle` makes STAGE deterministically `idle`, so a
# build-shaped prompt reaches the enforcement injection regardless of this
# dev machine's real stage marker.
SBX="$WORK/home"; mkdir -p "$SBX"

# Main checkout + a linked worktree off it.
MAIN="$WORK/proj"
mkdir -p "$MAIN"
git -C "$MAIN" init -q
git -C "$MAIN" config user.email t@t.t
git -C "$MAIN" config user.name t
echo seed > "$MAIN/seed.txt"
git -C "$MAIN" add -A && git -C "$MAIN" commit -qm seed
git -C "$MAIN" worktree add -q "$WORK/proj-wt1" -b valk/wt1
WT="$WORK/proj-wt1"

PROMPT_JSON='{"prompt":"let'"'"'s build a billing dashboard"}'

run_guard() { # run_guard <cwd>  -> echoes guard stdout
  ( cd "$1" && printf '%s' "$PROMPT_JSON" | HOME="$SBX" bash "$GUARD" 2>/dev/null )
}

# --- main checkout → exactly one valk-worktree reminder ---
OUT="$(run_guard "$MAIN")"
N="$(printf '%s' "$OUT" | grep -o 'valk-worktree' | wc -l | tr -d ' ')"
[ "$N" = "1" ] || fail "main checkout: expected exactly 1 valk-worktree mention, got $N (out: $OUT)"

# --- linked worktree → enforcement still present, but nudge is silent ---
OUT_WT="$(run_guard "$WT")"
printf '%s' "$OUT_WT" | grep -q 'VALK ENFORCEMENT' \
  || fail "worktree: enforcement context must still be emitted (out: $OUT_WT)"
printf '%s' "$OUT_WT" | grep -q 'valk-worktree' \
  && fail "worktree: worktree nudge must be silent inside a linked worktree"

# --- warn-only: exit is always 0; nudge never leaks into silent paths ---
( cd "$MAIN" && printf '%s' "$PROMPT_JSON" | HOME="$SBX" bash "$GUARD" >/dev/null 2>&1 )
[ $? -eq 0 ] || fail "guard must exit 0 from the main checkout (never blocks)"
( cd "$WT" && printf '%s' "$PROMPT_JSON" | HOME="$SBX" bash "$GUARD" >/dev/null 2>&1 )
[ $? -eq 0 ] || fail "guard must exit 0 from a linked worktree (never blocks)"

# A non-build prompt: pre-existing silent path — no output, exit 0, and the
# worktree nudge must NOT leak here even though cwd is the main checkout.
CHAT='{"prompt":"what time is it in Tokyo?"}'
OUT_CHAT="$( cd "$MAIN" && printf '%s' "$CHAT" | HOME="$SBX" bash "$GUARD" 2>/dev/null )"
rc=$?
[ "$rc" -eq 0 ] || fail "non-build prompt: exit changed (got $rc)"
[ -z "$OUT_CHAT" ] || fail "non-build prompt: guard must stay silent (out: $OUT_CHAT)"

# An opt-out prompt: early-exit path unchanged, no nudge leak.
OPT='{"prompt":"--skip-to tdd just do it"}'
OUT_OPT="$( cd "$MAIN" && printf '%s' "$OPT" | HOME="$SBX" bash "$GUARD" 2>/dev/null )"
[ -z "$OUT_OPT" ] || fail "opt-out prompt: guard must stay silent (out: $OUT_OPT)"

echo "ok: main checkout → exactly one valk-worktree reminder in guard output"
echo "ok: linked worktree → enforcement kept, worktree nudge self-silenced"
echo "ok: warn-only — exit always 0; nudge never leaks into silent paths"
exit 0
