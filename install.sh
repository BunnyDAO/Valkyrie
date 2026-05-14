#!/usr/bin/env bash
#
# install.sh — wire Valkyrie into your local Claude Code setup.
#
# What this does:
#   1. Symlinks each skill in skills/ into ~/.claude/skills/
#   2. Copies statusline.py + stage.py into ~/.claude/valkyrie/
#   3. Installs the UserPromptSubmit hook into ~/.claude/hooks/
#   4. Patches ~/.claude/settings.json to wire the statusline + hook
#   5. Symlinks scripts/afk into ~/.local/bin/ as both `afk` and `ralph-afk`
#      (creating ~/.local/bin/ if needed; ralph-afk kept as a BC alias)
#
# Idempotent: safe to re-run after a git pull.

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_HOME="$HOME/.claude"
SKILLS_DIR="$CLAUDE_HOME/skills"
PM_DIR="$CLAUDE_HOME/valkyrie"
HOOKS_DIR="$CLAUDE_HOME/hooks"
SETTINGS="$CLAUDE_HOME/settings.json"
LOCAL_BIN="$HOME/.local/bin"

mkdir -p "$SKILLS_DIR" "$PM_DIR" "$HOOKS_DIR" "$LOCAL_BIN"

# --- 1. skills --------------------------------------------------------------

echo "==> linking skills into $SKILLS_DIR"
for skill_md in "$REPO"/skills/*/SKILL.md; do
  src_dir="$(dirname "$skill_md")"
  name="$(basename "$src_dir")"
  target="$SKILLS_DIR/$name"

  if [ -e "$target" ] && [ ! -L "$target" ]; then
    echo "  - $name: existing non-symlink at $target — backing up to ${target}.bak"
    mv "$target" "${target}.bak"
  fi
  ln -sfn "$src_dir" "$target"
  echo "  + $name -> $src_dir"
done

# --- 2. statusline + stage helper ------------------------------------------

echo "==> installing statusline + stage helper into $PM_DIR"
cp "$REPO/statusline/statusline.py" "$PM_DIR/statusline.py"
cp "$REPO/statusline/stage.py" "$PM_DIR/stage.py"
chmod +x "$PM_DIR/statusline.py" "$PM_DIR/stage.py"
echo "  + $PM_DIR/statusline.py"
echo "  + $PM_DIR/stage.py"

echo "==> installing cost helper + rate table into $PM_DIR"
cp "$REPO/scripts/cost-helper.py" "$PM_DIR/cost-helper.py"
cp "$REPO/scripts/rates.json"     "$PM_DIR/rates.json"
chmod +x "$PM_DIR/cost-helper.py"
echo "  + $PM_DIR/cost-helper.py"
echo "  + $PM_DIR/rates.json"

# --- 3. UserPromptSubmit hook ----------------------------------------------

echo "==> installing UserPromptSubmit hook into $HOOKS_DIR"
cp "$REPO/scripts/valk-guard.sh" "$HOOKS_DIR/valk-guard.sh"
chmod +x "$HOOKS_DIR/valk-guard.sh"
echo "  + $HOOKS_DIR/valk-guard.sh"

# --- 4. patch settings.json -------------------------------------------------

echo "==> wiring statusline + hook into $SETTINGS"
if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

# Use python to do a safe in-place merge — preserves user's existing keys.
python3 - <<PY
import json, os, sys
from pathlib import Path

settings_path = Path(os.path.expanduser("~/.claude/settings.json"))
if sys.platform == 'win32':
    hook_path = str(Path(os.path.expanduser("~/.claude/hooks/valk-guard.sh"))).replace('/', '\\\\')
    statusline_path = str(Path(os.path.expanduser("~/.claude/valkyrie/statusline.py"))).replace('/', '\\\\')
else:
    hook_path = os.path.expanduser("~/.claude/hooks/valk-guard.sh")
    statusline_path = os.path.expanduser("~/.claude/valkyrie/statusline.py")
data = {}
if settings_path.exists() and settings_path.stat().st_size > 0:
    try:
        data = json.loads(settings_path.read_text())
    except json.JSONDecodeError:
        backup = settings_path.with_suffix(".json.bak")
        backup.write_text(settings_path.read_text())
        print(f"  ! existing settings.json was invalid JSON — backed up to {backup}", file=sys.stderr)
        data = {}

data["statusLine"] = {
    "type": "command",
    "command": f"python3 {statusline_path}",
    "padding": 0,
}

# Merge the hook entry without clobbering existing UserPromptSubmit hooks.
hooks = data.setdefault("hooks", {})
ups = hooks.setdefault("UserPromptSubmit", [])
already_wired = any(
    any(h.get("command") == hook_path for h in entry.get("hooks", []))
    for entry in ups if isinstance(entry, dict)
)
if not already_wired:
    ups.append({"hooks": [{"type": "command", "command": hook_path}]})

# Ensure parent directory exists (important for Windows)
settings_path.parent.mkdir(parents=True, exist_ok=True)

try:
    settings_path.write_text(json.dumps(data, indent=2) + "\\n")
    print(f"  + statusLine -> python3 ~/.claude/valkyrie/statusline.py")
    print(f"  + UserPromptSubmit hook -> {hook_path}")
except Exception as e:
    print(f"  ✗ Failed to write settings.json: {e}", file=sys.stderr)
    sys.exit(1)
PY

# --- 5. afk -----------------------------------------------------------

echo "==> linking afk into $LOCAL_BIN"
chmod +x "$REPO/scripts/afk"
for name in afk ralph-afk; do
  target="$LOCAL_BIN/$name"
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    echo "  - existing non-symlink $name in $LOCAL_BIN — backing up to ${target}.bak"
    mv "$target" "${target}.bak"
  fi
  ln -sfn "$REPO/scripts/afk" "$target"
  echo "  + $name -> $REPO/scripts/afk"
done

if ! echo ":$PATH:" | grep -q ":$LOCAL_BIN:"; then
  echo
  echo "  NOTE: $LOCAL_BIN is not on your PATH. Add this to your shell rc:"
  echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# --- done -------------------------------------------------------------------

echo
echo "Valkyrie installed. Restart Claude Code to pick up the new statusline."
echo
echo "Try it:"
echo "  - In any project: ask Claude to 'add a feature' — /valk will gate the flow."
echo "  - To run autonomously: afk 10                  (uses claude)"
echo "                         afk 10 --cli codex      (uses codex)"
