#!/usr/bin/env bash
# test-loop-gate.sh — the Stop-hook loop gate (scripts/valk-loop-gate.sh, #0030).
#
# Asserts: a `fail` loop-verdict BLOCKS the stop with a route-back reason and a
# per-session iteration ledger; max_iter exhausts to an allow; `pass` allows and
# resets the pair's ledger; `stop` allows (escalation); and every ambiguous case
# (no config / no pairs / no verdict / unattributable verdict) is permissive.

set -u

REPO="${REPO_ROOT:?REPO_ROOT not set}"
GATE="$REPO/scripts/valk-loop-gate.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

FAILS=0

# A crew repo with one loop pair: implementer ↺ reviewer, max_iter 2.
write_config() { # [extra-pair-yaml]
  mkdir -p "$TMP/repo/.claude"
  cat > "$TMP/repo/.claude/valk-config.md" <<EOF
---
version: 1
loop:
  pairs:
    - loop_back_to: implementer
      critic: reviewer
      max_iter: 2
${1:-}
---
# crew
EOF
}

# A transcript whose last assistant message carries the given loop-verdict body
# (JSON-encoded into the JSONL line like a real transcript).
write_transcript() { # verdict-json-body (or empty for none)
  local body="$1" text
  if [[ -z "$body" ]]; then
    text="just some assistant prose, no verdict here"
  else
    text=$(printf 'Review done.\n```loop-verdict\n%s\n```\n' "$body")
  fi
  jq -nc --arg t "$text" '{type:"assistant", message:{content:[{type:"text", text:$t}]}}' \
    > "$TMP/transcript.jsonl"
}

run_gate() {
  jq -n --arg c "$TMP/repo" --arg t "$TMP/transcript.jsonl" \
    '{cwd:$c, transcript_path:$t, session_id:"s1", stop_hook_active:false}' \
    | bash "$GATE"
}

check() { # desc expectation(block|allow) output
  local desc="$1" want="$2" out="$3" got
  if printf '%s' "$out" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    got=block
  else
    got=allow
  fi
  if [[ "$got" == "$want" ]]; then
    echo "  ok: $desc"
  else
    echo "  FAIL: $desc (wanted $want, got $got; out=$out)"
    FAILS=$((FAILS + 1))
  fi
}

reset_ledger() { rm -f "$TMP/repo/.claude/valk/loop-ledger.json"; }

echo "== fail verdict blocks with route-back, bounded by max_iter =="
write_config
write_transcript '{ "status": "fail", "critic": "reviewer", "message": "untested edge" }'
reset_ledger
OUT=$(run_gate); check "1st fail → block (route back)" block "$OUT"
printf '%s' "$OUT" | jq -r '.reason' | grep -q "re-run the range from implementer" \
  && echo "  ok: reason names the loop-back member" \
  || { echo "  FAIL: reason missing route-back member"; FAILS=$((FAILS + 1)); }
OUT=$(run_gate); check "2nd fail → block (iter 2/2)" block "$OUT"
OUT=$(run_gate); check "3rd fail → ALLOW (max_iter exhausted)" allow "$OUT"

echo "== pass allows and resets the ledger =="
write_transcript '{ "status": "pass", "critic": "reviewer", "message": "good" }'
OUT=$(run_gate); check "pass → allow" allow "$OUT"
grep -q 'implementer' "$TMP/repo/.claude/valk/loop-ledger.json" 2>/dev/null \
  && { echo "  FAIL: ledger entry not reset on pass"; FAILS=$((FAILS + 1)); } \
  || echo "  ok: ledger entry cleared on pass"
write_transcript '{ "status": "fail", "critic": "reviewer", "message": "regressed" }'
OUT=$(run_gate); check "fail after pass → block again (fresh count)" block "$OUT"

echo "== stop verdict allows (escalation to the human) =="
reset_ledger
write_transcript '{ "status": "stop", "critic": "reviewer", "message": "wrong approach" }'
OUT=$(run_gate); check "stop → allow" allow "$OUT"

echo "== ambiguity is permissive =="
reset_ledger
write_transcript ''
OUT=$(run_gate); check "no verdict in transcript → allow" allow "$OUT"

write_transcript '{ "status": "fail", "critic": "ghost", "message": "?" }'
write_config '    - loop_back_to: docs
      critic: explorer
      max_iter: 3'
reset_ledger
OUT=$(run_gate); check "unattributable critic + multiple pairs → allow" allow "$OUT"

rm -f "$TMP/repo/.claude/valk-config.md"
write_transcript '{ "status": "fail", "critic": "reviewer", "message": "x" }'
OUT=$(run_gate); check "no valk-config → allow" allow "$OUT"

echo
if [[ $FAILS -eq 0 ]]; then
  echo "test-loop-gate: ALL PASS"
else
  echo "test-loop-gate: $FAILS FAILURE(S)"
  exit 1
fi
