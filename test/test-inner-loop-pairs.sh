#!/usr/bin/env bash
#
# test-inner-loop-pairs.sh — the Valkyrie inner-loop port's testable foundation
# (Agent-Builder #0009): (1) `read-valk-config.sh --pairs` extracts the nested
# `loop: pairs:` YAML list as bash-parseable records; (2) `parse-loop-verdict.sh`
# reads a critic's output → pass|fail|stop. Best-effort orchestration lives in
# skill prose (skills/valk/SKILL.md); these are the hard, scriptable pieces.

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO_ROOT:-$(dirname "$TEST_DIR")}"
READER="$REPO/scripts/read-valk-config.sh"
VERDICT="$REPO/scripts/parse-loop-verdict.sh"

[ -x "$READER" ] || { echo "FAIL: read-valk-config.sh missing/not exec"; exit 1; }
[ -x "$VERDICT" ] || { echo "FAIL: parse-loop-verdict.sh missing/not exec"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# ---- 1. --pairs extracts the nested pairs list ----------------------------
R="$WORK/r"; mkdir -p "$R/.claude"
cat > "$R/.claude/valk-config.md" <<'EOF'
---
version: 1
stages:
  TDD: [implementer, tester-qa]
support: []
loop:
  max_iters: 20
  max_cost_usd: 50
  pairs:
    - loop_back_to: implementer
      critic: tester-qa
      max_iter: 3
      budget: 10
      budget_mode: valkyrie-usd
    - loop_back_to: planner
      critic: reviewer
      max_iter: 5
---
EOF

OUT="$(bash "$READER" --repo "$R" --pairs)"
N="$(printf '%s\n' "$OUT" | grep -c .)"
[ "$N" = "2" ] || { echo "FAIL: expected 2 pairs, got $N — <$OUT>"; exit 1; }
printf '%s\n' "$OUT" | grep -qx 'from=implementer critic=tester-qa max_iter=3 budget=10 budget_mode=valkyrie-usd' \
  || { echo "FAIL: pair 1 record wrong — <$OUT>"; exit 1; }
printf '%s\n' "$OUT" | grep -qx 'from=planner critic=reviewer max_iter=5' \
  || { echo "FAIL: pair 2 record wrong (budget fields should be absent) — <$OUT>"; exit 1; }

# no loop block → empty, exit 0
N2="$WORK/n"; mkdir -p "$N2/.claude"
printf -- '---\nversion: 1\nstages:\n  TDD: []\nsupport: []\n---\n' > "$N2/.claude/valk-config.md"
OUT2="$(bash "$READER" --repo "$N2" --pairs)"
[ -z "$OUT2" ] || { echo "FAIL: expected empty for no pairs, got <$OUT2>"; exit 1; }

# missing file → empty, exit 0
OUT3="$(bash "$READER" --repo "$WORK/nope" --pairs)"
[ -z "$OUT3" ] || { echo "FAIL: expected empty for missing config, got <$OUT3>"; exit 1; }

# ---- 2. parse-loop-verdict reads the fenced block -------------------------
mk() { printf '%s\n' "$1" > "$WORK/v.txt"; bash "$VERDICT" "$WORK/v.txt"; }

pass_out='Looks good.

```loop-verdict
{ "status": "pass", "message": "ok", "details": {} }
```'
[ "$(mk "$pass_out")" = "pass" ] || { echo "FAIL: pass not parsed"; exit 1; }

fail_out='```loop-verdict
{ "status": "fail", "message": "tests red" }
```'
[ "$(mk "$fail_out")" = "fail" ] || { echo "FAIL: fail not parsed"; exit 1; }

stop_out='```loop-verdict
{"status":"stop","message":"security"}
```'
[ "$(mk "$stop_out")" = "stop" ] || { echo "FAIL: stop not parsed"; exit 1; }

# the LAST block wins when several are present
two="$fail_out

$pass_out"
[ "$(mk "$two")" = "pass" ] || { echo "FAIL: last block should win"; exit 1; }

# no block / garbage → empty, exit non-zero (caller treats as "no verdict")
[ -z "$(mk 'just prose, no verdict')" ] || { echo "FAIL: expected empty for no block"; exit 1; }
printf 'just prose\n' > "$WORK/v.txt"
bash "$VERDICT" "$WORK/v.txt" >/dev/null 2>&1 && { echo "FAIL: expected non-zero exit for no verdict"; exit 1; }

echo "PASS: test-inner-loop-pairs.sh"
