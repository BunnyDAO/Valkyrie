# Critical Fix Required for install.sh

## Problem
Line 78 in `install.sh` fails on Windows (Git Bash/MSYS) because:
```python
settings_path = Path("$SETTINGS")  # ❌ Breaks on Windows
```

## Solution
Replace lines 74-109 with:

\`\`\`python
python3 - <<'PY'
import json, os, sys
from pathlib import Path

# FIXED: Use expanduser for cross-platform path resolution
settings_path = Path(os.path.expanduser("~/.claude/settings.json"))

# Construct hook path with proper platform handling
if sys.platform == 'win32':
    # Windows: use backslashes for consistency
    hook_path = str(Path(os.path.expanduser("~/.claude/hooks/valk-guard.sh"))).replace('/', '\\')
    statusline_path = str(Path(os.path.expanduser("~/.claude/valkyrie/statusline.py"))).replace('/', '\\')
else:
    # Unix-like: use forward slashes
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
    settings_path.write_text(json.dumps(data, indent=2) + "\n")
    print(f"  + statusLine -> python3 ~/.claude/valkyrie/statusline.py")
    print(f"  + UserPromptSubmit hook -> {hook_path}")
except Exception as e:
    print(f"  ✗ Failed to write settings.json: {e}", file=sys.stderr)
    sys.exit(1)
PY
\`\`\`

## Quick Fix Command
\`\`\`bash
# Apply the fix manually
cd ~/valkyrie
# Edit install.sh and replace the Python section with the corrected version above
\`\`\`

## Files Ready
- ✅ uninstall.sh - Complete uninstallation script
- ✅ WINDOWS.md - Windows installation guide  
- ✅ .github/workflows/test-install.yml - CI/CD testing
- ✅ IMPROVEMENTS.md - Complete documentation of changes
- ⏳ install.sh - Needs manual Python section fix (lines 74-109)

See `.improvements/` directory for all completed files.
