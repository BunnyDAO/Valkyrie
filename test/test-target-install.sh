#!/usr/bin/env bash
#
# test-target-install.sh — `install.sh --target <dir>` installs Valkyrie into
# <dir>/.claude ONLY (skills + stage + hook + settings), points settings and
# the copied hook at the target, and never mutates $HOME/.claude.
#
# (Agent-Builder cycle-2 #0019 / ADR 0002 V3. Default global install is a
#  separate, unchanged code path and is NOT exercised here — running it would
#  mutate the dev machine.)

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO_ROOT:-$(dirname "$TEST_DIR")}"
INSTALL="$REPO/install.sh"

[ -f "$INSTALL" ] || { echo "install.sh missing at $INSTALL"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
TARGET="$WORK/proj"
mkdir -p "$TARGET"

HOME_SKILLS="$HOME/.claude/skills"
before="$(ls -la "$HOME_SKILLS" 2>/dev/null | md5 2>/dev/null || echo none)"

if ! bash "$INSTALL" --target "$TARGET" >/dev/null 2>&1; then
  echo "FAIL: install.sh --target exited non-zero"
  exit 1
fi

CH="$TARGET/.claude"

# 1. skills symlinked into the target
for s in valk tdd to-prd to-issues; do
  [ -L "$CH/skills/$s" ] || { echo "FAIL: missing target skill symlink: $s"; exit 1; }
done

# 2. stage helper + hook + settings live in the target
[ -f "$CH/valkyrie/stage.py" ]      || { echo "FAIL: no target stage.py"; exit 1; }
[ -f "$CH/hooks/valk-guard.sh" ]   || { echo "FAIL: no target hook"; exit 1; }
[ -f "$CH/settings.json" ]               || { echo "FAIL: no target settings.json"; exit 1; }

# 3. settings + the copied hook point at the TARGET, not $HOME
grep -q "$CH/valkyrie/statusline.py" "$CH/settings.json" \
  || { echo "FAIL: settings statusLine not target-scoped"; exit 1; }
grep -q "$CH/hooks/valk-guard.sh" "$CH/settings.json" \
  || { echo "FAIL: settings hook not target-scoped"; exit 1; }
grep -q "$CH/valkyrie/stage.py" "$CH/hooks/valk-guard.sh" \
  || { echo "FAIL: copied hook stage.py not re-pointed to target"; exit 1; }

# 4. isolation: $HOME/.claude/skills listing unchanged by a --target install
after="$(ls -la "$HOME_SKILLS" 2>/dev/null | md5 2>/dev/null || echo none)"
[ "$before" = "$after" ] || { echo "FAIL: \$HOME/.claude/skills was mutated"; exit 1; }

echo "ok: project-scoped install is isolated and target-pointed"
exit 0
