---
name: setup
version: 0.1.0
description: One-time post-install wiring for Valkyrie. Copies stage helpers and hook scripts into the correct Claude home directory and patches settings.json to register the statusline and 4 hooks. Safe to re-run. Use after installing Valkyrie via the Claude Code plugin marketplace.
---

# Valkyrie Setup

Run this once after installing Valkyrie from the marketplace. It wires the statusline, hooks, and stage helpers that the skills depend on.

## What it does

1. Detects install scope — project (`.claude/` in CWD) or global (`~/.claude/`)
2. Copies `stage.py`, `statusline.py`, `cost-helper.py`, `telemetry-helper.py`, `rates.json`, and `crew-shim` into `$CLAUDE_HOME/valkyrie/`
3. Copies the 4 hook scripts into `$CLAUDE_HOME/hooks/` and makes them executable
4. Patches `$CLAUDE_HOME/settings.json` with the statusline command and all 4 hook entries (idempotent — safe to re-run)

## How to invoke

Say "set up valkyrie" or `/valkyrie:setup` after a marketplace install.

## Instructions

Determine the install scope:

```bash
# Detect scope: prefer project-local if .claude/ exists in cwd
if [ -d ".claude" ]; then
  CLAUDE_HOME="$(pwd)/.claude"
else
  CLAUDE_HOME="$HOME/.claude"
fi
echo "Installing into: $CLAUDE_HOME"
```

Locate the plugin's script sources. The marketplace copies scripts into the plugin directory. Find the valkyrie plugin source:

```bash
# Find the setup skill's own directory to locate sibling scripts
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SKILL_DIR/../.." && pwd)"
SCRIPTS_DIR="$PLUGIN_DIR/scripts"
STATUSLINE_DIR="$PLUGIN_DIR/statusline"
```

Create directories and copy helpers:

```bash
PM_DIR="$CLAUDE_HOME/valkyrie"
HOOKS_DIR="$CLAUDE_HOME/hooks"
mkdir -p "$PM_DIR" "$HOOKS_DIR"

# Stage + statusline
cp "$STATUSLINE_DIR/stage.py"      "$PM_DIR/stage.py"
cp "$STATUSLINE_DIR/statusline.py" "$PM_DIR/statusline.py"
chmod +x "$PM_DIR/stage.py" "$PM_DIR/statusline.py"

# Cost + telemetry helpers
cp "$SCRIPTS_DIR/cost-helper.py"      "$PM_DIR/cost-helper.py"
cp "$SCRIPTS_DIR/telemetry-helper.py" "$PM_DIR/telemetry-helper.py"
cp "$SCRIPTS_DIR/rates.json"          "$PM_DIR/rates.json"
cp "$SCRIPTS_DIR/crew-shim"           "$PM_DIR/crew-shim"
chmod +x "$PM_DIR/cost-helper.py" "$PM_DIR/telemetry-helper.py" "$PM_DIR/crew-shim"

# Hooks
for hook in valk-guard.sh valk-tdd-gate.sh valk-telemetry.sh valk-loop-gate.sh; do
  cp "$SCRIPTS_DIR/$hook" "$HOOKS_DIR/$hook"
  chmod +x "$HOOKS_DIR/$hook"
done

echo "Helpers and hooks installed."
```

Patch settings.json using Python for safe idempotent merge:

```bash
python3 - <<PY
import json, sys
from pathlib import Path

claude_home = "$CLAUDE_HOME"
settings_path = Path(claude_home) / "settings.json"
hook_path      = f"{claude_home}/hooks/valk-guard.sh"
gate_path      = f"{claude_home}/hooks/valk-tdd-gate.sh"
telemetry_path = f"{claude_home}/hooks/valk-telemetry.sh"
loopgate_path  = f"{claude_home}/hooks/valk-loop-gate.sh"
statusline_path = f"{claude_home}/valkyrie/statusline.py"

data = {}
if settings_path.exists() and settings_path.stat().st_size > 0:
    try:
        data = json.loads(settings_path.read_text())
    except json.JSONDecodeError:
        backup = settings_path.with_suffix(".json.bak")
        backup.write_text(settings_path.read_text())
        print(f"  ! settings.json was invalid — backed up to {backup}", file=sys.stderr)

data["statusLine"] = {"type": "command", "command": f"python3 {statusline_path}", "padding": 0}

hooks = data.setdefault("hooks", {})

ups = hooks.setdefault("UserPromptSubmit", [])
if not any(any(h.get("command") == hook_path for h in e.get("hooks", [])) for e in ups if isinstance(e, dict)):
    ups.append({"hooks": [{"type": "command", "command": hook_path}]})

pre = hooks.setdefault("PreToolUse", [])
if not any(any(h.get("command") == gate_path for h in e.get("hooks", [])) for e in pre if isinstance(e, dict)):
    pre.append({"matcher": "Edit|MultiEdit|Write|NotebookEdit|Bash", "hooks": [{"type": "command", "command": gate_path}]})

post = hooks.setdefault("PostToolUse", [])
if not any(any(h.get("command") == telemetry_path for h in e.get("hooks", [])) for e in post if isinstance(e, dict)):
    post.append({"matcher": "Read|Edit|MultiEdit|Write|NotebookEdit", "hooks": [{"type": "command", "command": telemetry_path}]})

stop = hooks.setdefault("Stop", [])
if not any(any(h.get("command") == loopgate_path for h in e.get("hooks", [])) for e in stop if isinstance(e, dict)):
    stop.append({"hooks": [{"type": "command", "command": loopgate_path}]})

settings_path.parent.mkdir(parents=True, exist_ok=True)
settings_path.write_text(json.dumps(data, indent=2) + "\n")
print(f"  + statusLine -> {statusline_path}")
print(f"  + UserPromptSubmit hook -> {hook_path}")
print(f"  + PreToolUse TDD gate -> {gate_path}")
print(f"  + PostToolUse telemetry -> {telemetry_path}")
print(f"  + Stop loop gate -> {loopgate_path}")
PY
```

After both steps succeed, tell the user:

> Valkyrie is fully wired. The statusline will appear on your next session start. Hooks are active immediately. Run `/valk` to start your first workflow.

If any step fails (file not found, permission error), report the exact error and suggest running `install.sh` from the Valkyrie repo as a fallback.
