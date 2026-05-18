---
id: 0021
title: valk-land conflict policy — abort clean, preserve, guide
type: AFK
status: open
blocked_by: [0019]
parent: docs/prd/valk-land.md
---

## What to build

Define what `valk-land` does when the rebase onto `origin/main` hits a merge
conflict. It does **not** auto-resolve and does **not** leave a half-applied
state: it runs `git rebase --abort`, leaving `valk/<name>` and the worktree
byte-identical to before the land attempt, and prints the precise manual
steps to resolve the conflict **in the worktree** (then re-run `valk-land`).
Exit is a clear non-zero, but the repository state is safe and unchanged.

This is the honest-hard-limit behavior from ADR-0001: `valk-land` makes
integrate-back ergonomic; it does not eliminate conflicts or the human
judgement a real conflict requires.

## Acceptance criteria

- [ ] An induced rebase conflict causes `valk-land` to `git rebase --abort`;
      `valk/<name>` and the worktree are byte-unchanged vs. before the call
- [ ] `origin/main` is not modified; nothing is pushed
- [ ] Output contains actionable manual-resolve guidance referencing the
      worktree and a re-run of `valk-land`
- [ ] Exit code is non-zero (failure signalled) but state is provably safe
- [ ] Bash test in `test/` induces a real conflict against a simulated
      origin and asserts the above; full suite stays green

## Blocked by

- 0019
