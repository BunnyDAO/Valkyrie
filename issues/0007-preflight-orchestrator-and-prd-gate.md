---
id: 0007
title: Preflight orchestrator + PRD existence gate
type: AFK
status: done
blocked_by: []
parent: docs/prd/afk-enforcement-guardrails.md
---

## What to build

The shared infrastructure for all guardrails, plus the first gate wired into it. End-to-end:

- A `preflight()` function in `afk` that runs after env setup but before the startup banner. It calls each registered gate function in turn, collects failure messages into a `GATE_FAILURES` accumulator, and if any failed prints the punch list to stderr and exits non-zero.
- The punch-list format:
  ```
  afk: cannot start — fix the following:
    ✗ <gate failure message 1>
    ✗ <gate failure message 2>
  Queue would have been: <N> issues. Re-run after fixing.
  ```
- The "queue would have been" line uses the same queue-counting logic the loop uses (count of unblocked open issues).
- The first gate: `gate_prd_exists`. Returns 0 if `docs/prd/` exists AND contains at least one non-empty `.md` file. Otherwise returns 1 and appends to `GATE_FAILURES`:
  ```
  no PRD found in docs/prd/ (run /to-prd, or pass --allow-no-prd to override)
  ```
- New flag: `--allow-no-prd` (no value). When passed, `gate_prd_exists` skips the check and prints a one-line warning before the startup banner: `afk: warning — PRD check skipped (--allow-no-prd)`.
- Pre-flight runs to stderr; the existing startup banner (when pre-flight passes) continues to print to stdout.

This slice does NOT add the dirty-tree, dangerous-path, or confirmation gates — those land in 0008, 0009, 0010. The orchestrator is built so each follow-up gate plugs in by appending one function call.

## Acceptance criteria

- [x] `afk 2` in a workdir with no `docs/prd/` directory exits non-zero with the punch-list error and "no PRD found in docs/prd/" message.
- [x] `afk 2` in a workdir with `docs/prd/` but no files exits non-zero with the same message.
- [x] `afk 2` in a workdir with `docs/prd/x.md` (zero bytes) exits non-zero with the same message.
- [x] `afk 2` in a workdir with `docs/prd/x.md` containing text passes the gate and the loop runs.
- [x] `afk 2 --allow-no-prd` in a workdir with no PRD prints the override warning, passes the gate, and the loop runs.
- [x] The punch-list message ends with `Queue would have been: <N> issues.` where N is the unblocked open issue count.
- [x] Punch-list output goes to stderr; startup banner (when preflight passes) goes to stdout.
- [x] Existing tests (smoke, max-hours, cost, max-cost-usd, csv-history) still pass — adding `docs/prd/` to fixture workdirs as needed so the new gate doesn't break them.
- [x] New test file `test/test-guardrails.sh` covers the cases above.

## Blocked by

None — can start immediately.
