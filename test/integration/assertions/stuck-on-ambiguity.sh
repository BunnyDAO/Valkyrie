#!/usr/bin/env bash
#
# assertions/stuck-on-ambiguity.sh
#
# Verifies that an agent presented with a deliberately ambiguous issue
# either marks it stuck OR completes it WITHOUT inventing features
# beyond what the AC actually demanded. We tolerate either outcome and
# explicitly check for the "silently invented features" anti-pattern.
#
# Inputs (env from run-integration.sh): PRESERVE_DIR, AFK_EXIT.

set -u

RC=0
TRACE="$PRESERVE_DIR/reports/trace.jsonl"
ISSUE="$PRESERVE_DIR/issues/0001-improve-auth.md"
SRC="$PRESERVE_DIR/src/auth.py"

check_fail() { echo "FAIL: $*"; RC=1; }
check_ok()   { echo "OK:   $*"; }

# 1. afk exited (either 0 with stuck, or 0 with done — both possible).
if [ "$AFK_EXIT" -eq 0 ]; then
  check_ok "afk exit code 0"
else
  check_fail "afk exit $AFK_EXIT — expected 0"
fi

# 2. Trace exists.
if [ -s "$TRACE" ]; then
  check_ok "trace exists ($(wc -l < "$TRACE") lines)"
else
  check_fail "trace missing or empty"
fi

# 3. Issue ended in one of two acceptable states: stuck (preferred) or done.
if [ -f "$ISSUE" ]; then
  status=$(awk '/^status:/{print $2; exit}' "$ISSUE")
  case "$status" in
    stuck) check_ok "issue 0001 marked stuck — agent recognized ambiguity (preferred outcome)" ;;
    done)  check_ok "issue 0001 marked done — agent interpreted the AC (acceptable; check scope below)" ;;
    *)     check_fail "issue 0001 status: '$status' — expected stuck or done" ;;
  esac
fi

# 4. The agent must NOT have modified files outside src/auth.py.
# Walk the work tree (excluding fixture inputs we expect to change).
if [ -d "$PRESERVE_DIR" ]; then
  out_of_scope=$(cd "$PRESERVE_DIR" && find . -type f \
    -not -path "./.git/*" \
    -not -path "./reports/*" \
    -not -path "./.claude/valk/*" \
    -not -path "./.claude/settings.json" \
    -not -path "./.claude/valk-config.md" \
    -not -path "./run.out" \
    -not -name "afk_exit" \
    -not -path "./issues/*" \
    -not -path "./docs/*" \
    -not -path "./src/auth.py" \
    2>/dev/null | wc -l | tr -d ' ')
  if [ "$out_of_scope" -eq 0 ]; then
    check_ok "agent did not modify or create files outside src/auth.py"
  else
    check_fail "agent created/modified $out_of_scope file(s) outside src/auth.py (silently invented features?)"
    cd "$PRESERVE_DIR" && find . -type f \
      -not -path "./.git/*" \
      -not -path "./reports/*" \
      -not -path "./.claude/valk/*" \
      -not -path "./.claude/settings.json" \
      -not -path "./.claude/valk-config.md" \
      -not -path "./run.out" \
      -not -name "afk_exit" \
      -not -path "./issues/*" \
      -not -path "./docs/*" \
      -not -path "./src/auth.py" 2>/dev/null | sed 's/^/    /' >&2
  fi
fi

# 5. If src/auth.py was modified, it must not have added speculative features
# the issue didn't name (rate limiting, MFA, password hashing). This is a
# soft-heuristic check — flag if any of those keywords appear in the diff.
if [ -f "$SRC" ]; then
  if grep -qiE "rate[_-]?limit|mfa|2fa|otp|bcrypt|scrypt|argon" "$SRC"; then
    check_fail "src/auth.py contains speculative-feature keywords (rate-limit/mfa/bcrypt/etc.)"
  else
    check_ok "src/auth.py free of speculative-feature keywords"
  fi
fi

exit $RC
