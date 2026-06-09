#!/usr/bin/env bash
#
# test-evaluator-modes.sh — Valkyrie honors a forged loop pair's `evaluatorMode`
# (agent | human | agent-escalate) best-effort (Agent-Builder #0111 / ADR-0027).
#
# Hard, scriptable pieces:
#   1. read-valk-config.sh --pairs exposes `evaluator_mode=<m>` (only when set;
#      absent ⇒ field omitted ⇒ caller defaults to `agent`).
#   2. afk --print-config reports non-`agent` pairs in `human_eval_pairs=` so an
#      unattended run can surface them; an all-`agent` (or no-mode) config leaves
#      it empty — i.e. agent-mode is byte-unchanged (regression).
# Orchestration (route-back, human pause) is best-effort skill prose.

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO_ROOT:-$(dirname "$TEST_DIR")}"
READER="$REPO/scripts/read-valk-config.sh"
AFK="$REPO/scripts/afk"

[ -x "$READER" ] || { echo "FAIL: read-valk-config.sh missing/not exec"; exit 1; }
[ -x "$AFK" ]    || { echo "FAIL: afk missing/not exec"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
field() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }

# ---- 1. --pairs surfaces evaluator_mode when set, omits it when absent -------
R="$WORK/r"; mkdir -p "$R/.claude"
cat > "$R/.claude/valk-config.md" <<'EOF'
---
version: 1
stages:
  TDD: [implementer, tester-qa]
support: []
loop:
  pairs:
    - loop_back_to: implementer
      critic: tester-qa
      max_iter: 3
      evaluatorMode: agent-escalate
    - loop_back_to: planner
      critic: reviewer
      max_iter: 5
      evaluatorMode: human
    - loop_back_to: drafter
      critic: linter
      max_iter: 2
---
EOF

OUT="$(bash "$READER" --repo "$R" --pairs)"
printf '%s\n' "$OUT" | grep -qx 'from=implementer critic=tester-qa max_iter=3 evaluator_mode=agent-escalate' \
  || { echo "FAIL: pair 1 evaluator_mode=agent-escalate missing — <$OUT>"; exit 1; }
printf '%s\n' "$OUT" | grep -qx 'from=planner critic=reviewer max_iter=5 evaluator_mode=human' \
  || { echo "FAIL: pair 2 evaluator_mode=human missing — <$OUT>"; exit 1; }
# pair 3 has no evaluatorMode → field omitted (caller defaults to agent)
printf '%s\n' "$OUT" | grep -qx 'from=drafter critic=linter max_iter=2' \
  || { echo "FAIL: pair 3 should omit evaluator_mode — <$OUT>"; exit 1; }

# ---- 2. afk --print-config surfaces human/escalate pairs ---------------------
PC="$(cd "$R" && bash "$AFK" 5 --print-config)"
HEP="$(field "$PC" human_eval_pairs)"
case "$HEP" in
  *"tester-qa (agent-escalate)"*) : ;;
  *) echo "FAIL: --print-config human_eval_pairs missing escalate pair — <$HEP>"; exit 1 ;;
esac
case "$HEP" in
  *"reviewer (human)"*) : ;;
  *) echo "FAIL: --print-config human_eval_pairs missing human pair — <$HEP>"; exit 1 ;;
esac
# the plain agent pair must NOT be surfaced
case "$HEP" in
  *"linter"*) echo "FAIL: agent-mode pair should not surface — <$HEP>"; exit 1 ;;
esac

# ---- 3. regression: agent-only / no-mode config → empty human_eval_pairs -----
A="$WORK/a"; mkdir -p "$A/.claude"
cat > "$A/.claude/valk-config.md" <<'EOF'
---
version: 1
stages:
  TDD: [implementer, tester-qa]
support: []
loop:
  pairs:
    - loop_back_to: implementer
      critic: tester-qa
      max_iter: 3
      evaluatorMode: agent
---
EOF
PCA="$(cd "$A" && bash "$AFK" 5 --print-config)"
[ -z "$(field "$PCA" human_eval_pairs)" ] \
  || { echo "FAIL: agent-mode should leave human_eval_pairs empty — <$(field "$PCA" human_eval_pairs)>"; exit 1; }

# no loop block at all → empty too (vanilla)
N="$WORK/n"; mkdir -p "$N/.claude"
printf -- '---\nversion: 1\nstages:\n  TDD: []\nsupport: []\n---\n' > "$N/.claude/valk-config.md"
PCN="$(cd "$N" && bash "$AFK" 5 --print-config)"
[ -z "$(field "$PCN" human_eval_pairs)" ] \
  || { echo "FAIL: no-loop config should leave human_eval_pairs empty"; exit 1; }

echo "PASS: test-evaluator-modes.sh"
exit 0
