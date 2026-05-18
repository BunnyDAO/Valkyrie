# valk-land resolves the repo's default branch; it never guesses it

Status: accepted

## Context

ADR-0002 describes `valk-land` as landing a `valk/<name>` branch onto **the
main branch** and rebasing onto **fresh `origin/main`** — generic language for
"the repo's default integration branch". The implementation, however,
hardcoded the literal string `main` at every site (rebase `origin/main`,
`rev-parse main` for the unwind anchor, `checkout main`, `push origin main`,
and the user-facing messages). Any consumer repo whose default branch is not
named `main` (e.g. `master`-default repos like BuildAICrew/Agent-Builder)
aborts at `git rev-parse main` and cannot be landed — the companion
`valk-worktree` is already base-agnostic (`git worktree add -b` off HEAD), so
the breakage was a silent asymmetry, not a recorded decision. ADR-0002 flags
valk-land's branch behavior as the class of thing "recorded so nobody quietly
changes them", so the resolution strategy is recorded here.

A **base** is the repo's default integration branch — the branch valk-land
fast-forwards and the rebase target lives on. It is a *role*, not the literal
name `main`.

## Decision

- **Resolve the base, don't assume it.** Derive `base` from
  `git -C "$root" symbolic-ref --quiet refs/remotes/origin/HEAD`
  (`refs/remotes/origin/<name>` → strip prefix). Use the single resolved
  `base` for the local ops (`rev-parse`/`checkout`/`merge --ff-only`/`push`)
  and `origin/$base` for the rebase target.
- **Never guess.** If `origin/HEAD` is unset or there is no origin, valk-land
  **aborts and preserves state** (per ADR-0002's stance) with a precise hint:
  run `git remote set-head origin -a`, or re-run with `--base <name>`.
  Probing local branches (`main` then `master`) was rejected — in a repo with
  both it can fast-forward/push the wrong branch, the exact silent corruption
  ADR-0001/0002 exist to remove.
- **`--base <name>` escape hatch, usable anytime.** An explicit `--base`
  always wins over auto-resolution, covering standalone/no-remote repos
  (a local-first case ADR-0002 explicitly cares about) and unusual remotes.
- **Verify before acting.** `origin/$base` must exist before the rebase;
  otherwise abort with the same hint rather than emit git's raw error.

Every ADR-0002 safety property is preserved unchanged: delegate-or-local,
never force-push, rebase-linear, green-gate-before-finalize,
unwind-on-rejected-push, run-from-main-checkout guard.

## Considered options

- **Probe local `main` then `master`.** Rejected: guesses; ambiguous when both
  exist; can land the wrong branch — reintroduces the corruption class.
- **Abort only, no `--base`.** Rejected: leaves genuinely no-remote /
  standalone repos (a case ADR-0002 names) with no non-manual land path.
- **Keep hardcoded `main`, document the limitation.** Rejected: contradicts
  ADR-0002's own generic "the main branch" intent and valk-land's
  "language-agnostic and standalone" header.

## Consequences

- valk-land works on any default-branch name; behavior on `main`-default
  repos is byte-unchanged (origin/HEAD resolves to `main`).
- New `--base <name>` flag joins `--no-push`/`--force`/`--clean`.
- A regression case in `test/test-valk-land.sh` pins that a `master`-default
  repo lands and that an unresolved base aborts with the hint.
- Third entry in the Valkyrie ADR log; extends, and stays consistent with,
  ADR-0001 and ADR-0002.
