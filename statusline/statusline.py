#!/usr/bin/env python3
"""
Valkyrie statusline.

Inspired by moonbox3/ccstatusbar. If `~/.claude/ccstatusbar.py` is installed,
this delegates the heavy lifting (ctx %, 5h, wk, model, git) to ccstatusbar
and *appends* a STAGE segment that reflects the current Valkyrie stage.

If ccstatusbar is not installed, this produces a self-contained statusline
with: cwd, git branch, ctx %, STAGE, model.

Stage state is read from:
  1. <cwd>/.claude/valk/stage   (per-project; preferred)
  2. ~/.claude/valk/stage       (global fallback)

Claude Code invokes this command and pipes session JSON on stdin. We output
ONE line to stdout. See: https://docs.claude.com/claude-code/statusline
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

# --- ANSI color helpers -----------------------------------------------------

NO_COLOR = bool(os.environ.get("NO_COLOR"))


def c(code: str, text: str) -> str:
    if NO_COLOR or not sys.stdout.isatty() and not os.environ.get("FORCE_COLOR"):
        # Statusline output is rendered by Claude Code, which interprets ANSI
        # even when not a TTY. Always emit unless NO_COLOR is set.
        if NO_COLOR:
            return text
    return f"\x1b[{code}m{text}\x1b[0m"


def dim(t: str) -> str:
    return c("2", t)


def bold(t: str) -> str:
    return c("1", t)


def blue(t: str) -> str:
    return c("34", t)


def cyan(t: str) -> str:
    return c("36", t)


def green(t: str) -> str:
    return c("32", t)


def yellow(t: str) -> str:
    return c("33", t)


def magenta(t: str) -> str:
    return c("35", t)


def red(t: str) -> str:
    return c("31", t)


# --- Stage segment ----------------------------------------------------------

# Each stage maps to (display label, color function). Order roughly matches the
# enforced workflow in /valk.
STAGE_DISPLAY = {
    "idle":     ("IDLE",     dim),
    "design":          ("DESIGN", blue),  # grill-with-docs
    "grill-with-docs": ("DESIGN", blue),  # alias
    "prd":      ("PRD",      cyan),    # to-prd
    "to-prd":   ("PRD",      cyan),
    "issues":   ("ISSUES",   cyan),    # to-issues
    "to-issues": ("ISSUES",  cyan),
    "tdd":      ("TDD",      green),
    "zoom":     ("ZOOM",     yellow),  # zoom-out
    "zoom-out": ("ZOOM",     yellow),
    "refactor": ("REFACTOR", magenta),
    "afk":      ("AFK",      magenta),
}


def read_stage(cwd: Path) -> str | None:
    candidates = [
        cwd / ".claude" / "valk" / "stage",
        Path.home() / ".claude" / "valk" / "stage",
    ]
    for p in candidates:
        try:
            line = p.read_text(encoding="utf-8").strip().splitlines()[0].strip().lower()
            if line:
                return line
        except (OSError, IndexError):
            continue
    return None


def stage_segment(cwd: Path) -> str | None:
    stage = read_stage(cwd)
    if not stage:
        return None
    label, color = STAGE_DISPLAY.get(stage, (stage.upper(), bold))
    return color(f"▶ {label}")


# --- ccstatusbar delegation -------------------------------------------------

CCSTATUSBAR = Path.home() / ".claude" / "ccstatusbar.py"


def call_ccstatusbar(stdin_payload: str) -> str | None:
    if not CCSTATUSBAR.exists():
        return None
    try:
        result = subprocess.run(
            [sys.executable, str(CCSTATUSBAR)],
            input=stdin_payload,
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.rstrip("\n")
    except (subprocess.SubprocessError, OSError):
        pass
    return None


# --- Self-contained fallback segments --------------------------------------


def cwd_segment(cwd: Path) -> str:
    home = Path.home()
    try:
        rel = cwd.relative_to(home)
        display = "~/" + str(rel) if str(rel) != "." else "~"
    except ValueError:
        display = str(cwd)
    return blue(display)


def git_segment(cwd: Path) -> str | None:
    git_dir = cwd / ".git"
    if not git_dir.exists():
        # Walk up to find a repo root
        for parent in cwd.parents:
            if (parent / ".git").exists():
                break
        else:
            return None
    try:
        branch = subprocess.run(
            ["git", "-C", str(cwd), "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True, text=True, timeout=2,
        ).stdout.strip()
        if not branch:
            return None
        status = subprocess.run(
            ["git", "-C", str(cwd), "status", "--porcelain"],
            capture_output=True, text=True, timeout=2,
        ).stdout.splitlines()
        staged = sum(1 for l in status if l[:1] not in (" ", "?", ""))
        unstaged = sum(1 for l in status if l[1:2] not in (" ", ""))
        untracked = sum(1 for l in status if l.startswith("??"))
        bits = [cyan(branch)]
        counters = []
        if staged:
            counters.append(yellow(f"S:{staged}"))
        if unstaged:
            counters.append(yellow(f"U:{unstaged}"))
        if untracked:
            counters.append(yellow(f"A:{untracked}"))
        if counters:
            bits.append("| " + " ".join(counters))
        return " ".join(bits)
    except (subprocess.SubprocessError, OSError):
        return None


def ctx_segment(payload: dict) -> str | None:
    """Real context-window usage from Claude Code's `context_window` object.

    Schema (verified against code.claude.com/docs/en/statusline):
      context_window.used_percentage        pre-calculated % used
      context_window.total_input_tokens     tokens in context (incl. cache)
      context_window.total_output_tokens
      context_window.context_window_size    200000, or 1000000 extended
      exceeds_200k_tokens                   bool

    Renders e.g.  ctx:42% (84k/200k)  — colored green/yellow/red by how
    much is USED UP, with a ⚠ marker once past the 200k threshold.
    """
    cw = payload.get("context_window") or {}
    if not cw:
        return None

    size = cw.get("context_window_size") or 0
    used_tok = (cw.get("total_input_tokens") or 0) + (cw.get("total_output_tokens") or 0)

    # Prefer Claude's pre-calculated percentage; fall back to computing it.
    pct = cw.get("used_percentage")
    if pct is None:
        if not size:
            return None
        pct = 100.0 * used_tok / size
    pct = float(pct)

    pct_i = int(round(pct))
    # Color reflects how much is GONE: green plenty left, red almost full.
    color = green if pct_i < 70 else (yellow if pct_i < 90 else red)

    if size:
        body = f"ctx:{pct_i}% " + dim(f"({used_tok // 1000}k/{size // 1000}k used)")
    else:
        body = f"ctx:{pct_i}% used"

    seg = color(body)
    if payload.get("exceeds_200k_tokens"):
        seg += " " + red("⚠200k+")
    return seg


def model_segment(payload: dict) -> str:
    model = (payload.get("model") or {}).get("display_name")
    if not model:
        model = os.environ.get("CLAUDE_MODEL") or "Claude"
    return dim(model)


# --- Main -------------------------------------------------------------------

def main() -> int:
    raw = sys.stdin.read() if not sys.stdin.isatty() else "{}"
    try:
        payload = json.loads(raw or "{}")
    except json.JSONDecodeError:
        payload = {}

    cwd_str = (payload.get("workspace") or {}).get("current_dir") or os.getcwd()
    cwd = Path(cwd_str)

    base = call_ccstatusbar(raw)
    stage = stage_segment(cwd)

    if base:
        # Append our stage segment before the trailing model name. Heuristic:
        # ccstatusbar puts the model last, so we insert just before it.
        if stage:
            parts = base.rsplit("  ", 1)
            if len(parts) == 2:
                output = f"{parts[0]}  {stage}  {parts[1]}"
            else:
                output = f"{base}  {stage}"
        else:
            output = base
    else:
        segments = [cwd_segment(cwd)]
        for seg in (git_segment(cwd), ctx_segment(payload), stage, model_segment(payload)):
            if seg:
                segments.append(seg)
        output = "  ".join(segments)

    print(output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
