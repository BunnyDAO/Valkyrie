---
id: 0018
title: "FOLLOW-UP (deferred): design valk-land (branch→master integration)"
type: HITL
status: open
blocked_by: []
parent: docs/prd/concurrency-hardening.md
---

## What to build

> **Tracking placeholder — not implemented by this effort.** Filed so the
> deferred piece is not lost. It needs its own grill/PRD before any code.

Worktree-per-flow moves collisions from silent commit-sweeps to explicit
merge work: N flows on N `valk/<name>` branches must land on the main
branch. This issue tracks designing a `valk-land` companion to make that
integrate-back ergonomic. It has real, unresolved design forks that deserve
their own DESIGN session:

- auto-rebase-onto-main vs open-a-PR
- whether/how it gates on tests/CI before landing
- conflict policy when parallel branches touched overlapping files
- cleanup coupling with `valk-worktree --remove`

Folding this into the concurrency-hardening PRD was deliberately rejected as
scope-creep. Until this is designed, the manual merge/PR path documented in
the SOP (#0015) is the supported integrate-back.

## Acceptance criteria

- [ ] Remains `open` as a tracked placeholder until consciously picked up
- [ ] When picked up: runs its own grill → PRD → issues → tdd (not
      implemented directly from this issue)
- [ ] The SOP's manual integrate-back stays the documented path until then

## Blocked by

- None — but intentionally deferred (do not implement without its own PRD)
