#!/usr/bin/env python3
"""
cost-helper.py — parse stream-json logs and compute per-iteration USD cost.

Invoked from afk. Two subcommands:

  parse-log <logfile>
      Print one whitespace-separated line:
        model=<name> input=<n> output=<n> cw5m=<n> cw1h=<n> cread=<n> exit=<code> cost_usd=<decimal>
      The exit code is always 0 on the printed line (the parser doesn't know
      the CLI's exit; afk passes that separately when needed).
      Exits 0 if the log was parseable AND the model is in the rate table.
      Exits non-zero with a clear stderr message on any failure
      (missing rates.json, malformed rates.json, unknown model).

  validate-rates [path]
      Sanity-check the rate table. Exits 0 on valid, non-zero otherwise.

Rate table is read from $HOME/.claude/valkyrie/rates.json by default.
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path


def rates_path() -> Path:
    return Path(os.environ.get("HOME", str(Path.home()))) / ".claude" / "valkyrie" / "rates.json"


def load_rates(path: Path | None = None) -> dict:
    p = path or rates_path()
    if not p.exists():
        sys.stderr.write(f"error: rates.json not found at {p}. Run install.sh.\n")
        sys.exit(2)
    try:
        data = json.loads(p.read_text())
    except json.JSONDecodeError as e:
        sys.stderr.write(f"error: rates.json at {p} is not valid JSON: {e}\n")
        sys.exit(2)
    # Schema: top-level must contain at least 'anthropic' or 'openai' provider.
    if not isinstance(data, dict) or not any(k in data for k in ("anthropic", "openai")):
        sys.stderr.write(f"error: rates.json at {p} missing required provider keys (anthropic/openai)\n")
        sys.exit(2)
    return data


# Strip a trailing -YYYYMMDD date suffix from a model name.
_DATE_SUFFIX_RE = re.compile(r"-\d{8}$")


def normalize_model(name: str) -> str:
    return _DATE_SUFFIX_RE.sub("", name or "")


def find_model_rates(rates: dict, model: str) -> dict:
    """Return the rate dict for `model` (after normalization), or exit 2."""
    norm = normalize_model(model)
    for provider in ("anthropic", "openai"):
        if provider in rates and norm in rates[provider]:
            return rates[provider][norm]
    sys.stderr.write(
        f"error: model '{model}' (normalized: '{norm}') not in rates.json. "
        f"Add it to scripts/rates.json and re-run install.sh.\n"
    )
    sys.exit(2)


def parse_usage_event(usage: dict) -> tuple[int, int, int, int, int]:
    """
    Return (input, output, cw5m, cw1h, cread).
    `cache_creation_input_tokens` may be a flat int OR a dict with 5m/1h sub-fields.
    Flat case is attributed entirely to cw5m (overestimates cost — safer for a cap).
    """
    input_tok = int(usage.get("input_tokens", 0) or 0)
    output_tok = int(usage.get("output_tokens", 0) or 0)
    cread = int(usage.get("cache_read_input_tokens", 0) or 0)

    cc = usage.get("cache_creation_input_tokens", 0)
    if isinstance(cc, dict):
        cw5m = int(cc.get("ephemeral_5m_input_tokens", 0) or 0)
        cw1h = int(cc.get("ephemeral_1h_input_tokens", 0) or 0)
    else:
        cw5m = int(cc or 0)
        cw1h = 0

    return input_tok, output_tok, cw5m, cw1h, cread


def parse_log(logfile: Path) -> dict:
    """
    Read a stream-json log file. Sum usage across all message events.
    Returns dict with model, input, output, cw5m, cw1h, cread.
    Raises if the log has no usage events at all.
    """
    model = ""
    totals = {"input": 0, "output": 0, "cw5m": 0, "cw1h": 0, "cread": 0}
    saw_usage = False

    with logfile.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                continue  # tolerate non-JSON noise
            # Pull model from anywhere it appears.
            if not model:
                m = ev.get("model")
                if m:
                    model = m
                msg = ev.get("message")
                if not model and isinstance(msg, dict):
                    m = msg.get("model")
                    if m:
                        model = m
            # Pull usage from message events.
            msg = ev.get("message")
            if isinstance(msg, dict) and isinstance(msg.get("usage"), dict):
                i, o, w5, w1, r = parse_usage_event(msg["usage"])
                totals["input"]  += i
                totals["output"] += o
                totals["cw5m"]   += w5
                totals["cw1h"]   += w1
                totals["cread"]  += r
                saw_usage = True

    if not model:
        sys.stderr.write(f"error: no model field found in {logfile}\n")
        sys.exit(3)

    return {
        "model": model,
        "saw_usage": saw_usage,
        **totals,
    }


def compute_cost(rate: dict, parsed: dict) -> float:
    return (
        parsed["input"]  / 1_000_000.0 * rate["input_per_mtok"]
      + parsed["output"] / 1_000_000.0 * rate["output_per_mtok"]
      + parsed["cw5m"]   / 1_000_000.0 * rate.get("cache_write_5m_per_mtok", 0.0)
      + parsed["cw1h"]   / 1_000_000.0 * rate.get("cache_write_1h_per_mtok", 0.0)
      + parsed["cread"]  / 1_000_000.0 * rate.get("cache_read_per_mtok", 0.0)
    )


def fmt_cost(c: float) -> str:
    """Round-trip-safe cost format. Trim trailing zeros; cap at 6 decimals."""
    s = f"{c:.6f}".rstrip("0").rstrip(".")
    return s if s else "0"


def cmd_parse_log(args: list[str]) -> int:
    if len(args) != 1:
        sys.stderr.write("usage: cost-helper.py parse-log <logfile>\n")
        return 2
    logfile = Path(args[0])
    if not logfile.exists():
        sys.stderr.write(f"error: log file not found: {logfile}\n")
        return 2

    rates = load_rates()
    parsed = parse_log(logfile)
    rate = find_model_rates(rates, parsed["model"])
    cost = compute_cost(rate, parsed)
    norm = normalize_model(parsed["model"])

    print(
        f"model={norm} input={parsed['input']} output={parsed['output']} "
        f"cw5m={parsed['cw5m']} cw1h={parsed['cw1h']} cread={parsed['cread']} "
        f"saw_usage={'1' if parsed['saw_usage'] else '0'} "
        f"cost_usd={fmt_cost(cost)}"
    )
    return 0


def cmd_validate_rates(args: list[str]) -> int:
    path = Path(args[0]) if args else rates_path()
    load_rates(path)  # exits on failure
    print(f"rates.json at {path}: ok")
    return 0


def main() -> int:
    if len(sys.argv) < 2:
        sys.stderr.write("usage: cost-helper.py {parse-log|validate-rates} [...]\n")
        return 2
    sub = sys.argv[1]
    rest = sys.argv[2:]
    if sub == "parse-log":
        return cmd_parse_log(rest)
    if sub == "validate-rates":
        return cmd_validate_rates(rest)
    sys.stderr.write(f"unknown subcommand: {sub}\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())
