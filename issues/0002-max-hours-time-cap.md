---
id: 0002
title: --max-hours time cap with banner and final summary
type: AFK
status: done
blocked_by: [0001]
parent: docs/prd/afk-budget-caps.md
---

## What to build

Add a wall-clock time cap to `afk`. End-to-end behavior:

- New flag `--max-hours <N>` accepts a positive number (decimals allowed, e.g. `--max-hours 0.5`).
- Default value: `4`. Applies if the flag isn't passed.
- At startup, after argv parsing, the loop computes `DEADLINE_TS = start + max_hours * 3600` and prints an active-caps banner:
  ```
  afk: caps active — 10 iterations | 4h00m
  ```
- Between iterations, before picking the next issue, the loop checks `now >= DEADLINE_TS`. If so, it exits with `reason: time cap hit` (does not start another iteration).
- A final summary banner is printed on every exit path — clean exit (no more issues / max iters / cap hit) AND Ctrl-C. Format:
  ```
  afk: stopped — reason: <reason>
    iterations:    <done> / <max>
    elapsed:       <Hh MMm> / <max>h00m
    issues done:   <n>
    issues stuck:  <n>
    logs:          .claude/valk/afk-logs/
  ```
- The `reason:` field takes one of: `no more issues`, `iteration cap hit`, `time cap hit`, `interrupted`.
- The Ctrl-C trap continues to clear the stage marker (existing behavior); after clearing, it prints the summary banner.

This slice does NOT touch cost tracking — that arrives in 0004. The banner and summary should be designed so cost lines slot in cleanly later (leave room or a comment in the format).

## Acceptance criteria

- [x] `afk 2 --max-hours 0.001` (3.6 seconds) against a stubbed CLI that sleeps ~2s/iter exits with `reason: time cap hit` after exactly 1 completed iteration. (One iter completes; cap is checked at the boundary, not mid-iter.)
- [x] `afk 5` (no flag) behaves identically to today plus prints the banner showing default `4h00m`.
- [x] Startup banner prints active iteration cap and active hours cap on a single line.
- [x] Final summary banner prints on clean exit, includes `reason:` field, iterations done/max, elapsed time formatted as `XhYYm`, issues done count, issues stuck count.
- [x] Final summary banner prints on Ctrl-C (SIGINT), with `reason: interrupted`, before the process exits 130.
- [x] `--max-hours abc` (non-numeric) exits 2 with a clear error.
- [x] `--max-hours -1` (non-positive) exits 2 with a clear error.
- [x] Existing iteration cap behavior is unchanged when only the positional argument is passed.
- [x] At least one test in `test/` covers each of: time cap hit, iteration cap hit, no-more-issues exit, SIGINT summary.

## Blocked by

- 0001 (test harness)
