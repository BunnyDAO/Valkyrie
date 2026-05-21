#!/usr/bin/env bash
# Valkyrie PostToolUse telemetry — the lean AFK audit log.
#
# Logs each file Read / Edit / Write (path + line count) to a per-session JSONL
# under <repo>/.claude/valk/telemetry/. afk summarizes it after each iteration
# (files touched, lines crawled, files edited-without-reading) so an unattended
# run leaves an audit trail you can trust. Honest scope: this records the
# tool-call trail, not the model's reasoning — "edited without reading" is a
# proxy for inference, not proof of it.
#
# Only logs while a Valkyrie stage is active (non-idle), so ad-hoc sessions stay
# clean. Wired in ~/.claude/settings.json under hooks.PostToolUse (install.sh).
# Always exits 0 — telemetry must never disturb the tool that just ran.

set -u

INPUT=$(cat)

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
case "$TOOL" in
  Read|Edit|MultiEdit|Write|NotebookEdit) ;;
  *) exit 0 ;;
esac

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[ -z "$CWD" ] && CWD="$PWD"

# Only record during an active workflow stage; skip idle/ad-hoc sessions.
read_stage() {
  local f
  for f in "$CWD/.claude/valk/stage" "$HOME/.claude/valk/stage"; do
    [ -f "$f" ] && { tr -d '[:space:]' < "$f"; return; }
  done
  printf 'idle'
}
STAGE=$(read_stage)
[ "${STAGE:-idle}" = "idle" ] && exit 0

FP=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' 2>/dev/null)
[ -z "$FP" ] && exit 0

SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // "nosession"' 2>/dev/null)
[ -z "$SESSION" ] && SESSION="nosession"

# Line count of the file as it stands now (PostToolUse runs after the tool, so
# edits/writes are already applied). A reasonable proxy for "lines crawled".
LINES=0
if [ -f "$FP" ]; then
  n=$(wc -l < "$FP" 2>/dev/null | tr -d ' ')
  [[ "$n" =~ ^[0-9]+$ ]] && LINES="$n"
fi

TELEM_DIR="$CWD/.claude/valk/telemetry"
mkdir -p "$TELEM_DIR" 2>/dev/null || exit 0
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

jq -nc \
  --arg t "$TS" --arg tool "$TOOL" --arg path "$FP" --argjson lines "$LINES" \
  '{t:$t, tool:$tool, path:$path, lines:$lines}' \
  >> "$TELEM_DIR/$SESSION.jsonl" 2>/dev/null || true

exit 0
