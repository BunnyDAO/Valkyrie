---
id: 0019
title: valk-land tracer — local clean land (rebase → ff → push)
type: AFK
status: done
blocked_by: []
parent: docs/prd/valk-land.md
---

## What to build

The thin end-to-end spine of `valk-land`. `valk-land <name>` takes a
finished `valk/<name>` branch and lands it on the main branch via the
**local path** (no PR host configured — the default, including Valkyrie
itself): fetch the remote, rebase `valk/<name>` onto fresh `origin/main`,
fast-forward the local main branch, then sync-safe push so `origin/main`
advances. One command; afterwards the work is on `origin/main` with linear
history. Establishes the `valk-land <name>` ↔ branch `valk/<name>` naming
that mirrors `valk-worktree`, and the new standalone `scripts/valk-land`
script.

This slice also pins the **compatibility invariant** for the whole feature
(PRD US13): `valk-land` is a new standalone script that reuses
`read-valk-config.sh` read-only and touches no stage sub-skill, the `valk`
orchestrator, or the crew-shim — so `test-noop.sh` stays byte-green and the
full suite stays green.

## Acceptance criteria

- [x] `valk-land <name>` on a clean (no-conflict) `valk/<name>` lands it: it
      is rebased onto current `origin/main`, local main fast-forwards, and
      `origin/main` is advanced to include the work
- [x] History is linear (no merge commit); no force-push, no rewrite of
      already-pushed history
- [x] A bash test in `test/` (auto-discovered by `run-tests.sh`) proves it
      against a **simulated origin** (a bare clone), observing only git
      state / filesystem / exit code
- [x] `test-noop.sh` stays byte-green and the full suite stays green
      (regression guard for the untouched single-flow / crew-shim path)

> Done. Realistic topology folded in per user direction: `valk/<name>`
> checked out in a linked worktree, rebased in place there; run from the
> main checkout (refuses from inside the worktree); no-worktree topology is
> an explicit unsupported error (a later slice can drive it). Suite 12/12,
> `test-noop` byte-green.

## Blocked by

- None — can start immediately
