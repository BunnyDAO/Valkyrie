#!/usr/bin/env bash
#
# uninstall.sh — Remove Valkyrie from Claude Code setup
#
# Removes everything install.sh adds — skill symlinks, the valkyrie/ helper dir,
# hook scripts, command symlinks — and un-patches Valkyrie's own entries from
# settings.json (preserving all your other settings). --restore additionally
# restores a full settings.json backup if install.sh left one.
#
# Usage:
#   ./uninstall.sh              # Remove Valkyrie; un-patch settings.json
#   ./uninstall.sh --restore    # …and restore a full settings.json backup if present

set -euo pipefail

CLAUDE_HOME="$HOME/.claude"
SKILLS_DIR="$CLAUDE_HOME/skills"
PM_DIR="$CLAUDE_HOME/valkyrie"
HOOKS_DIR="$CLAUDE_HOME/hooks"
SETTINGS="$CLAUDE_HOME/settings.json"
LOCAL_BIN="$HOME/.local/bin"
REPO="$(cd "$(dirname "$0")" && pwd)"   # uninstall.sh lives in the repo root

RESTORE_SETTINGS=false
if [[ "${1:-}" == "--restore" ]]; then
  RESTORE_SETTINGS=true
fi

echo "==> Uninstalling Valkyrie from Claude Code"
echo

# --- 1. Remove skill symlinks (source of truth: the repo's skills/ dir) ------
echo "==> Removing skill symlinks from $SKILLS_DIR"
for skill_dir in "$REPO"/skills/*/; do
  [ -d "$skill_dir" ] || continue
  skill="$(basename "$skill_dir")"
  if [ -L "$SKILLS_DIR/$skill" ]; then
    rm -f "$SKILLS_DIR/$skill"
    echo "  - Removed $skill"
  elif [ -e "$SKILLS_DIR/$skill" ]; then
    echo "  ⚠️  $skill exists but is not a symlink (skipping)"
  fi
done

# --- 2. Remove the valkyrie/ helper dir (cost-helper, stage, rates, …) -------
if [ -d "$PM_DIR" ]; then
  echo "==> Removing valkyrie directory"
  rm -rf "$PM_DIR"
  echo "  - Removed $PM_DIR"
fi

# --- 3. Remove hook scripts --------------------------------------------------
echo "==> Removing hook scripts from $HOOKS_DIR"
for hook in valk-guard.sh valk-tdd-gate.sh valk-telemetry.sh valk-loop-gate.sh; do
  if [ -f "$HOOKS_DIR/$hook" ]; then
    rm -f "$HOOKS_DIR/$hook"
    echo "  - Removed $hook"
  fi
done

# --- 4. Remove command symlinks ----------------------------------------------
echo "==> Removing command symlinks from $LOCAL_BIN"
for name in afk ralph-afk valk-worktree valk-land valk-revisit \
            read-valk-config.sh parse-loop-verdict.sh valk-issues; do
  if [ -L "$LOCAL_BIN/$name" ]; then
    rm -f "$LOCAL_BIN/$name"
    echo "  - Removed $name"
  fi
done

# --- 5. Un-patch settings.json ----------------------------------------------
# Remove only Valkyrie's own entries (the statusLine + the valk-* hooks),
# leaving every other user setting intact.
if [ -f "$SETTINGS" ] && [ -s "$SETTINGS" ]; then
  echo "==> Removing Valkyrie entries from settings.json"
  python3 - "$SETTINGS" <<'PY' || echo "  ⚠️  settings.json not valid JSON — left unchanged"
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
data = json.loads(p.read_text())
changed = False

sl = data.get("statusLine")
if isinstance(sl, dict) and "valkyrie/statusline.py" in sl.get("command", ""):
    del data["statusLine"]; changed = True

hooks = data.get("hooks")
if isinstance(hooks, dict):
    for event in list(hooks):
        kept = []
        for entry in hooks.get(event, []):
            sub = [h for h in entry.get("hooks", [])
                   if "/hooks/valk-" not in h.get("command", "")]
            if sub:
                entry["hooks"] = sub
                kept.append(entry)
            else:
                changed = True
        if kept:
            hooks[event] = kept
        else:
            del hooks[event]; changed = True
    if not hooks:
        data.pop("hooks", None)

if changed:
    p.write_text(json.dumps(data, indent=2) + "\n")
    print("  - Removed Valkyrie statusLine + hook entries")
else:
    print("  - No Valkyrie entries found")
PY
fi

if [ "$RESTORE_SETTINGS" = true ]; then
  LATEST_BACKUP="$(ls -t "$SETTINGS".bak "$SETTINGS".pre-valkyrie-* 2>/dev/null | head -1 || true)"
  if [ -n "$LATEST_BACKUP" ]; then
    echo "==> Restoring full settings.json from $LATEST_BACKUP"
    cp "$LATEST_BACKUP" "$SETTINGS"
    echo "  ✓ Restored"
  else
    echo "  - No full backup found (install.sh writes settings.json.bak only when it finds invalid JSON)"
  fi
fi

# --- Done -------------------------------------------------------------------
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Valkyrie uninstalled"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "Removed:"
echo "  - Skill symlinks from $SKILLS_DIR"
echo "  - Helper dir: $PM_DIR"
echo "  - Hook scripts (valk-*.sh) from $HOOKS_DIR"
echo "  - Command symlinks (afk, valk-*, …) from $LOCAL_BIN"
echo "  - Valkyrie statusLine + hook entries from settings.json"
echo
echo "To reinstall: ./install.sh"
echo
