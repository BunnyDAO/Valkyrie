---
id: 0010
title: Confirmation prompt + queue summary
type: AFK
status: done
blocked_by: [0007]
parent: docs/prd/afk-enforcement-guardrails.md
---

## What to build

Add `gate_confirm` to the preflight orchestrator — the last gate to run, after all hard-block gates have passed. End-to-end:

- After all earlier gates pass, the gate prints to stdout:
  ```
  afk: caps active — <N> iterations | <H>h<MM>m | $<U>.<UU>

  Queue (<K> issues, in dependency order):
    <id1> — <title1>
    <id2> — <title2>
    ...

  Proceed? [y/N]: 
  ```
- Where `<K>` is the count of unblocked open issues, and the queue lists the same set in the same order `pick_next_issue` would pick them.
- Reads one line from stdin. Accepts `y`, `Y`, `yes`, `YES` (case sensitivity flexible: `Yes`, `YeS` all accepted). Anything else (including empty input) aborts with: `afk: aborted at confirmation prompt.` and exits non-zero.
- New flag: `--no-confirm`. When passed:
  - The active-caps line + queue summary STILL print to stdout (so CI logs capture the queue).
  - The `Proceed? [y/N]: ` prompt is skipped entirely.
  - No stdin read.
- The queue summary is also used by 0007's "Queue would have been: N issues." line — extract that count from the same logic so the two stay consistent.

## Acceptance criteria

- [x] With `--no-confirm`, the queue summary prints to stdout, no prompt appears, and the loop runs immediately.
- [x] Without `--no-confirm` and stdin closed, the loop aborts non-zero (no prompt to interact with).
- [x] Piping `y`, `Y`, `yes`, `YES` to stdin all proceed and the loop runs.
- [x] Piping `n`, `no`, `q`, empty line, garbage to stdin all abort with the documented message and non-zero exit.
- [x] Queue summary lists exactly the unblocked open issues that `pick_next_issue` would pick, in dependency order, formatted as `  <id> — <title>`.
- [x] When zero issues are queued (none open / all blocked), the queue summary says `Queue (0 issues): nothing to do.` and the loop exits cleanly with `reason: no more issues` (no prompt).
- [x] Queue summary goes to stdout; the prompt itself goes to stdout; abort message goes to stderr.
- [x] Multi-gate failure path: when an EARLIER gate failed, `gate_confirm` does NOT run (the loop already exited with the punch list).
- [x] New tests in `test/test-guardrails.sh` cover the above (using stdin redirection like `echo y | afk ...` and `</dev/null`).

## Blocked by

- 0007 (orchestrator + queue-counting helper)
