#!/usr/bin/env bash
#
# uninstall.sh — Remove Valkyrie from Claude Code setup
#
# This script safely removes all Valkyrie components and optionally
# restores your previous settings.json configuration.
#
# Usage:
#   ./uninstall.sh              # Remove Valkyrie, keep settings backup
#   ./uninstall.sh --restore    # Remove Valkyrie and restore previous settings

set -euo pipefail

CLAUDE_HOME="$HOME/.claude"
SKILLS_DIR="$CLAUDE_HOME/skills"
PM_DIR="$CLAUDE_HOME/valkyrie"
HOOKS_DIR="$CLAUDE_HOME/hooks"
SETTINGS="$CLAUDE_HOME/settings.json"
LOCAL_BIN="$HOME/.local/bin"

RESTORE_SETTINGS=false
if [[ "${1:-}" == "--restore" ]]; then
  RESTORE_SETTINGS=true
fi

echo "==> Uninstalling Valkyrie from Claude Code"
echo

# --- 1. Remove skill symlinks -----------------------------------------------

echo "==> Removing skill symlinks from $SKILLS_DIR"
for skill in grill-me refactor-spaghetti tdd to-issues to-prd valk zoom-out; do
  if [ -L "$SKILLS_DIR/$skill" ]; then
    rm -f "$SKILLS_DIR/$skill"
    echo "  - Removed $skill"
  elif [ -e "$SKILLS_DIR/$skill" ]; then
    echo "  ⚠️  $skill exists but is not a symlink (skipping)"
  fi
done

# --- 2. Remove valkyrie directory -------------------------------------------

if [ -d "$PM_DIR" ]; then
  echo "==> Removing valkyrie directory"
  rm -rf "$PM_DIR"
  echo "  - Removed $PM_DIR"
fi

# --- 3. Remove hook ---------------------------------------------------------

if [ -f "$HOOKS_DIR/valk-guard.sh" ]; then
  echo "==> Removing valk-guard hook"
  rm -f "$HOOKS_DIR/valk-guard.sh"
  echo "  - Removed $HOOKS_DIR/valk-guard.sh"
fi

# --- 4. Remove afk symlinks -------------------------------------------------

echo "==> Removing afk commands from $LOCAL_BIN"
for name in afk ralph-afk; do
  if [ -L "$LOCAL_BIN/$name" ]; then
    rm -f "$LOCAL_BIN/$name"
    echo "  - Removed $name"
  fi
done

# --- 5. Restore or keep settings.json ---------------------------------------

if [ "$RESTORE_SETTINGS" = true ]; then
  # Find most recent backup
  LATEST_BACKUP=$(ls -t "$SETTINGS".pre-valkyrie-* 2>/dev/null | head -1 || echo "")

  if [ -n "$LATEST_BACKUP" ]; then
    echo "==> Restoring settings.json from backup"
    cp "$LATEST_BACKUP" "$SETTINGS"
    echo "  ✓ Restored from $LATEST_BACKUP"
  else
    echo "  ⚠️  No backup found to restore"
  fi
else
  # List available backups
  BACKUPS=$(ls -t "$SETTINGS".pre-valkyrie-* 2>/dev/null || echo "")

  if [ -n "$BACKUPS" ]; then
    echo "==> Settings.json backups available (not restored)"
    echo "$BACKUPS" | while read -r backup; do
      echo "  - $backup"
    done
    echo
    echo "To restore manually:"
    echo "  cp <backup-file> $SETTINGS"
  else
    echo "  - No settings.json backups found"
  fi
fi

# --- Done -------------------------------------------------------------------

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Valkyrie uninstalled successfully"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "What was removed:"
echo "  - 7 skill symlinks from $SKILLS_DIR"
echo "  - Valkyrie directory: $PM_DIR"
echo "  - Hook script: $HOOKS_DIR/valk-guard.sh"
echo "  - afk command symlinks from $LOCAL_BIN"
echo

if [ "$RESTORE_SETTINGS" = false ]; then
  echo "Your settings.json was not modified."
  echo "Backups are still available if you need to restore."
  echo
  echo "To restore settings to pre-Valkyrie state:"
  echo "  ./uninstall.sh --restore"
fi

echo
echo "To reinstall Valkyrie:"
echo "  ./install.sh"
echo
