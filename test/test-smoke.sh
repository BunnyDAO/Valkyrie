#!/usr/bin/env bash
#
# Smoke test — proves the harness wires up correctly.
#
# Runs the existing afk against a stubbed `claude` binary that marks
# fixture issues `status: done`. Asserts the loop completes both iterations,
# exits 0, and clears the stage marker for the temp workdir.

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO_ROOT:-$(dirname "$TEST_DIR")}"
RALPH_AFK="$REPO/scripts/afk"
STUB_DIR="$TEST_DIR/stubs"
FIXTURE_DIR="$TEST_DIR/fixtures/smoke"

# Sanity: prerequisites exist.
[ -x "$RALPH_AFK" ]              || { echo "afk missing at $RALPH_AFK"; exit 1; }
[ -x "$STUB_DIR/claude" ]        || { echo "stub claude missing at $STUB_DIR/claude"; exit 1; }
[ -d "$FIXTURE_DIR/issues" ]     || { echo "fixture issues missing"; exit 1; }

# Set up an isolated workdir and copy fixtures into it so the test can mutate
# without touching repo-tracked files.
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
mkdir -p "$WORKDIR/issues" "$WORKDIR/docs/prd"
cp "$FIXTURE_DIR/issues/"*.md "$WORKDIR/issues/"
echo "stub PRD content" > "$WORKDIR/docs/prd/dummy.md"

# Run afk against the stub. Stubs must shadow any real `claude` on PATH.
cd "$WORKDIR"
PATH="$STUB_DIR:$PATH" "$RALPH_AFK" 2 --no-confirm >"$WORKDIR/run.out" 2>&1
RC=$?

# Assertion helpers.
assert() { [ "$2" = "$3" ] || { echo "FAIL: $1 — expected '$3', got '$2'"; cat "$WORKDIR/run.out"; exit 1; }; }
assert_match() { grep -q "$2" "$1" || { echo "FAIL: '$2' not found in $1"; cat "$1"; exit 1; }; }

# 1. afk exited cleanly.
assert "exit code" "$RC" "0"

# 2. Both fixture issues got marked done.
assert_match "issues/0001-fake-feature-a.md" '^status: done'
assert_match "issues/0002-fake-feature-b.md" '^status: done'

# 3. Stage marker is cleared (file doesn't exist OR is empty).
if [ -f ".claude/valk/stage" ]; then
  STAGE="$(cat .claude/valk/stage)"
  [ -z "$STAGE" ] || { echo "FAIL: stage not cleared, got '$STAGE'"; exit 1; }
fi

# 4. AFK log directory was populated.
[ -d ".claude/valk/afk-logs" ] || { echo "FAIL: afk-logs dir missing"; exit 1; }
LOG_COUNT="$(ls .claude/valk/afk-logs/ | wc -l | tr -d ' ')"
[ "$LOG_COUNT" -ge 2 ] || { echo "FAIL: expected ≥2 log files, got $LOG_COUNT"; exit 1; }

echo "smoke test ok"
