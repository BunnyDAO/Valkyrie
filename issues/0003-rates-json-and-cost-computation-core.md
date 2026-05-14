---
id: 0003
title: rates.json + cost computation core + install.sh wiring
type: AFK
status: done
blocked_by: [0001]
parent: docs/prd/afk-budget-caps.md
---

## What to build

Foundational cost-computing primitives, with no cap enforcement yet. Adds:

- A new file `scripts/rates.json` matching the schema in the PRD (provider-grouped: `anthropic`, `openai`; per-model breakdown with `input_per_mtok`, `output_per_mtok`, `cache_write_5m_per_mtok`, `cache_write_1h_per_mtok`, `cache_read_per_mtok`). Ship with **placeholder values** for known model IDs (claude-opus-4-7, claude-sonnet-4-6, claude-haiku-4-5, gpt-5-codex). Real published prices are filled in by 0006.
- `install.sh` copies `scripts/rates.json` to `~/.claude/valkyrie/rates.json` (idempotent — overwrites on each run, like the statusline file).
- A `load_rates` function in `afk` that reads `~/.claude/valkyrie/rates.json` once at startup, validates the shape (provider keys present, each model has the five required fields), and stores the parsed data in memory.
- A `parse_iter_usage` function that takes a per-iteration log file path and emits a record of `(model, input, output, cache_write_5m, cache_write_1h, cache_read, exit_code)` extracted from the claude `stream-json` events. Handles two edge cases:
  - `cache_creation_input_tokens` may be a flat number (older API shape) or split into `ephemeral_5m_input_tokens`/`ephemeral_1h_input_tokens`. If flat, attribute all of it to `cache_write_5m` (the cheaper tier — overestimates cost, which is the safer direction for a cap).
  - The `model` field may include a date suffix (e.g. `claude-opus-4-7-20251115`). Strip a trailing `-\d{8}` before lookup.
- A `compute_iter_cost` function that takes the parsed record + the loaded rate table and returns a USD decimal.
- Hard-refuse paths (each exits with a clear error message and exit code ≥1):
  - `rates.json` does not exist.
  - `rates.json` is not valid JSON.
  - `rates.json` is missing a required provider key.
  - At runtime, parsed model name (post-normalization) is not in the rate table.

This slice does NOT add a `--max-cost-usd` flag, does NOT print costs in the banner or summary, and does NOT change the per-iteration loop behavior. It only adds the building blocks. End-to-end testability is via direct invocation of the new functions through a small `--debug-cost <logfile>` mode that prints `parse + compute` output for a given log file (used by the tests).

## Acceptance criteria

- [x] `scripts/rates.json` exists with the documented schema and placeholder values for at least: claude-opus-4-7, claude-sonnet-4-6, claude-haiku-4-5, gpt-5-codex.
- [x] `install.sh` copies `scripts/rates.json` to `~/.claude/valkyrie/rates.json` and prints a confirmation line.
- [x] Running `install.sh` twice in a row produces identical state (idempotent).
- [x] `afk` exits with a clear error if `~/.claude/valkyrie/rates.json` does not exist.
- [x] `afk` exits with a clear error if the file is malformed JSON.
- [x] `afk --debug-cost <fixture-log>` prints the parsed `(model, input, output, cw5m, cw1h, cread)` values and the computed USD cost for the given log file.
- [x] Date-suffixed model names like `claude-opus-4-7-20251115` are normalized to `claude-opus-4-7` for lookup.
- [x] Flat `cache_creation_input_tokens` is attributed entirely to `cache_write_5m`.
- [x] A model not in the rate table (post-normalization) causes `--debug-cost` to exit non-zero with a clear error naming the offending model.
- [x] Tests in `test/` cover: known fixture → known cost; missing rates.json; malformed rates.json; unknown model; date-suffixed model name normalization; flat cache field handling.

## Blocked by

- 0001 (test harness)
