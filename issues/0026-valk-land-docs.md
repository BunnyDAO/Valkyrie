---
id: 0026
title: Docs — integrate-back is "manual or valk-land"
type: AFK
status: done
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

- [x] SOP.md + docs/workflow.md present `valk-land` as the supported
      ergonomic integrate-back, with delegate-or-local, test gate,
      conflict-abort, and `--clean` summarized accurately
- [x] The manual merge/PR path remains documented and explicitly still valid
- [x] The honest hard limit (ergonomic, not conflict-eliminating) is stated,
      consistent with `docs/adr/0001-isolation-not-locking.md`
- [x] No code/behavior change; existing tests stay green

> Done. Both docs' parallel-flow sections now show `valk-land <name>` as the
> supported integrate-back (delegate-or-local, test-gate, conflict-abort,
> --clean), the manual merge/PR path explicitly still valid, and the
> ADR-0001 honest limit stated. The stale "#0018 deferred" wording is
> replaced. Docs only; suite 12/12.

## Blocked by

- 0019, 0020, 0021, 0022, 0023, 0024
