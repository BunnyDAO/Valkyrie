---
id: 0027
title: Seed docs/adr/0002 — valk-land delegation & no-force
type: AFK
status: done
blocked_by: []
parent: docs/prd/valk-land.md
---

## What to build

Record the load-bearing, hard-to-reverse, surprising-without-context
decisions behind `valk-land` so a future reader does not "fix" them into
always-PR or force-push. Create `docs/adr/0002-valk-land-delegation-and-no-
force.md` in the established ADR format (status, context, decision,
considered options, consequences) capturing:

- **Why delegate-or-local, not always-PR:** an always-PR design breaks
  standalone/local-first (Valkyrie itself has no PR host); `valk-land`
  follows the repo's existing `pr_skill` opt-in instead of forcing a host.
- **Why never force-push / never rewrite pushed history:** safety over
  convenience; an aborted land that preserves state beats a "successful"
  land that rewrote history.
- **Why rebase-linear (not merge commits):** review-friendly linear history;
  conflicts surface explicitly, consistent with ADR-0001's "explicit merge
  work" framing.

Must reference and stay consistent with
`docs/adr/0001-isolation-not-locking.md` (the parent decision: `valk-land`
is the cure's ergonomic companion, not a second cure).

The decision is already PRD-approved, so this has no blockers — it can be
written at any time.

## Acceptance criteria

- [x] `docs/adr/0002-valk-land-delegation-and-no-force.md` exists in the
      house ADR format and is the second entry in the ADR log
- [x] It states the delegate-or-local rationale and why always-PR was
      rejected
- [x] It states the never-force-push and rebase-linear rationale
- [x] It references ADR-0001 and is consistent with it (companion, not a
      second cure)
- [x] No code/behavior change; existing tests stay green

> Done. ADR-0002 seeded in the house format (Status/Context/Decision/
> Considered options/Consequences), records delegate-or-local vs always-PR,
> never-force-push, rebase-linear, and links ADR-0001 as the parent. Docs
> only; suite 12/12.

## Blocked by

- None — the decision is already PRD-approved
