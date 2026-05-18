---
id: 0012
title: Atomic-commit recipe in the tdd stage skill
type: AFK
status: done
blocked_by: []
parent: docs/prd/concurrency-hardening.md
---

## What to build

Replace the bare commit instruction in the tdd stage skill with an explicit
concurrency-safe recipe, so a flow's commit can no longer be scooped by a
concurrent flow's broad commit.

The recipe a stage skill follows when it commits:

- Commit atomically with a single `git commit -- <explicit pathspecs>`
  (snapshots exactly those paths, ignores the rest of the shared index, no
  add→commit window). Never `git add -A`, never `git commit -a`, never
  `git add` followed by a separate `git commit`.
- Then push sync-safe: fetch; if the remote moved, rebase; then push.
- If the commit comes back empty/failed, assume a concurrent flow already
  swept those paths into its own commit: fetch, inspect the log, verify the
  tip still builds, reconcile. Prefer the integrity-fix (make the pushed tip
  compile) over rewriting already-pushed history; record the attribution
  wart in the issue rather than force-pushing.

Add a one-line pointer to this recipe anywhere another stage skill commits.

**Hard constraint:** this only *adds commit guidance to the tdd skill*. It
must not change stage ordering, the prd-review gate, or the crew-shim
decision contract — consumers (e.g. a repo with `valk-config.md`) must be
unaffected.

## Acceptance criteria

- [ ] The tdd skill's commit step prescribes the atomic
      `git commit -- <pathspecs>` + sync-safe push + post-sweep reconcile
- [ ] It explicitly forbids `git add -A` / `git commit -a` / add-then-commit
- [ ] No change to stage order, the prd-review gate, or the crew-shim
      contract; `test-noop.sh` stays byte-green
- [ ] Honest note in the PRD/issue that this is prose to an operator —
      mitigation, not cure, and not unit-testable (no bash test can assert
      an LLM obeyed it); the cure is isolation (#0013)
- [ ] Lands in the repo `skills/` source; live immediately via the install
      symlink (no reinstall needed)

## Blocked by

- None — can start immediately
