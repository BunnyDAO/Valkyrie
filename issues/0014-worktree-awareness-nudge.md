---
id: 0014
title: Self-silencing worktree-awareness nudge in the prompt guard
type: AFK
status: open
blocked_by: [0013]
parent: docs/prd/concurrency-hardening.md
---

## What to build

A backstop that points users at `valk-worktree` when they're in the unsafe
shared checkout, and gets out of the way the moment they isolate.

Extend the existing UserPromptSubmit guard with a cheap, stateless git check:
"am I running in the main checkout, or in a linked worktree?" If the flow is
in the **main checkout**, inject **one** gentle reminder pointing at
`valk-worktree`. Inside a linked worktree it is **silent** — the nudge is
self-extinguishing once each terminal is isolated, so it never nags the
intended (worktree) workflow.

Explicitly NOT built: any flow registry / pids / heartbeat / stale-pruning
(dropped as highest-risk-for-least-gain). The check is warn-only — it never
blocks, never changes exit behaviour, and cannot false-lock anyone out.

Takes effect after one installer run (the guard is copied into the hooks
dir, not symlinked).

## Acceptance criteria

- [ ] Invoked from the main checkout → output contains exactly one reminder
      that references `valk-worktree`
- [ ] Invoked inside a linked worktree → no reminder (silent)
- [ ] Never blocks and never changes the guard's exit behaviour (warn-only)
- [ ] No registry/pid/heartbeat/lockfile state introduced anywhere
- [ ] Bash test in `test/` (run-tests.sh) covers main-tree→nudge,
      worktree→silent, exit unchanged; `test-noop.sh` single-flow path stays
      byte-green

## Blocked by

- 0013 (the nudge must point at a `valk-worktree` command that exists)
