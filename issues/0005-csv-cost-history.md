---
id: 0005
title: CSV cost history file
type: AFK
status: done
blocked_by: [0004]
parent: docs/prd/afk-budget-caps.md
---

## What to build

Persist per-iteration cost data across runs to a CSV file. This gives the team real data for tuning the hardcoded defaults later.

- After each iteration completes (regardless of how the run later ends), append one row to `<repo>/.claude/valk/afk-cost-history.csv`.
- Columns (in this exact order):
  ```
  timestamp, iter, model, input_tokens, output_tokens, cache_write_5m, cache_write_1h, cache_read, cost_usd, cumulative_usd, exit_reason_for_run
  ```
- `timestamp` is ISO-8601 in UTC.
- `cost_usd` is per-iteration (not cumulative).
- `cumulative_usd` is the running total at end of this iter.
- `exit_reason_for_run` is left as the empty string until the run ends; the loop does NOT retroactively rewrite earlier rows when the run terminates. (Keeps appends atomic and crash-safe.) Instead, the very last row of any run gets the actual reason filled in. Tests verify only the last row carries a reason.
- If the file does not exist when about to append, write the header line first (matching the column list above), then the row.
- Appends are line-by-line and flushed each iter — the file is durable across Ctrl-C and crashes mid-loop.
- Rows from prior runs are never modified or deleted.

## Acceptance criteria

- [x] First-time `afk` run creates `<repo>/.claude/valk/afk-cost-history.csv` with the header line followed by one row per iteration.
- [x] Subsequent runs append rows; header is not duplicated.
- [x] Each row has exactly 11 fields, comma-separated, no trailing comma. Fields containing commas (none expected, but defensively) are quoted.
- [x] `cumulative_usd` of row N equals `cumulative_usd` of row N-1 + `cost_usd` of row N (within rounding).
- [x] After a Ctrl-C mid-iter, the CSV contains rows for all iterations that completed before the interrupt; the in-flight iter has no row.
- [x] The last row of a finished run has `exit_reason_for_run` set to one of the documented reasons.
- [x] Earlier rows from the same run have `exit_reason_for_run` empty.
- [x] A row is durable: killing `afk` with SIGKILL between iterations does not corrupt prior rows.
- [x] Tests in `test/` cover: header on first creation; append on second run; column count and order; cumulative arithmetic; SIGINT preserves prior rows; reason populated on last row only.

## Blocked by

- 0004 (cumulative cost, parsed token counts, exit reason — all upstream)
