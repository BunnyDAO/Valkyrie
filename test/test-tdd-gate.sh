#!/usr/bin/env bash
# test-tdd-gate.sh — the PreToolUse hard gate (scripts/valk-tdd-gate.sh).
#
# Asserts: production-code edits are DENIED during pre-TDD flow stages, ALLOWED at
# tdd/afk/idle, workflow artifacts (*.md, docs/, issues/) always pass, and the
# best-effort Bash check blocks `… > x.ts` without blocking benign commands.

set -u

REPO="${REPO_ROOT:?REPO_ROOT not set}"
GATE="$REPO/scripts/valk-tdd-gate.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

FAILS=0

set_stage() {
  mkdir -p "$TMP/.claude/valk"
  printf '%s\n' "$1" > "$TMP/.claude/valk/stage"
}

# Build a PreToolUse input JSON. For Bash, $3 is the command; otherwise it's a path.
run_gate() { # tool path-or-cmd
  local tool="$1" arg="$2" json
  if [[ "$tool" == "Bash" ]]; then
    json=$(jq -n --arg t "$tool" --arg c "$TMP" --arg a "$arg" \
      '{tool_name:$t, cwd:$c, tool_input:{command:$a}}')
  elif [[ "$tool" == "NotebookEdit" ]]; then
    json=$(jq -n --arg t "$tool" --arg c "$TMP" --arg a "$arg" \
      '{tool_name:$t, cwd:$c, tool_input:{notebook_path:$a}}')
  else
    json=$(jq -n --arg t "$tool" --arg c "$TMP" --arg a "$arg" \
      '{tool_name:$t, cwd:$c, tool_input:{file_path:$a}}')
  fi
  printf '%s' "$json" | bash "$GATE"
}

assert_deny() { # desc tool arg
  local out; out=$(run_gate "$2" "$3")
  if printf '%s' "$out" | grep -q '"permissionDecision":[[:space:]]*"deny"'; then
    printf '  ok   (deny)  %s\n' "$1"
  else
    printf '  FAIL (want deny) %s\n    got: %s\n' "$1" "$out"; FAILS=$((FAILS+1))
  fi
}

assert_allow() { # desc tool arg
  local out; out=$(run_gate "$2" "$3")
  if printf '%s' "$out" | grep -q '"permissionDecision"'; then
    printf '  FAIL (want allow) %s\n    got: %s\n' "$1" "$out"; FAILS=$((FAILS+1))
  else
    printf '  ok   (allow) %s\n' "$1"
  fi
}

echo "-- gated stage: design --"
set_stage design
assert_deny  "Edit src/foo.ts blocked"                Edit         "$TMP/src/foo.ts"
assert_deny  "Write src/app.py blocked"               Write        "$TMP/src/app.py"
assert_allow "Edit docs/prd/x.md allowed"             Edit         "$TMP/docs/prd/x.md"
assert_allow "Edit DOMAIN.md allowed"                 Edit         "$TMP/DOMAIN.md"
assert_allow "Edit PRODUCT-MAP.md allowed"            Edit         "$TMP/PRODUCT-MAP.md"
assert_allow "Read is never gated"                    Read         "$TMP/src/foo.ts"
assert_deny  "Bash echo > src/foo.ts blocked"         Bash         "echo x > $TMP/src/foo.ts"
assert_allow "Bash echo > notes.md allowed"           Bash         "echo x > $TMP/notes.md"
assert_allow "Bash benign 2>/dev/null allowed"        Bash         "ls -la 2>/dev/null"
assert_allow "Bash git status allowed"                Bash         "git status"

echo "-- gated stage: issues --"
set_stage issues
assert_deny  "Edit src/foo.go blocked at issues"      Edit         "$TMP/src/foo.go"
assert_allow "Edit issues/0001.md allowed"            Edit         "$TMP/issues/0001-x.md"

echo "-- allow-edit stage: tdd --"
set_stage tdd
assert_allow "Edit src/foo.ts allowed at tdd"         Edit         "$TMP/src/foo.ts"
assert_allow "Bash echo > src/foo.ts allowed at tdd"  Bash         "echo x > $TMP/src/foo.ts"

echo "-- allow-edit stage: afk --"
set_stage afk
assert_allow "Edit src/foo.ts allowed at afk"         Edit         "$TMP/src/foo.ts"

echo "-- idle (not in a flow) --"
set_stage idle
assert_allow "Edit src/foo.ts allowed at idle"        Edit         "$TMP/src/foo.ts"

echo "-- no stage file at all → idle → allow --"
rm -f "$TMP/.claude/valk/stage"
assert_allow "Edit src/foo.ts allowed (no stage file)" Edit        "$TMP/src/foo.ts"

echo
if [ "$FAILS" -eq 0 ]; then
  echo "test-tdd-gate: all assertions passed"
  exit 0
else
  echo "test-tdd-gate: $FAILS assertion(s) failed"
  exit 1
fi
