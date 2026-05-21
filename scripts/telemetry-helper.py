#!/usr/bin/env python3
"""Summarize a Valkyrie telemetry JSONL into an audit one-liner.

Usage:
    telemetry-helper.py summarize <session.jsonl>

Prints (stdout, space-separated key=value):
    files=<unique paths touched>
    lines=<sum of per-file line counts>
    edit_without_read=<paths edited but never read in this session>
    unread=<comma-joined unread-edited paths, or "-">

"edited without reading" is a proxy for inference — the agent changed a file it
never opened in this session. It's a signal to eyeball, not proof of a mistake.
"""

from __future__ import annotations

import json
import sys

EDIT_TOOLS = {"Edit", "MultiEdit", "Write", "NotebookEdit"}


def summarize(path: str) -> int:
    # path -> {"read": bool, "edit": bool, "lines": int}
    seen: dict[str, dict] = {}
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue
                p = entry.get("path")
                if not p:
                    continue
                rec = seen.setdefault(p, {"read": False, "edit": False, "lines": 0})
                tool = entry.get("tool", "")
                if tool == "Read":
                    rec["read"] = True
                if tool in EDIT_TOOLS:
                    rec["edit"] = True
                try:
                    rec["lines"] = max(rec["lines"], int(entry.get("lines", 0) or 0))
                except (TypeError, ValueError):
                    pass
    except FileNotFoundError:
        print("files=0 lines=0 edit_without_read=0 unread=-")
        return 0

    files = len(seen)
    lines = sum(r["lines"] for r in seen.values())
    unread = sorted(p for p, r in seen.items() if r["edit"] and not r["read"])
    print(
        f"files={files} lines={lines} "
        f"edit_without_read={len(unread)} "
        f"unread={','.join(unread) if unread else '-'}"
    )
    return 0


def main() -> int:
    if len(sys.argv) >= 3 and sys.argv[1] == "summarize":
        return summarize(sys.argv[2])
    print("usage: telemetry-helper.py summarize <session.jsonl>", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
