#!/usr/bin/env python3
"""
Stage state writer for Valkyrie skills.

Skills invoke this to record the workflow stage they just entered, so the
statusline (and the orchestrator) can see where the user is in the flow.

Usage:
    stage.py set tdd                       # write 'tdd' to per-project stage file
    stage.py set tdd --global              # write to ~/.claude/valk/stage
    stage.py get                           # print current stage to stdout
    stage.py clear                         # back to idle

State file: <cwd>/.claude/valk/stage  (one stage name per line, UTF-8).
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

VALID_STAGES = {
    "idle", "design", "grill-with-docs", "prd", "to-prd",
    "prd-review", "issues", "to-issues", "tdd", "zoom", "zoom-out",
    "refactor", "afk",
}


def state_path(use_global: bool) -> Path:
    base = Path.home() if use_global else Path(os.getcwd())
    p = base / ".claude" / "valk" / "stage"
    p.parent.mkdir(parents=True, exist_ok=True)
    return p


def cmd_set(args: argparse.Namespace) -> int:
    stage = args.stage.strip().lower()
    if stage not in VALID_STAGES:
        print(f"unknown stage: {stage}. valid: {sorted(VALID_STAGES)}", file=sys.stderr)
        return 2
    path = state_path(args.global_)
    path.write_text(stage + "\n", encoding="utf-8")
    print(f"stage -> {stage} ({path})")
    return 0


def cmd_get(args: argparse.Namespace) -> int:
    for path in (state_path(False), state_path(True)):
        try:
            print(path.read_text(encoding="utf-8").strip())
            return 0
        except OSError:
            continue
    print("idle")
    return 0


def cmd_clear(args: argparse.Namespace) -> int:
    for path in (state_path(False), state_path(True) if args.global_ else None):
        if path is None:
            continue
        try:
            path.unlink()
        except OSError:
            pass
    print("stage -> idle")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Valkyrie stage state.")
    sub = parser.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("set", help="set the current stage")
    s.add_argument("stage", help="stage name (e.g. grill-with-docs, to-prd, tdd)")
    s.add_argument("--global", dest="global_", action="store_true",
                   help="write to ~/.claude (not project-local)")
    s.set_defaults(func=cmd_set)

    g = sub.add_parser("get", help="print the current stage")
    g.set_defaults(func=cmd_get)

    c = sub.add_parser("clear", help="reset to idle")
    c.add_argument("--global", dest="global_", action="store_true")
    c.set_defaults(func=cmd_clear)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
