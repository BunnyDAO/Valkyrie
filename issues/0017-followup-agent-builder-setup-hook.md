---
id: 0017
title: "FOLLOW-UP (cross-repo → Agent-Builder): ship a .valk-worktree-setup"
type: AFK
status: done
blocked_by: [0013]
parent: docs/prd/concurrency-hardening.md
---

## What to build

> **Cross-repo tracker.** This work targets the **Agent-Builder repo**
> (`~/Wenrwa Projects/Agent-Builder`), NOT Valkyrie. It is filed here only so
> the follow-up is not lost. Valkyrie has zero dependency on it — Valkyrie's
> value is complete without any consumer hook.

In the Agent-Builder repo, add an executable `.valk-worktree-setup` at the
repo root, written against Valkyrie's documented hook contract (from #0013),
so a freshly created worktree comes up build-ready: install dependencies
(`npm ci`) and select a free dev-server port (so parallel worktrees don't
collide on the port). This is what delivers the "frictionless" promise for
Agent-Builder specifically; until it exists, `valk-worktree` still works
there (git-only) but the user does deps/port by hand.

## Acceptance criteria

- [x] An executable `.valk-worktree-setup` exists at the Agent-Builder repo
      root, conforming to Valkyrie's documented contract (#0013)
- [x] A new worktree created via `valk-worktree` comes up dependency-ready
      with a non-colliding dev port
- [x] Done in the Agent-Builder repo; committed there, not in Valkyrie
- [x] No change to Valkyrie required (confirms standalone independence)

## Delivered

Agent-Builder repo (BunnyDAO/BuildAICrew) commit `0799b38`:
`.valk-worktree-setup` (mode 755) + `.env*.local` gitignore. Lockfile-exact
`npm ci` + free dev port pinned in `.env.local`, idempotent. Verified port
pick + idempotency in a scoped dry-run. No Valkyrie change — confirms the
helper's standalone independence.

## Blocked by

- 0013 (the `.valk-worktree-setup` contract + sample must exist first)
