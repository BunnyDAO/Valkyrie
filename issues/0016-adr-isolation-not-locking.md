---
id: 0016
title: Seed docs/adr/0001 — isolation, not locking
type: AFK
status: open
blocked_by: []
parent: docs/prd/concurrency-hardening.md
---

## What to build

Start the Valkyrie ADR log and record the load-bearing decision behind this
whole effort, so a future reader understands *why* it was built this way.

Create `docs/adr/0001-isolation-not-locking.md` capturing: concurrency
safety for multiple flows on one project is achieved by making **isolation
(a frictionless worktree helper) the path of least resistance**, NOT by a
locking / flow-registry / pid / heartbeat guard. Record the real trade-off
(registry-guard vs worktree-helper), why the registry was rejected (highest
risk for least marginal gain; stale-state false-locks), the honest hard
limit (a shared tree cannot be made safe by code — same-file races and
shared red runs are irreducible), and that the atomic-commit recipe is
mitigation while isolation is the cure.

## Acceptance criteria

- [ ] `docs/adr/0001-isolation-not-locking.md` exists in the standard ADR
      format (status, context, decision, consequences)
- [ ] It states the registry-vs-helper trade-off and why locking/registry
      was explicitly rejected
- [ ] It states the honest hard limit (no code fixes a shared tree) and the
      mitigation-vs-cure framing
- [ ] It establishes the `docs/adr/` log for the repo (first entry)

## Blocked by

- None — can start immediately
