#!/usr/bin/env bash
#
# assertions/trivial-slice.sh
#
# Verifies the trivial-slice scenario produced the expected behavior.
#
# Inputs (env from run-integration.sh):
#   PRESERVE_DIR  — path to preserved artifacts (trace, work tree, run output, afk_exit)
#   AFK_EXIT      — exit code of the afk invocation
#
# Each check echoes "OK: …" or "FAIL: …". First failure flips RC to 1.

set -u

RC=0
TRACE="$PRESERVE_DIR/reports/trace.jsonl"
ISSUE="$PRESERVE_DIR/issues/0001-rename-greet-to-say-hello.md"
SRC="$PRESERVE_DIR/src/greet.py"

check_fail() { echo "FAIL: $*"; RC=1; }
check_ok()   { echo "OK:   $*"; }

# 1. afk exited cleanly (or with the "one iter, then done" pattern).
if [ "$AFK_EXIT" -eq 0 ]; then
  check_ok "afk exit code 0"
else
  check_fail "afk exit $AFK_EXIT — expected 0"
fi

# 2. Trace file exists and is non-empty JSONL.
if [ -s "$TRACE" ]; then
  lines=$(wc -l < "$TRACE")
  check_ok "trace exists, $lines lines"
else
  check_fail "trace missing or empty at $TRACE"
fi

# 3. Trace has at least one SessionStart and at least one Stop event.
if [ -s "$TRACE" ]; then
  has_start=$(grep -c '"event": "SessionStart"' "$TRACE" || true)
  has_stop=$(grep -c '"event": "Stop"' "$TRACE" || true)
  [ "$has_start" -ge 1 ] && check_ok "trace has $has_start SessionStart event(s)" || check_fail "no SessionStart in trace"
  [ "$has_stop" -ge 1 ] && check_ok "trace has $has_stop Stop event(s)" || check_fail "no Stop in trace"
fi

# 4. Trace shows the agent invoked at least one tool (PreToolUse appears).
if [ -s "$TRACE" ]; then
  tool_uses=$(grep -c '"event": "PreToolUse"' "$TRACE" || true)
  if [ "$tool_uses" -ge 1 ]; then
    check_ok "agent invoked $tool_uses tool(s)"
  else
    check_fail "no PreToolUse events — agent didn't take any actions"
  fi
fi

# 5. The source file got renamed (success criterion of the issue itself).
if [ -f "$SRC" ]; then
  if grep -q "def say_hello" "$SRC"; then
    check_ok "src/greet.py defines say_hello"
  else
    check_fail "src/greet.py does NOT define say_hello"
  fi
  # Word-boundary match so we don't accidentally hit `def greet_loudly`.
  if grep -qE "^def greet\(" "$SRC"; then
    check_fail "src/greet.py still defines greet (rename incomplete)"
  else
    check_ok "src/greet.py no longer defines the old greet function"
  fi
else
  check_fail "src/greet.py missing"
fi

# 6. Issue marked done (since pr_skill is 'none', this is the success signal).
if [ -f "$ISSUE" ]; then
  status=$(awk '/^status:/{print $2; exit}' "$ISSUE")
  if [ "$status" = "done" ]; then
    check_ok "issue 0001 status: done"
  else
    check_fail "issue 0001 status: '$status' — expected done"
  fi
fi

# 7. Cost stayed within budget.
csv="$PRESERVE_DIR/.claude/valk/afk-cost-history.csv"
if [ -f "$csv" ]; then
  total=$(awk -F, 'NR>1 {sum+=$9} END{printf "%.4f", sum}' "$csv")
  check_ok "total cost: \$$total (budget was \$${VALK_BUDGET_USD:-1.0})"
else
  echo "WARN: no cost CSV at $csv"
fi

exit $RC
