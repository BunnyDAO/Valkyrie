---
id: 0013
title: valk-worktree helper — create+remove lifecycle (the cure)
type: AFK
status: done
blocked_by: []
parent: docs/prd/concurrency-hardening.md
---

## What to build

The centerpiece: a one-command way to put each terminal in its own isolated
git worktree, so concurrent Valkyrie flows on one project cannot corrupt each
other. Standalone-valuable and language-agnostic.

- `valk-worktree <name>` → create a linked worktree on a fresh
  `valk/<name>` branch beside the repo; if an executable
  `.valk-worktree-setup` exists at the repo root, run it; then print the
  next steps ("cd here — you're isolated"). Idempotent / safe no-op if that
  worktree already exists.
- `valk-worktree --remove <name>` → remove the worktree and drop the
  `valk/<name>` branch when it is merged. The create+remove lifecycle is
  complete in v1 — a create-only helper would rot worktrees within a day.
- **No consumer hook required**: with no `.valk-worktree-setup` the helper
  still does the pure git worktree/branch — that alone is the cure. The
  hook is optional aid, the same pattern as `valk-config.md` (default path
  assumes nothing).
- **Define + document the `.valk-worktree-setup` contract** (when it runs,
  what it can rely on, exit semantics) and **ship a sample** so any consumer
  can drop one in.
- The installer registers the command on PATH the same way it registers the
  existing background-run helper.

## Acceptance criteria

- [x] `valk-worktree <name>` creates `../<repo>-<name>` on branch
      `valk/<name>`; runs `.valk-worktree-setup` iff present+executable;
      prints next steps; idempotent / safe no-op if it already exists
- [x] `valk-worktree --remove <name>` removes the worktree and drops the
      `valk/<name>` branch when merged; safe/clear if it doesn't exist
- [x] Works with NO `.valk-worktree-setup` present (git-only path) — proves
      standalone value; no npm/port logic baked into the helper
- [x] The `.valk-worktree-setup` contract is documented and a sample shipped
- [x] Installer PATH-registers the command; install test updated and green
- [x] Bash test in `test/` (temp git repo) covers: create, branch, hook-run,
      idempotency, `--remove` teardown, no-op safety — run via `run-tests.sh`

## Blocked by

- None — can start immediately
