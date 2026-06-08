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

# install_link — symlink with verify-and-copy fallback.
#
# Why this exists: on Git Bash (Windows) without developer mode / admin,
# `ln -sfn` silently falls back to a directory copy that never re-syncs on
# subsequent install.sh runs. Users end up running stale skills weeks out of
# date with no warning. Detect via `readlink` and copy explicitly when the
# symlink didn't take, so `install.sh` is idempotent on every platform.
#
# Echoes a per-target verification line (with SKILL.md byte count where
# present) so users can confirm the install actually refreshed.
install_link() {
  src="$1"; target="$2"; label="$3"
  # First-install backup: only when target exists, isn't a symlink, AND no
  # .bak exists yet. (Our own previous copy-mode install is also a non-
  # symlink dir — without this guard we'd accumulate .bak siblings on every
  # re-run.)
  if [ -e "$target" ] && [ ! -L "$target" ] && [ ! -e "${target}.bak" ]; then
    echo "  - $label: existing non-symlink at $target — backing up to ${target}.bak"
    mv "$target" "${target}.bak"
  elif [ -e "$target" ] && [ ! -L "$target" ]; then
    # Existing non-symlink + .bak already present → our previous copy-mode
    # install. Remove so cp -R below can refresh it.
    rm -rf "$target"
  fi
  ln -sfn "$src" "$target" 2>/dev/null || true
  if [ -L "$target" ] && [ "$(readlink "$target" 2>/dev/null)" = "$src" ]; then
    if [ -f "$target/SKILL.md" ]; then
      sz=$(wc -c < "$target/SKILL.md" 2>/dev/null | tr -d ' ')
      echo "  + $label -> $src (symlink, SKILL.md=${sz:-?}B)"
    else
      echo "  + $label -> $src (symlink)"
    fi
  else
    # ln -sfn didn't produce a real symlink (Git Bash / Windows without
    # dev mode). Wipe whatever it created and copy explicitly so the install
    # is current; future install.sh runs re-sync via the same path.
    rm -rf "$target" 2>/dev/null || true
    cp -R "$src" "$target"
    if [ -f "$target/SKILL.md" ]; then
      sz=$(wc -c < "$target/SKILL.md" 2>/dev/null | tr -d ' ')
      echo "  + $label -> $src (COPY mode, SKILL.md=${sz:-?}B — symlinks unavailable; re-run install.sh after pulls to re-sync)"
    else
      echo "  + $label -> $src (COPY mode — symlinks unavailable; re-run install.sh after pulls to re-sync)"
    fi
  fi
}

# --- 1. skills --------------------------------------------------------------

