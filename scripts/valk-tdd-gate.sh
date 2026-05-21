#!/usr/bin/env bash
# Valkyrie PreToolUse gate — the hard wall behind "no production code before TDD".
#
# Valkyrie's stage rules are honor-based (the model chooses to obey SKILL.md), and
# honor drifts — especially mid-long-conversation and in AFK runs where no human is
# watching. This hook turns the load-bearing promise into a MECHANICAL block: while a
# flow is in a pre-TDD stage (design / prd / issues …), edits to production code are
# DENIED. Workflow artifacts (docs, issues, the domain docs, any *.md) stay writable
# so the earlier stages can still do their job.
#
# Wired in ~/.claude/settings.json under hooks.PreToolUse (install.sh does this).
#
# Honest limits: airtight for Edit/Write/NotebookEdit (clear file_path); best-effort
# for Bash (Turing-complete — can't catch every write, so it only blocks writes that
# clearly target source-code files). Threat model is model DRIFT, not a determined
# human — it's the user's machine and the hook can be disabled. Against drift, this is
# a real wall.

set -u

INPUT=$(cat)

# cwd first (cheapest path to the stage decision): the common case is a non-gated
# stage, where we exit before parsing anything else.
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""')
[[ -z "$CWD" ]] && CWD="$PWD"

# Resolve the current stage exactly as stage.py does: project-local, then global,
# then idle. Read the file directly — no python subprocess on every tool call.
read_stage() {
  local f
  for f in "$CWD/.claude/valk/stage" "$HOME/.claude/valk/stage"; do
    if [[ -f "$f" ]]; then
      tr -d '[:space:]' < "$f"
      return 0
    fi
  done
  printf 'idle'
}
STAGE=$(read_stage)
STAGE=${STAGE:-idle}

# Only the pre-TDD flow stages gate edits. Everything else is allowed:
#   idle            — not in a Valkyrie flow (valk-guard nudges build prompts)
#   tdd / afk       — implementation stages, code is the whole point
#   refactor / zoom — escape hatches the user invokes deliberately
case "$STAGE" in
  design|grill-with-docs|prd|to-prd|prd-review|issues|to-issues) ;;  # gated
  *) exit 0 ;;                                                        # allowed
esac

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')

HINT="Valkyrie blocks production-code edits until the TDD stage (current stage: ${STAGE}). Finish the flow through to TDD, or run \`/valk --skip-to tdd\` if you intend to implement now. (Docs, PRDs, issues, and any *.md stay writable.)"

deny() {
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

# Workflow artifacts are writable at any stage: all markdown, plus the docs/issues/
# stage directories regardless of where the repo sits.
is_artifact() {
  case "$1" in
    *.md|*.markdown) return 0 ;;
    */docs/*|docs/*) return 0 ;;
    */issues/*|issues/*) return 0 ;;
    */.claude/valk/*|.claude/valk/*) return 0 ;;
  esac
  return 1
}

# Source-code file extensions — used only for the best-effort Bash check.
SRC_EXT='\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs|java|rb|c|cc|cpp|cxx|h|hpp|hh|cs|php|swift|kt|kts|scala|clj|cljs|ex|exs|erl|hs|ml|mli|mm|sql|vue|svelte|dart|lua|jl|pl|pm|groovy|gradle)'

case "$TOOL" in
  Edit|MultiEdit|Write|NotebookEdit)
    FP=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""')
    [[ -z "$FP" ]] && exit 0          # nothing to inspect — don't block blindly
    is_artifact "$FP" && exit 0
    deny "${HINT} (blocked edit to: ${FP})"
    ;;
  Bash)
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')
    # Best-effort: deny only when a write operation clearly targets a source file.
    # Conservative on purpose — benign writes (logs, /dev/null, /tmp, *.md) pass, so
    # the gate never breaks ordinary shell use while still stopping `echo … > x.ts`.
    if printf '%s' "$CMD" | grep -qE '(>>?|[[:space:]]tee[[:space:]]|sed -i|dd of=|[[:space:]]cp[[:space:]]|[[:space:]]mv[[:space:]]|[[:space:]]install[[:space:]])' \
       && printf '%s' "$CMD" | grep -qiE "${SRC_EXT}([[:space:]\"';|&)]|\$)"; then
      deny "${HINT} (blocked a shell command that writes to a source file)"
    fi
    exit 0
    ;;
  *)
    exit 0 ;;
esac
