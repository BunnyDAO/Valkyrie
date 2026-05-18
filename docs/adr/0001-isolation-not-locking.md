# Concurrency safety via frictionless isolation, not locking

Status: accepted

## Context

Users run multiple Claude+Valkyrie flows simultaneously against **one
checkout** of a project. A shared working tree has one index, one `HEAD`,
one set of files and one stage marker, so concurrent flows corrupt each
other: one flow's `git add`→`git commit` window is scooped by another's
broad commit (slices land in the wrong commit; once a broken pushed `HEAD`),
a half-written file reddens another flow's `tsc`/test run, and the single
`.claude/valk/stage` marker is clobbered.

We needed concurrency safety without abandoning the multi-terminal workflow,
which is itself a throughput multiplier the user values.

## Decision

Make **isolation the path of least resistance**, not concurrency control.

- **Cure — isolation (#0013):** a one-command `valk-worktree` helper puts
  each terminal in its own git worktree on its own `valk/<name>` branch.
  Concurrent flows then cannot share state, so the entire class of
  corruption is gone *by construction*. Language-agnostic, standalone, with
  an optional documented setup hook.
- **Mitigation — atomic commits (#0012):** the tdd skill commits via a
  single `git commit -- <explicit pathspecs>` + sync-safe push. This shrinks
  only the commit-sweep slice and only if every flow complies (it is prose
  to an operator, not enforceable by code).
- **Backstop — a self-silencing nudge (#0014):** the prompt guard points a
  user at `valk-worktree` while they are in the shared checkout and goes
  silent once they are isolated. Warn-only; it never blocks.

## Considered options

**A flow registry / lockfile / pid + heartbeat guard** (detect other live
flows, refuse or serialize) was explicitly **rejected**. It is the highest
risk for the least marginal gain: stale state (a crashed flow's lock/pid)
**false-locks the user out** of their own repo, heartbeat/pruning logic is
fragile, and even a perfect registry does not make two flows editing the
same file in one tree safe — it would only add a failure mode on top of a
problem it cannot actually solve. Isolation removes the shared state the
registry would be trying to police.

## Consequences

- **Honest hard limit:** no Valkyrie code can make a *shared* tree safe.
  Same-file races and a half-written file reddening a shared test run are
  **irreducible** without isolation. We do not pretend otherwise; #0012 is
  mitigation, #0013 is the cure, #0014 is a backstop — not a guarantee.
- Parallelism moves from silent commit-sweeps to **explicit merge work**: N
  flows on N `valk/<name>` branches must be landed on the main branch.
  Integrate-back is manual (merge/PR) for now; automating it (`valk-land`)
  is a deliberately deferred, separately-designed PRD (#0018).
- This file establishes the `docs/adr/` log for the Valkyrie repo (entry 0001).