echo "==> linking skills into $SKILLS_DIR"
for skill_md in "$REPO"/skills/*/SKILL.md; do
  src_dir="$(dirname "$skill_md")"
  name="$(basename "$src_dir")"
  install_link "$src_dir" "$SKILLS_DIR/$name" "$name"
done

# --- 2. statusline + stage helper ------------------------------------------

echo "==> installing statusline + stage helper into $PM_DIR"
cp "$REPO/statusline/statusline.py" "$PM_DIR/statusline.py"
cp "$REPO/statusline/stage.py" "$PM_DIR/stage.py"
chmod +x "$PM_DIR/statusline.py" "$PM_DIR/stage.py"
echo "  + $PM_DIR/statusline.py"
echo "  + $PM_DIR/stage.py"

echo "==> installing cost helper + rate table into $PM_DIR"
cp "$REPO/scripts/cost-helper.py"      "$PM_DIR/cost-helper.py"
cp "$REPO/scripts/telemetry-helper.py" "$PM_DIR/telemetry-helper.py"
cp "$REPO/scripts/rates.json"          "$PM_DIR/rates.json"
cp "$REPO/scripts/crew-shim"           "$PM_DIR/crew-shim"
chmod +x "$PM_DIR/cost-helper.py" "$PM_DIR/telemetry-helper.py" "$PM_DIR/crew-shim"
echo "  + $PM_DIR/cost-helper.py"
echo "  + $PM_DIR/telemetry-helper.py"
echo "  + $PM_DIR/rates.json"
echo "  + $PM_DIR/crew-shim"

# --- 3. hooks: UserPromptSubmit guard + PreToolUse TDD gate ----------------

echo "==> installing hooks into $HOOKS_DIR"
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

# PreToolUse hard gate: mechanically blocks production-code edits until TDD.
# Reads the stage from the tool's cwd directly, so no --target re-point is needed.
cp "$REPO/scripts/valk-tdd-gate.sh" "$HOOKS_DIR/valk-tdd-gate.sh"
chmod +x "$HOOKS_DIR/valk-tdd-gate.sh"
echo "  + $HOOKS_DIR/valk-tdd-gate.sh"

# PostToolUse telemetry: the lean AFK audit log (files/lines, edit-without-read).
# Stage-gated and self-contained, so no --target re-point is needed.
cp "$REPO/scripts/valk-telemetry.sh" "$HOOKS_DIR/valk-telemetry.sh"
chmod +x "$HOOKS_DIR/valk-telemetry.sh"
echo "  + $HOOKS_DIR/valk-telemetry.sh"

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
gate_path = "$CLAUDE_HOME/hooks/valk-tdd-gate.sh"
telemetry_path = "$CLAUDE_HOME/hooks/valk-telemetry.sh"
statusline_path = "$CLAUDE_HOME/valkyrie/statusline.py"

# On Windows, convert to Git Bash format (/c/Users/... instead of C:Users...)
if sys.platform == 'win32' and len(hook_path) > 2 and hook_path[1] == ':':
    # Convert C:Users... to /c/Users/... (using chr(92) for backslash to avoid escaping issues)
    hook_path = '/' + hook_path[0].lower() + hook_path[2:].replace(chr(92), '/')
    gate_path = '/' + gate_path[0].lower() + gate_path[2:].replace(chr(92), '/')
    telemetry_path = '/' + telemetry_path[0].lower() + telemetry_path[2:].replace(chr(92), '/')
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

# Merge the PreToolUse TDD gate the same idempotent way. The matcher keeps it off
# the hot path for tools it never acts on.
pre = hooks.setdefault("PreToolUse", [])
gate_wired = any(
    any(h.get("command") == gate_path for h in entry.get("hooks", []))
    for entry in pre if isinstance(entry, dict)
)
if not gate_wired:
    pre.append({
        "matcher": "Edit|MultiEdit|Write|NotebookEdit|Bash",
        "hooks": [{"type": "command", "command": gate_path}],
    })

# Merge the PostToolUse telemetry hook the same idempotent way.
post = hooks.setdefault("PostToolUse", [])
telem_wired = any(
    any(h.get("command") == telemetry_path for h in entry.get("hooks", []))
    for entry in post if isinstance(entry, dict)
)
if not telem_wired:
    post.append({
        "matcher": "Read|Edit|MultiEdit|Write|NotebookEdit",
        "hooks": [{"type": "command", "command": telemetry_path}],
    })

# Ensure parent directory exists (important for Windows)
settings_path.parent.mkdir(parents=True, exist_ok=True)

try:
    settings_path.write_text(json.dumps(data, indent=2) + "\\n")
    print(f"  + statusLine -> python3 {statusline_path}")
    print(f"  + UserPromptSubmit hook -> {hook_path}")
    print(f"  + PreToolUse TDD gate -> {gate_path}")
    print(f"  + PostToolUse telemetry -> {telemetry_path}")
except Exception as e:
    print(f"  ✗ Failed to write settings.json: {e}", file=sys.stderr)
    sys.exit(1)
PY

# --- 5. afk -----------------------------------------------------------

echo "==> linking afk into $LOCAL_BIN"
chmod +x "$REPO/scripts/afk"
for name in afk ralph-afk; do
  install_link "$REPO/scripts/afk" "$LOCAL_BIN/$name" "$name"
done

# valk-worktree: one-command per-flow git-worktree isolation — the cure for
# concurrent flows on one checkout. PATH-registered exactly like afk.
chmod +x "$REPO/scripts/valk-worktree"
install_link "$REPO/scripts/valk-worktree" "$LOCAL_BIN/valk-worktree" "valk-worktree"

# valk-land: ergonomic, race-free integrate-back companion to valk-worktree.
# PATH-registered exactly like afk / valk-worktree.
chmod +x "$REPO/scripts/valk-land"
install_link "$REPO/scripts/valk-land" "$LOCAL_BIN/valk-land" "valk-land"

# valk-revisit: loop-back — record a mid-stream requirement change + rewind
# the stage. The orchestrator (/valk) detects changes and calls this on
# confirm; users can also invoke it directly. PATH-registered like the rest.
chmod +x "$REPO/scripts/valk-revisit"
install_link "$REPO/scripts/valk-revisit" "$LOCAL_BIN/valk-revisit" "valk-revisit"

# read-valk-config / parse-loop-verdict: helpers the inner-loop skill prose
# (#0009) calls by name — read the loop: pairs list + a critic's verdict. Other
# scripts still call read-valk-config.sh by sibling path; this just also exposes
# both on PATH so the crew can invoke them.
chmod +x "$REPO/scripts/read-valk-config.sh" "$REPO/scripts/parse-loop-verdict.sh"
install_link "$REPO/scripts/read-valk-config.sh" "$LOCAL_BIN/read-valk-config.sh" "read-valk-config.sh"
install_link "$REPO/scripts/parse-loop-verdict.sh" "$LOCAL_BIN/parse-loop-verdict.sh" "parse-loop-verdict.sh"

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
echo "                         afk 10 --cli copilot    (uses GitHub Copilot CLI)"
