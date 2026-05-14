---
id: 0004
title: --max-cost-usd cap enforcement and per-iter cost line
type: AFK
status: done
blocked_by: [0002, 0003]
parent: docs/prd/afk-budget-caps.md
---

## What to build

Wire the cost-computing primitives from 0003 into the per-iteration loop and add the `--max-cost-usd` cap. End-to-end:

- New flag `--max-cost-usd <X>` accepts a positive number (decimals allowed). Default: `50`.
- Startup banner from 0002 is extended to include the cost cap on the same line:
  ```
  afk: caps active — 10 iterations | 4h00m | $50.00
  ```
- After each iteration, parse the per-iter log via `parse_iter_usage` (from 0003), compute the iter's cost via `compute_iter_cost`, and add to a running `cumulative_cost`.
- After each iteration, print one cumulative status line:
  ```
  iter 3/10 done | elapsed 1h12m / 4h00m | spend $4.50 / $50.00 (~9%)
  ```
- Cap check at iter boundary: if `cumulative_cost >= max_cost_usd`, exit with `reason: cost cap hit`. Time cap and iteration cap from 0002 still take precedence if they hit first; whichever crosses first wins.
- Final summary banner extends to include spend:
  ```
  afk: stopped — reason: cost cap hit
    iterations:    7 / 10
    elapsed:       2h41m / 4h00m
    spend:         $50.04 / $50.00 (overshoot: $0.04)
    issues done:   5
    issues stuck:  2
    logs:          .claude/valk/afk-logs/
  ```
- No-usage handling (PRD Q7):
  - If `parse_iter_usage` returns zero usage events AND the iteration's CLI exit code is `0` → treat the iter as `$0`, log a one-line note, continue.
  - If zero usage events AND non-zero exit → exit the loop with `reason: cost tracking failed`. Print the offending log file path so the user can debug.
- The unknown-model hard-refuse path from 0003 fires here at runtime if a real iter produces a model not in the rate table — same error, immediate exit.

## Acceptance criteria

- [x] `afk 5 --max-cost-usd 0.05` against a stubbed CLI emitting ~$0.02/iter exits with `reason: cost cap hit` after 3 iterations and `cumulative >= 0.05`.
- [x] `afk 5` (no flag) prints banner showing default `$50.00` and runs to completion (no cap hit) for cheap fixtures.
- [x] Per-iteration status line is printed after every iter, with cumulative time and spend formatted as documented.
- [x] When time cap, iter cap, and cost cap could all theoretically hit, whichever crosses first wins; the `reason:` field on the summary identifies which.
- [x] Stubbed CLI exits 0 with no `usage` events → iter treated as $0, loop continues, summary shows the iter as completed.
- [x] Stubbed CLI exits non-zero with no `usage` events → loop exits with `reason: cost tracking failed`, error message names the offending log file.
- [x] Stubbed CLI emits a model not in the rate table → loop exits with the unknown-model error from 0003.
- [x] `--max-cost-usd abc` exits 2 with a clear error.
- [x] `--max-cost-usd 0` or negative exits 2 with a clear error.
- [x] Tests in `test/` cover: cost cap hit; default behavior; per-iter line content; clean no-usage continues; dirty no-usage hard-fails; unknown model at runtime; cap precedence (time hits first, cost hits first).

## Blocked by

- 0002 (banner + summary framing — cost lines slot into existing format)
- 0003 (rates.json, parse, compute primitives)
