---
id: 0020
title: valk-land push-phase safety — --no-push and origin-moved abort
type: AFK
status: done
blocked_by: [0019]
parent: docs/prd/valk-land.md
---

## What to build

Make the push phase safe and race-free. Two behaviors on the local path:

- `valk-land <name> --no-push` does the full rebase + fast-forward of local
  main but **does not touch `origin`** — the land stays purely local.
- If `origin/main` moved **again** between the fetch/rebase and the push
  (a concurrent flow landed in that window), `valk-land` does not force
  anything: it aborts the land, leaves `valk/<name>` and the worktree
  exactly as they were, and tells the user to re-run. It never force-pushes
  and never rewrites already-pushed history.

## Acceptance criteria

- [x] `--no-push` lands locally (local main advanced) with `origin/main`
      provably unchanged
- [x] When `origin/main` advances after the rebase but before the push, the
      push is refused: nothing is force-pushed, `origin/main` keeps the
      concurrent work, `valk/<name>` + worktree are intact, exit is non-zero
      with a clear "re-run" message
- [x] No code path can produce a force-push or a non-fast-forward push
- [x] Bash test in `test/` against a simulated origin covers both behaviors
      (including a concurrently-advanced origin); full suite stays green

> Done. `--no-push` skips origin entirely; a rejected push unwinds the
> unpublished local ff (`reset --hard` to pre-land main), keeps the rebased
> work on `valk/<name>`, and emits explicit re-run guidance. No `--force`
> anywhere. Suite 12/12, `test-noop` byte-green.

## Blocked by

- 0019
