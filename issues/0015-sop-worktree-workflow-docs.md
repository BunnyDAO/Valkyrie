---
id: 0015
title: Document worktree-per-flow as the supported parallel mode
type: AFK
status: done
blocked_by: [0013]
parent: docs/prd/concurrency-hardening.md
---

## What to build

Make the safe parallel workflow the documented, supported one — so the
multi-terminal user has a clear path, not folklore.

Update the SOP and workflow docs to state:

- Running multiple Valkyrie flows on one project is supported **via one
  worktree per flow** (`valk-worktree <name>`), not by sharing one checkout.
  Explain *why* (a shared tree cannot be made safe by code) without
  re-deriving it.
- The integrate-back story: each flow works on its own `valk/<name>`
  branch; land it via merge/PR to the main branch. This is the **manual**
  path for now (automating it — `valk-land` — is a separate deferred PRD,
  see #0018).
- Cleanup: `valk-worktree --remove <name>` when a flow is done.
- A short pointer that the prompt guard will nudge you if you're still in
  the shared checkout, and goes silent once isolated.

Docs only — no behavior change.

## Acceptance criteria

- [x] SOP + workflow docs describe worktree-per-flow as the supported
      parallel mode, with the create / integrate-back / remove lifecycle
- [x] The "why a shared tree can't be code-fixed" framing is stated plainly
- [x] Manual merge/PR integrate-back documented; `valk-land` referenced as a
      tracked future PRD (#0018), not implied to exist now
- [x] No code/behavior change; existing tests stay green

## Blocked by

- 0013 (docs reference the `valk-worktree` command + its lifecycle)
