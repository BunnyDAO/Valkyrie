#!/usr/bin/env bash
# Valkyrie UserPromptSubmit guard.
#
# When the user submits a prompt that looks like a build / fix / refactor
# request and the Valkyrie stage is idle, inject a system reminder that
# forces Claude to invoke the valk skill before writing any code.
#
# Wired in ~/.claude/settings.json under hooks.UserPromptSubmit.

set -u

INPUT=$(cat)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // ""')

# Bail silently if no prompt text (defensive — should not happen).
if [[ -z "$PROMPT" ]]; then
  exit 0
fi

# User explicitly opted out — let it through.
if printf '%s' "$PROMPT" | grep -qiE "skip[- ]?prompt[- ]?maxx|trivial change|one-?line (fix|change)|--skip-to"; then
  exit 0
fi

# User is already invoking the workflow — let it through.
if printf '%s' "$PROMPT" | grep -qiE "^/(valk|maxx|pm|grill-?me|to-?prd|to-?issues|tdd|zoom-?out|refactor-?spaghetti)\b"; then
  exit 0
fi

# Get current stage (per-project, falling back to global, falling back to "idle").
STAGE=$(python3 "$HOME/.claude/valkyrie/stage.py" get 2>/dev/null || echo "idle")
STAGE=${STAGE:-idle}

# Only enforce when idle. Mid-workflow stages are owned by their skills.
if [[ "$STAGE" != "idle" ]]; then
  exit 0
fi

# Match build / fix / refactor language. Tuned for false POSITIVES over false
# negatives — better to nag occasionally than miss a real build request. Each
# alternation is one category; add new categories at the end, not inside the
# existing groups, so the meaning stays readable.
#
# Categories:
#   1. "let's X" + build verb            (lets build, let's add, ...)
#   2. modal/intent + build verb         (try to add, want to build, can you implement, ...)
#   3. imperative start + article        (build a, add an, implement the, ...)
#   4. bug fixes                         (fix this/the/a bug)
#   5. refactor                          (refactor this/the/that/a)
#   6. feature noun                      (new feature, a feature, another feature)
#   7. "X me a/an"                       (build me a, implement me an)
TRIGGER_RE="let'?s (build|add|implement|create|design|ship|make)"
TRIGGER_RE+="|(try(ing)? to|want to|going to|need to|let me|can you|could you|please|help me|i'?ll|we should|i'?d like to|wanna|gonna) (add|build|implement|create|design|ship|make)"
TRIGGER_RE+="|(^|[^a-z])(build|add|implement|create|make|design|ship) (a|an|the|some|me|new) "
TRIGGER_RE+="|fix (this|the|a|an) bug"
TRIGGER_RE+="|refactor (this|the|that|a|an)"
TRIGGER_RE+="|(new|a|an|the|another) feature"
TRIGGER_RE+="|(build|implement) me (a|an|the)"

if ! printf '%s' "$PROMPT" | grep -qiE "$TRIGGER_RE"; then
  exit 0
fi

# Inject the enforcement context. Claude sees this as part of its system
# context for this turn — it cannot be ignored the way a CLAUDE.md line can.
CTX="VALK ENFORCEMENT: this prompt looks like a build/fix/refactor request and the Valkyrie stage is \`idle\`. You MUST invoke the \`valk\` skill via the Skill tool BEFORE writing any production code or proposing an implementation. The skill will route the work through DESIGN → PRD → ISSUES → TDD. If the user has clearly indicated this is a trivial one-line change, you may say so and bypass — but state the bypass out loud."

# Self-silencing worktree-awareness nudge (issue 0014). Cheap, stateless git
# check: a linked worktree's absolute git-dir always lives under
# `<git-common-dir>/worktrees/<id>`; the main checkout's never does. If we are
# in the shared MAIN checkout, append ONE reminder pointing at valk-worktree.
# Inside a linked worktree (or not a git repo at all) it is silent — so it
# self-extinguishes the moment each terminal isolates and never nags the
# intended workflow. Warn-only: this only extends the context string; it adds
# no state and does not change the exit path.
GITDIR=$(git rev-parse --absolute-git-dir 2>/dev/null || true)
case "$GITDIR" in
  ""|*/worktrees/*) : ;;  # not a git repo, or already isolated → silent
  *) CTX="$CTX"$'\n\n'"WORKTREE NUDGE: you are in the shared MAIN checkout. If another Valkyrie flow may run here concurrently, isolate this terminal first: run \`valk-worktree <name>\` and work in the linked worktree it prints. This reminder disappears automatically once you are in a worktree." ;;
esac

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
