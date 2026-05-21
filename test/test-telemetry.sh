#!/usr/bin/env bash
#
# test-telemetry.sh — the lean AFK audit log.
#
# Three layers:
#   1. hook unit   — valk-telemetry.sh logs Read/Edit during a non-idle stage
#                    (with line count) and stays silent when idle.
#   2. helper unit — telemetry-helper.py computes files/lines/edit_without_read.
#   3. afk glue    — afk prints a per-iteration telemetry summary from a session's
#                    JSONL (helper pointed at the repo copy via VALK_TELEMETRY_HELPER).

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO_ROOT:-$(dirname "$TEST_DIR")}"
HOOK="$REPO/scripts/valk-telemetry.sh"
HELPER="$REPO/scripts/telemetry-helper.py"
AFK="$REPO/scripts/afk"
STUB_DIR="$TEST_DIR/stubs"

[ -x "$HOOK" ]   || { echo "hook missing at $HOOK"; exit 1; }
[ -f "$HELPER" ] || { echo "helper missing at $HELPER"; exit 1; }

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

FAILS=0
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

# ── 1. hook unit ────────────────────────────────────────────────────────────
HOOKCWD="$WORKDIR/hook"
mkdir -p "$HOOKCWD/.claude/valk"
printf 'a\nb\nc\nd\n' > "$HOOKCWD/foo.ts"        # 4 lines

# non-idle stage → logs with the right path + line count
echo tdd > "$HOOKCWD/.claude/valk/stage"
printf '{"tool_name":"Read","cwd":"%s","session_id":"s1","tool_input":{"file_path":"%s/foo.ts"}}' \
  "$HOOKCWD" "$HOOKCWD" | bash "$HOOK"
JF="$HOOKCWD/.claude/valk/telemetry/s1.jsonl"
[ -f "$JF" ] || fail "hook: no telemetry file written during tdd stage"
grep -q '"tool":"Read"' "$JF" 2>/dev/null || fail "hook: tool not recorded"
grep -q '"lines":4' "$JF" 2>/dev/null     || fail "hook: line count wrong (want 4)"

# idle stage → silent
echo idle > "$HOOKCWD/.claude/valk/stage"
printf '{"tool_name":"Read","cwd":"%s","session_id":"s2","tool_input":{"file_path":"%s/foo.ts"}}' \
  "$HOOKCWD" "$HOOKCWD" | bash "$HOOK"
[ -f "$HOOKCWD/.claude/valk/telemetry/s2.jsonl" ] && fail "hook: logged during idle (should be silent)"

# non-file tool → ignored
echo tdd > "$HOOKCWD/.claude/valk/stage"
printf '{"tool_name":"Bash","cwd":"%s","session_id":"s3","tool_input":{"command":"ls"}}' \
  "$HOOKCWD" | bash "$HOOK"
[ -f "$HOOKCWD/.claude/valk/telemetry/s3.jsonl" ] && fail "hook: logged a non-file tool"

# ── 2. helper unit ──────────────────────────────────────────────────────────
cat > "$WORKDIR/t.jsonl" <<'JSONL'
{"t":"x","tool":"Read","path":"src/a.ts","lines":100}
{"t":"x","tool":"Edit","path":"src/a.ts","lines":110}
{"t":"x","tool":"Read","path":"src/b.ts","lines":50}
{"t":"x","tool":"Write","path":"src/c.ts","lines":20}
JSONL
OUT="$(python3 "$HELPER" summarize "$WORKDIR/t.jsonl")"
echo "$OUT" | grep -q 'files=3' || fail "helper: files (want 3) — got: $OUT"
echo "$OUT" | grep -q 'lines=180' || fail "helper: lines (want 180) — got: $OUT"
echo "$OUT" | grep -q 'edit_without_read=1' || fail "helper: edit_without_read (want 1) — got: $OUT"
echo "$OUT" | grep -q 'unread=src/c.ts' || fail "helper: unread path — got: $OUT"

# ── 3. afk glue ─────────────────────────────────────────────────────────────
mkdir -p "$WORKDIR/issues" "$WORKDIR/docs/prd" "$WORKDIR/.claude/valk/telemetry"
echo "stub PRD" > "$WORKDIR/docs/prd/dummy.md"
cat > "$WORKDIR/issues/0001-x.md" <<'ISSUE'
---
id: 0001
title: telemetry glue slice
type: AFK
status: open
blocked_by: []
---
## Acceptance criteria
- [ ] stub marks done
ISSUE
# The smoke stub emits session_id "stub"; pre-seed that session's telemetry.
cat > "$WORKDIR/.claude/valk/telemetry/stub.jsonl" <<'JSONL'
{"t":"x","tool":"Read","path":"src/a.ts","lines":100}
{"t":"x","tool":"Write","path":"src/new.ts","lines":30}
JSONL

cd "$WORKDIR"
VALK_TELEMETRY_HELPER="$HELPER" PATH="$STUB_DIR:$PATH" "$AFK" 1 --no-confirm --no-escalate \
  >"$WORKDIR/run.out" 2>&1
RC=$?
[ "$RC" -eq 0 ] || { fail "afk run exit $RC"; cat "$WORKDIR/run.out"; }
grep -q 'telemetry: 2 files / 130 lines crawled | 1 edited without reading' "$WORKDIR/run.out" \
  || { fail "afk: per-iteration telemetry line missing/incorrect"; grep -i telemetry "$WORKDIR/run.out" || true; }
grep -q 'edits w/o read:' "$WORKDIR/run.out" || fail "afk: final summary telemetry line missing"

if [ "$FAILS" -eq 0 ]; then
  echo "test-telemetry: all assertions passed"
  exit 0
else
  echo "test-telemetry: $FAILS assertion(s) failed"
  exit 1
fi
