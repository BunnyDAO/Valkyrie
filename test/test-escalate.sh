#!/usr/bin/env bash
#
# test-escalate.sh — afk --escalate per-issue model escalation.
#
# Uses a custom `claude` stub that (a) records the --model afk passed and
# (b) never marks the issue done. Asserts afk walks the ladder
# haiku→sonnet→opus across attempts, then marks the issue stuck once the
# ladder is exhausted — and that --escalate is rejected with --cli codex.

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

MODEL_LOG="$WORKDIR/models.log"
: > "$MODEL_LOG"

cd "$WORKDIR"
export MODEL_LOG
# No --escalate flag: escalation must be ON by default.
PATH="$STUB_DIR:$PATH" "$AFK" 5 --no-confirm >"$WORKDIR/run.out" 2>&1
RC=$?

FAILS=0
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

# 1. Clean exit.
[ "$RC" -eq 0 ] || { fail "afk exit code $RC (expected 0)"; cat "$WORKDIR/run.out"; }

# 2. The ladder was walked in order: haiku, sonnet, opus (one line each).
GOT="$(tr '\n' ' ' < "$MODEL_LOG" | sed 's/ *$//')"
[ "$GOT" = "haiku sonnet opus" ] || fail "model ladder was '$GOT' (expected 'haiku sonnet opus')"

# 3. Exactly 3 attempts (MAX_ATTEMPTS = 3 tiers x 1 try), no 4th.
N="$(wc -l < "$MODEL_LOG" | tr -d ' ')"
[ "$N" -eq 3 ] || fail "expected 3 attempts, got $N"

# 4. Issue ended 'stuck' after exhausting the ladder.
grep -q '^status: stuck' "$WORKDIR/issues/0001-fails.md" || fail "issue not marked stuck"

# 5. Escalation log mentions exhausting the ladder.
grep -q 'exhausted the escalation ladder' "$WORKDIR/run.out" || fail "no 'exhausted ladder' message"

# --- guard: codex auto-disables escalation (claude-only) and still runs ------
# Default-on escalation must NOT break codex: it warns, disables, and exits 0.
cd "$WORKDIR"
PATH="$REPO_STUBS:$PATH" "$AFK" 1 --no-confirm --cli codex >"$WORKDIR/guard.out" 2>&1
GRC=$?
[ "$GRC" -eq 0 ] || { fail "--cli codex run should exit 0 (got $GRC)"; cat "$WORKDIR/guard.out"; }
grep -q 'escalation is claude-only' "$WORKDIR/guard.out" || fail "missing codex escalation-disabled warning"

# --- guard: --no-escalate is one shot per issue (no model flag, then stuck) --
# Fresh failing issue + the model-recording stub. --no-escalate => one attempt,
# NO --model passed, issue immediately stuck (the old default behavior).
NOESC_LOG="$WORKDIR/noesc.log"; : > "$NOESC_LOG"
cat > "$WORKDIR/issues/0002-fails.md" <<'ISSUE'
---
id: 0002
title: Also-fails slice
type: AFK
status: open
blocked_by: []
---

## Acceptance criteria
- [ ] never satisfied by the stub
ISSUE
cd "$WORKDIR"
MODEL_LOG="$NOESC_LOG" PATH="$STUB_DIR:$PATH" "$AFK" 3 --no-confirm --no-escalate >"$WORKDIR/noesc.out" 2>&1
NRC=$?
[ "$NRC" -eq 0 ] || { fail "--no-escalate run should exit 0 (got $NRC)"; cat "$WORKDIR/noesc.out"; }
grep -q '^status: stuck' "$WORKDIR/issues/0002-fails.md" || fail "--no-escalate: 0002 not marked stuck"
grep -q '<none>' "$NOESC_LOG" || fail "--no-escalate: expected no --model passed (<none>)"
grep -qE '^(haiku|sonnet|opus)$' "$NOESC_LOG" && fail "--no-escalate: a model tier was passed (should be none)"

if [ "$FAILS" -eq 0 ]; then
  echo "test-escalate: all assertions passed"
  exit 0
else
  echo "test-escalate: $FAILS assertion(s) failed"
  exit 1
fi
