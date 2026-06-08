#!/usr/bin/env bash
#
# test-loop-config.sh — afk reads a forged crew's valk-config `loop:` block's
# *outer* caps as defaults; flags / the positional still win (Agent-Builder
# #0005). Verified through `afk --print-config` (resolves caps and exits without
# running an agent — so it needs no CLI on PATH).

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO_ROOT:-$(dirname "$TEST_DIR")}"
AFK="$REPO/scripts/afk"

[ -x "$AFK" ] || { echo "FAIL: afk missing/not exec at $AFK"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

mkrepo() { local d="$WORK/$1"; mkdir -p "$d/.claude"; echo "$d"; }
field() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }  # "key=val" -> val

# A forged Valkyrie crew with a loop: block.
R="$(mkrepo r)"
cat > "$R/.claude/valk-config.md" <<'EOF'
---
version: 1
stages:
  DESIGN: []
  PRD: []
  ISSUES: []
  TDD: [implementer, tester-qa]
support: []
loop:
  loop_back_to: implementer
  critic: tester-qa
  max_iter: 3
  budget: 10
  max_iters: 20
  max_hours: 4
  max_cost_usd: 50
  escalate_ladder: [sonnet, opus]
---
EOF

# 1) the loop block supplies afk's defaults
OUT="$(cd "$R" && bash "$AFK" --print-config)"
[ "$(field "$OUT" max_iters)" = "20" ] \
  || { echo "FAIL: loop max_iters not adopted (got '$(field "$OUT" max_iters)')"; exit 1; }
[ "$(field "$OUT" max_cost_usd)" = "50" ] \
  || { echo "FAIL: loop max_cost_usd not adopted"; exit 1; }
[ "$(field "$OUT" escalate_ladder)" = "sonnet opus" ] \
  || { echo "FAIL: loop escalate_ladder not adopted (got '$(field "$OUT" escalate_ladder)')"; exit 1; }

# 2) a positional max_iters overrides the loop block
OUT="$(cd "$R" && bash "$AFK" 9 --print-config)"
[ "$(field "$OUT" max_iters)" = "9" ] \
  || { echo "FAIL: positional did not override loop max_iters (got '$(field "$OUT" max_iters)')"; exit 1; }

# 3) a flag overrides the loop block
OUT="$(cd "$R" && bash "$AFK" --print-config --max-cost-usd 99)"
[ "$(field "$OUT" max_cost_usd)" = "99" ] \
  || { echo "FAIL: --max-cost-usd did not override loop block (got '$(field "$OUT" max_cost_usd)')"; exit 1; }

# 4) no loop block -> vanilla afk defaults; positional still required
N="$(mkrepo n)"
OUT="$(cd "$N" && bash "$AFK" 5 --print-config)"
[ "$(field "$OUT" max_cost_usd)" = "50" ] \
  || { echo "FAIL: vanilla default cost wrong (got '$(field "$OUT" max_cost_usd)')"; exit 1; }
[ "$(field "$OUT" max_iters)" = "5" ] \
  || { echo "FAIL: vanilla positional max_iters wrong (got '$(field "$OUT" max_iters)')"; exit 1; }

echo "PASS: test-loop-config.sh"
