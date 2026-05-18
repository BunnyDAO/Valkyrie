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

# --target <dir> installs Valkyrie into <dir>/.claude (project-scoped, opt-in)
# instead of the global ~/.claude. Default is unchanged: $HOME/.claude.
TARGET_HOME=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) TARGET_HOME="${2:?--target needs a directory}"; shift 2 ;;
    *) echo "install.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -n "$TARGET_HOME" ]; then
  mkdir -p "$TARGET_HOME/.claude"
  CLAUDE_HOME="$(cd "$TARGET_HOME/.claude" && pwd)"
  SCOPED=1
else
  CLAUDE_HOME="$HOME/.claude"
  SCOPED=0
fi

SKILLS_DIR="$CLAUDE_HOME/skills"
PM_DIR="$CLAUDE_HOME/valkyrie"
HOOKS_DIR="$CLAUDE_HOME/hooks"
SETTINGS="$CLAUDE_HOME/settings.json"
LOCAL_BIN="$HOME/.local/bin"

mkdir -p "$SKILLS_DIR" "$PM_DIR" "$HOOKS_DIR"
[ "$SCOPED" -eq 0 ] && mkdir -p "$LOCAL_BIN"

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
cp "$REPO/scripts/crew-shim"      "$PM_DIR/crew-shim"
chmod +x "$PM_DIR/cost-helper.py" "$PM_DIR/crew-shim"
echo "  + $PM_DIR/cost-helper.py"
echo "  + $PM_DIR/rates.json"
echo "  + $PM_DIR/crew-shim"

# --- 3. UserPromptSubmit hook ----------------------------------------------

echo "==> installing UserPromptSubmit hook into $HOOKS_DIR"
cp "$REPO/scripts/valk-guard.sh" "$HOOKS_DIR/valk-guard.sh"
chmod +x "$HOOKS_DIR/valk-guard.sh"
if [ "$SCOPED" -eq 1 ]; then
  # Re-point the copied hook's stage helper at the project, not $HOME.
  sed -i.bak \
    "s|\"\$HOME/.claude/valkyrie/stage.py\"|\"$CLAUDE_HOME/valkyrie/stage.py\"|" \
    "$HOOKS_DIR/valk-guard.sh"
  rm -f "$HOOKS_DIR/valk-guard.sh.bak"
fi
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

settings_path = Path("$SETTINGS")
# Use forward slashes for all platforms - Git Bash on Windows understands them
# $CLAUDE_HOME-derived so a --target (project-scoped) install writes
# target-scoped paths; for the default global install this is ~/.claude.
hook_path = "$CLAUDE_HOME/hooks/valk-guard.sh"
statusline_path = "$CLAUDE_HOME/valkyrie/statusline.py"

# On Windows, convert to Git Bash format (/c/Users/... instead of C:Users...)
if sys.platform == 'win32' and len(hook_path) > 2 and hook_path[1] == ':':
    # Convert C:Users... to /c/Users/... (using chr(92) for backslash to avoid escaping issues)
    hook_path = '/' + hook_path[0].lower() + hook_path[2:].replace(chr(92), '/')
    statusline_path = '/' + statusline_path[0].lower() + statusline_path[2:].replace(chr(92), '/')
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
    print(f"  + statusLine -> python3 {statusline_path}")
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

# valk-worktree: one-command per-flow git-worktree isolation — the cure for
# concurrent flows on one checkout. PATH-registered exactly like afk.
chmod +x "$REPO/scripts/valk-worktree"
target="$LOCAL_BIN/valk-worktree"
if [ -e "$target" ] && [ ! -L "$target" ]; then
  echo "  - existing non-symlink valk-worktree in $LOCAL_BIN — backing up to ${target}.bak"
  mv "$target" "${target}.bak"
fi
ln -sfn "$REPO/scripts/valk-worktree" "$target"
echo "  + valk-worktree -> $REPO/scripts/valk-worktree"

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
