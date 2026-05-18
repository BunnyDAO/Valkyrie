---
id: 0026
title: Docs — integrate-back is "manual or valk-land"
type: AFK
status: open
blocked_by: [0019, 0020, 0021, 0022, 0023, 0024]
parent: docs/prd/valk-land.md
---

## What to build

Make `valk-land` the documented, supported ergonomic integrate-back path.
Update `SOP.md` and `docs/workflow.md` so the parallel-flow lifecycle's
integrate-back step reads "**manual or `valk-land <name>`**": describe the
one-command land, the delegate-or-local behavior, the test gate, the
conflict/abort safety, and the opt-in `--clean`. The manual merge/PR path
stays documented and valid (not removed). State plainly the honest hard
limit (consistent with ADR-0001): `valk-land` makes the merge work
ergonomic and race-free; it does not eliminate conflicts.

Docs only — no behavior change. Blocked until the behavior slices are
complete so the docs describe shipped reality, not intent.

## Acceptance criteria

- [ ] SOP.md + docs/workflow.md present `valk-land` as the supported
      ergonomic integrate-back, with delegate-or-local, test gate,
      conflict-abort, and `--clean` summarized accurately
- [ ] The manual merge/PR path remains documented and explicitly still valid
- [ ] The honest hard limit (ergonomic, not conflict-eliminating) is stated,
      consistent with `docs/adr/0001-isolation-not-locking.md`
- [ ] No code/behavior change; existing tests stay green

## Blocked by

- 0019, 0020, 0021, 0022, 0023, 0024
