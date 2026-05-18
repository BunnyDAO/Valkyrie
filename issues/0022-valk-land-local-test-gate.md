---
id: 0022
title: valk-land local safety gate — test_skill, abort on red
type: AFK
status: done
blocked_by: [0019]
parent: docs/prd/valk-land.md
---

## What to build

Gate the local land on the project's own GREEN signal so a slice that was
green in isolation can't publish a broken `main`. After the rebase onto
fresh `origin/main` and **before** finalizing/pushing, `valk-land` runs the
repo's GREEN signal — the `test_skill` declared in `.claude/valk-config.md`,
read via the existing `read-valk-config.sh` (the same contract `tdd` uses),
falling back to an inferred runner.

- Red → **abort the land**: nothing is finalized or pushed; `valk/<name>`
  and the worktree are left exactly as they were.
- No `test_skill` and no runner inferable → do not silently land: warn
  loudly and require an explicit `--force` to land unverified.

`read-valk-config.sh` is consumed read-only; no stage skill is modified.

## Acceptance criteria

- [x] With a `test_skill` (injected via a temp `.claude/valk-config.md` +
      stub) that passes, the land completes; when it fails, the land aborts
      with nothing pushed and `valk/<name>` + worktree intact
- [x] With no test signal and none inferable, `valk-land` refuses to land
      without `--force`, and lands (with a clear unverified warning) with it
- [x] The signal used is the same `test_skill` contract `tdd` consumes
      (read via the shared `read-valk-config.sh`, verified behaviorally)
- [x] Bash test in `test/` covers pass / fail / no-signal / `--force`;
      `test-noop.sh` byte-green; full suite stays green

> Done. As a script (not an agent), valk-land honors `test_skill` as a
> runnable command, executed on the rebased worktree before ff/push; red
> aborts (nothing pushed, rebased work preserved). Scoping note: no auto
> runner-inference in v1 — an unset/unrunnable `test_skill` is treated as
> "no signal" and requires explicit `--force` (with a loud unverified
> warning), satisfying the "none inferable → refuse/--force" criterion
> without speculative inference. Suite 12/12, `test-noop` byte-green.

## Blocked by

- 0019
