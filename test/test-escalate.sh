#!/usr/bin/env bash
#
# test-escalate.sh — afk model escalation (on by default).
#
# Uses a custom `claude` stub that (a) records the --model afk passed and
# (b) never marks the issue done. Asserts:
#   - default (no flags): escalation walks the DEFAULT ladder sonnet→opus, then stuck
#   - --escalate-ladder "haiku sonnet opus": walks all three tiers, then stuck
#   - --cli codex: escalation auto-disables with a warning, run still exits 0
#   - --no-escalate: one shot, no --model passed, issue stuck immediately

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO_ROOT:-$(dirname "$TEST_DIR")}"
AFK="$REPO/scripts/afk"
REPO_STUBS="$TEST_DIR/stubs"

[ -x "$AFK" ] || { echo "afk missing at $AFK"; exit 1; }

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# --- custom stub: records --model, never finishes the issue ------------------
STUB_DIR="$WORKDIR/stub"
mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/claude" <<'STUB'
#!/usr/bin/env bash
set -u
model=""
while [ $# -gt 0 ]; do
  case "$1" in
    --model) model="$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf '%s\n' "${model:-<none>}" >> "$MODEL_LOG"
cat >/dev/null   # drain the piped prompt
# Deliberately do NOT mark the issue done — simulate a failing attempt.
cat <<'JSON'
{"type":"system","subtype":"init","session_id":"stub","model":"claude-haiku-4-5","cwd":"/tmp"}
{"type":"assistant","message":{"id":"m","type":"message","role":"assistant","model":"claude-haiku-4-5","content":[{"type":"text","text":"did not finish"}],"stop_reason":"end_turn","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
{"type":"result","subtype":"success","is_error":false,"session_id":"stub","total_cost_usd":0.0}
JSON
exit 0
STUB
chmod +x "$STUB_DIR/claude"

# --- fixture repo -----------------------------------------------------------
mkdir -p "$WORKDIR/issues" "$WORKDIR/docs/prd"
echo "stub PRD" > "$WORKDIR/docs/prd/dummy.md"

# (Re)create the single failing issue as status: open. Called before each run so
# pick_next_issue selects it fresh.
reset_issue() {
  cat > "$WORKDIR/issues/0001-fails.md" <<'ISSUE'
---
id: 0001
title: Always-fails slice
type: AFK
status: open
blocked_by: []
---

## Acceptance criteria
- [ ] never satisfied by the stub
ISSUE
  # Clear any escalation attempt state from a prior run.
  rm -rf "$WORKDIR/.claude/valk/afk-escalation"
}

cd "$WORKDIR"

FAILS=0
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

# Run afk with the failing stub; $1 = MODEL_LOG path, rest = extra afk args.
run_afk() {
  local log="$1"; shift
  : > "$log"
  MODEL_LOG="$log" PATH="$STUB_DIR:$PATH" "$AFK" 6 --no-confirm "$@" >"$WORKDIR/run.out" 2>&1
}

# --- 1. DEFAULT ladder (no flags) → sonnet, opus, then stuck ----------------
reset_issue
run_afk "$WORKDIR/default.log"
RC=$?
[ "$RC" -eq 0 ] || { fail "default run exit $RC (expected 0)"; cat "$WORKDIR/run.out"; }
GOT="$(tr '\n' ' ' < "$WORKDIR/default.log" | sed 's/ *$//')"
[ "$GOT" = "sonnet opus" ] || fail "default ladder was '$GOT' (expected 'sonnet opus')"
grep -q '^status: stuck' "$WORKDIR/issues/0001-fails.md" || fail "default: issue not marked stuck"

# --- 2. EXPLICIT 3-tier ladder → haiku, sonnet, opus, then stuck ------------
reset_issue
run_afk "$WORKDIR/explicit.log" --escalate-ladder "haiku sonnet opus"
GOT="$(tr '\n' ' ' < "$WORKDIR/explicit.log" | sed 's/ *$//')"
[ "$GOT" = "haiku sonnet opus" ] || fail "explicit ladder was '$GOT' (expected 'haiku sonnet opus')"
grep -q '^status: stuck' "$WORKDIR/issues/0001-fails.md" || fail "explicit: issue not marked stuck"

# --- 3. codex auto-disables escalation (claude-only), warns, exits cleanly ---
# Leave 0001 'stuck' from step 2 so there's no open issue: the run exits 0 via
# "no more issues" without entering the codex+cost path (orthogonal to this
# test). The escalation-disabled warning is printed during setup regardless.
PATH="$REPO_STUBS:$PATH" "$AFK" 1 --no-confirm --cli codex >"$WORKDIR/guard.out" 2>&1
GRC=$?
[ "$GRC" -eq 0 ] || { fail "--cli codex run should exit 0 (got $GRC)"; cat "$WORKDIR/guard.out"; }
grep -q 'escalation is claude-only' "$WORKDIR/guard.out" || fail "missing codex escalation-disabled warning"

# --- 4. --no-escalate → one attempt, no --model passed, immediate stuck ------
reset_issue
run_afk "$WORKDIR/noesc.log" --no-escalate
NRC=$?
[ "$NRC" -eq 0 ] || { fail "--no-escalate run should exit 0 (got $NRC)"; cat "$WORKDIR/run.out"; }
N="$(wc -l < "$WORKDIR/noesc.log" | tr -d ' ')"
[ "$N" -eq 1 ] || fail "--no-escalate: expected 1 attempt, got $N"
grep -q '<none>' "$WORKDIR/noesc.log" || fail "--no-escalate: expected no --model passed (<none>)"
grep -qE '^(haiku|sonnet|opus)$' "$WORKDIR/noesc.log" && fail "--no-escalate: a model tier was passed (should be none)"
grep -q '^status: stuck' "$WORKDIR/issues/0001-fails.md" || fail "--no-escalate: issue not marked stuck"

if [ "$FAILS" -eq 0 ]; then
  echo "test-escalate: all assertions passed"
  exit 0
else
  echo "test-escalate: $FAILS assertion(s) failed"
  exit 1
fi
