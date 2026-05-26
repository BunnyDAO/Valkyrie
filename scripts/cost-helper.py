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

# Strip a trailing context-window suffix like "[1m]" or "[200k]". The
# extended-context variants don't have their own published rates in rates.json;
# fall back to the base model's pricing (slight underestimate for 1M Opus, but
# better than failing the run).
_CONTEXT_SUFFIX_RE = re.compile(r"\[[^\]]+\]$")


def normalize_model(name: str) -> str:
    n = name or ""
    n = _CONTEXT_SUFFIX_RE.sub("", n)
    n = _DATE_SUFFIX_RE.sub("", n)
    return n


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


def extract_codex_usage(ev: dict) -> dict | None:
    """
    Best-effort token usage from a codex `exec --json` JSONL event.

    codex emits *cumulative* token-count events (unlike claude's per-message
    deltas), so the caller keeps the LAST one rather than summing. Returns
    {input, output, cread} or None if this event carries no usage.

    Tolerant of schema drift: looks for a usage dict under several known keys
    and accepts both codex names (input_tokens / output_tokens /
    cached_input_tokens) and OpenAI chat names (prompt_tokens /
    completion_tokens). If codex changes shape, this returns None and the run
    falls back to the rates.json estimate — it never raises.
    VERIFY field names against your codex version with: codex exec --json ... | tail.
    """
    if not isinstance(ev, dict):
        return None
    cand = None
    info = ev.get("info")
    if isinstance(info, dict):
        cand = info.get("total_token_usage") or info.get("token_usage") or info.get("last_token_usage")
    if not isinstance(cand, dict):
        cand = ev.get("total_token_usage") or ev.get("token_usage")
    if not isinstance(cand, dict):
        return None
    inp = cand.get("input_tokens", cand.get("prompt_tokens"))
    out = cand.get("output_tokens", cand.get("completion_tokens"))
    if inp is None and out is None:
        return None
    cread = cand.get("cached_input_tokens", cand.get("cache_read_input_tokens", 0)) or 0
    return {"input": int(inp or 0), "output": int(out or 0), "cread": int(cread or 0)}


def parse_log(logfile: Path) -> dict:
    """
    Read a stream-json log file. Sum usage across all message events AND
    capture the CLI's self-reported `total_cost_usd` from the terminal
    `result` event (Anthropic's own client-side estimate).

    For non-claude CLIs (codex --json) that emit cumulative token-count events
    instead of claude's per-message usage, the latest codex usage is used as the
    totals and the model defaults to gpt-5-codex.

    Returns dict with model, input, output, cw5m, cw1h, cread, saw_usage,
    and reported_cost (float, or None if no result event carried one).
    Raises if the log has no model field at all.
    """
    model = ""
    totals = {"input": 0, "output": 0, "cw5m": 0, "cw1h": 0, "cread": 0}
    saw_usage = False
    codex_usage = None  # latest cumulative codex token-count event, if any
    reported_cost = None  # last non-null total_cost_usd from a result event
    api_key_source = None  # from the init event; "none" == subscription/OAuth

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
            # Capture the CLI's own cost estimate from the result event.
            # (Anthropic CLI only; codex won't emit this — that's fine,
            #  reported_cost stays None and we fall back to recompute.)
            if ev.get("type") == "result" and "total_cost_usd" in ev:
                try:
                    reported_cost = float(ev["total_cost_usd"])
                except (TypeError, ValueError):
                    pass
            # Capture apiKeySource from the init event. "none" means the
            # session ran on a Claude subscription / OAuth login (NOT billed
            # per token), so total_cost_usd is notional. Real claude always
            # emits this field; absence only happens in synthetic fixtures.
            if api_key_source is None and ev.get("apiKeySource") is not None:
                api_key_source = ev.get("apiKeySource")
            # Pull usage from message events (claude: per-message deltas).
            msg = ev.get("message")
            if isinstance(msg, dict) and isinstance(msg.get("usage"), dict):
                i, o, w5, w1, r = parse_usage_event(msg["usage"])
                totals["input"]  += i
                totals["output"] += o
                totals["cw5m"]   += w5
                totals["cw1h"]   += w1
                totals["cread"]  += r
                saw_usage = True
            # codex --json: cumulative token-count event (keep latest, don't sum).
            cu = extract_codex_usage(ev)
            if cu is not None:
                codex_usage = cu

    # Non-claude CLIs (codex) report cumulative usage, not per-message deltas —
    # apply the latest snapshot only when no claude-style usage was seen.
    if not saw_usage and codex_usage is not None:
        totals["input"] = codex_usage["input"]
        totals["output"] = codex_usage["output"]
        totals["cread"] = codex_usage["cread"]
        saw_usage = True
        if not model:
            model = "gpt-5-codex"

    if not model:
        sys.stderr.write(f"error: no model field found in {logfile}\n")
        sys.exit(3)

    return {
        "model": model,
        "saw_usage": saw_usage,
        "reported_cost": reported_cost,
        "api_key_source": api_key_source,
        **totals,
    }


def resolve_cost_mode(env_mode: str | None, api_key_source: str | None) -> str:
    """Decide whether to present cost as dollars or token counts.

    - Explicit override via $VALK_COST_MODE = "dollars" | "tokens" wins.
    - Otherwise "auto": apiKeySource == "none" (subscription / OAuth — not
      billed per token) => "tokens". Any other value, OR a missing field
      (synthetic fixtures only; real claude always emits it), => "dollars".
      Failing toward dollars is the safe default: an API-billed user losing
      spend visibility is worse than a subscription user seeing a notional
      figure they can discount.
    """
    m = (env_mode or "").strip().lower()
    if m in ("dollars", "tokens"):
        return m
    if (api_key_source or "").strip().lower() == "none":
        return "tokens"
    return "dollars"


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

    parsed = parse_log(logfile)
    norm = normalize_model(parsed["model"])

    # Layered cost model:
    #  - PRIMARY: the CLI's own total_cost_usd, when present AND > 0.
    #    A 0.0 is treated as "not reported" (placeholder / no-op iteration);
    #    a real working iteration always reports > 0. On this path we do NOT
    #    consult rates.json at all — Anthropic already priced it.
    #  - FALLBACK: recompute from token usage x rates.json. Triggered when
    #    the result event is absent (crash/kill/timeout) or carried 0.0,
    #    or for non-Anthropic CLIs (codex) that don't emit total_cost_usd.
    reported = parsed.get("reported_cost")
    if reported is not None and reported > 0:
        cost = reported
        source = "reported"
    else:
        rates = load_rates()
        rate = find_model_rates(rates, parsed["model"])
        cost = compute_cost(rate, parsed)
        source = "computed"

    cost_mode = resolve_cost_mode(
        os.environ.get("VALK_COST_MODE"), parsed.get("api_key_source")
    )
    total_tokens = (
        parsed["input"] + parsed["output"]
        + parsed["cw5m"] + parsed["cw1h"] + parsed["cread"]
    )

    print(
        f"model={norm} input={parsed['input']} output={parsed['output']} "
        f"cw5m={parsed['cw5m']} cw1h={parsed['cw1h']} cread={parsed['cread']} "
        f"saw_usage={'1' if parsed['saw_usage'] else '0'} "
        f"cost_usd={fmt_cost(cost)} cost_source={source} "
        f"cost_mode={cost_mode} total_tokens={total_tokens}"
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
