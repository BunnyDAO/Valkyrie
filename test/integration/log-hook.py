#!/usr/bin/env python3
"""
log-hook.py — passive JSONL trace logger for Claude Code hooks.

Adapted from the pattern in randlee/sc-test-harness. Always exits 0; never
gates a tool call. Used by Valkyrie's integration test fixtures to capture
every Claude Code event during an `afk` run so behavior is auditable offline.

Usage (called from .claude/settings.json hook config):
    python3 /path/to/log-hook.py --event <EventName>

Input:
    stdin = the hook payload (JSON or raw text — both tolerated)

Output side-effect:
    appends ONE JSON line to $VALK_TRACE_FILE (or ./reports/trace.jsonl
    if the env var isn't set). Each line shape:
    {
      "ts": "<ISO 8601 UTC>",
      "event": "<EventName>",
      "cwd": "<process cwd>",
      "stdin": <parsed JSON, or raw string, or null>,
      "env": { ...subset of CLAUDE_* env... },
      "pid": <int>,
      "ppid": <int>
    }

Stdout: nothing on success. Exit code: always 0.

Errors (missing dir, unwritable file) are surfaced to stderr but never block
the hook — losing a trace line is preferable to breaking the agent.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import sys
from pathlib import Path


def parse_stdin() -> object:
    """Read stdin once. Return parsed JSON if possible; raw string if not;
    None if empty."""
    raw = sys.stdin.read()
    if not raw.strip():
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return raw


def capture_env() -> dict[str, str]:
    """Return only the env vars that matter for trace audit. Filtering
    keeps trace files small and avoids leaking secrets (PATH, HOME, etc.)."""
    keep_prefixes = ("CLAUDE_", "VALK_", "ANTHROPIC_LOG", "AFK_")
    keep_exact = {"PWD", "USER"}
    out = {}
    for k, v in os.environ.items():
        if k in keep_exact or any(k.startswith(p) for p in keep_prefixes):
            # Don't include API keys even when prefix matches.
            if "API_KEY" in k or "TOKEN" in k or "SECRET" in k:
                out[k] = "<redacted>"
            else:
                out[k] = v
    return out


def trace_path() -> Path:
    env_path = os.environ.get("VALK_TRACE_FILE")
    if env_path:
        return Path(env_path)
    return Path(os.getcwd()) / "reports" / "trace.jsonl"


def main() -> int:
    parser = argparse.ArgumentParser(description="Passive Claude Code hook logger.")
    parser.add_argument("--event", required=True, help="Hook event name (e.g. PreToolUse)")
    args = parser.parse_args()

    record = {
        "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "event": args.event,
        "cwd": os.getcwd(),
        "stdin": parse_stdin(),
        "env": capture_env(),
        "pid": os.getpid(),
        "ppid": os.getppid(),
    }

    path = trace_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(record, default=str) + "\n")
    except OSError as e:
        # Never break the hook chain; just complain to stderr.
        print(f"log-hook.py: warning — could not write trace: {e}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
