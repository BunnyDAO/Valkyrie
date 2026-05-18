# valk-land delegates or lands locally; never force-pushes; rebase-linear

Status: accepted

## Context

Isolation (`valk-worktree`, ADR-0001) made concurrent flows safe by moving
collisions from silent commit-sweeps to **explicit merge work**: every
isolated flow ends with a `valk/<name>` branch a human must get back onto the
main branch. `valk-land <name>` automates that integrate-back. Three of its
decisions are hard to reverse (they shape a PATH-installed command, its
tests, the SOP, and consumer expectations) and surprising without context —
a future reader will ask "why doesn't it just always open a PR?", "why not
force-push to make a land 'work'?", "why rebase instead of merge?". Recorded
so nobody quietly changes them.

## Decision

- **Delegate-or-local, not always-PR.** If the repo opts in via
  `pr_skill` in `.claude/valk-config.md`, `valk-land` steps aside and that
  skill owns the PR (push, review, CI) — the same opt-in contract `tdd`
  already uses. With no `pr_skill` it lands locally
  (rebase → test-gate → fast-forward → sync-safe push).
- **Never force-push, never rewrite already-pushed history.** A land that
  cannot fast-forward aborts and preserves state; it is never "made to work"
  by `--force`.
- **Rebase-linear, not merge commits.** The local path rebases
  `valk/<name>` onto fresh `origin/main` and fast-forwards; history stays
  linear and review-friendly.

## Considered options

- **Always open a PR.** Rejected: it breaks standalone/local-first — Valkyrie
  itself (and many consumers) have no PR host. Forcing one would make the
  default path depend on infrastructure that need not exist, contradicting
  the same local-first stance behind `valk-config.md` and
  `.valk-worktree-setup`.
- **Force-push / rewrite to resolve a non-fast-forward.** Rejected: it
  destroys a concurrent flow's landed work and rewrites published history —
  exactly the class of corruption this whole effort exists to remove. An
  aborted, re-runnable land is strictly safer than a "successful" destructive
  one.
- **Merge commits instead of rebase.** Rejected: noisier history for an
  ephemeral per-flow branch; rebase-linear keeps review focused and makes
  conflicts surface explicitly, consistent with ADR-0001's "explicit merge
  work" framing.

## Consequences

- The land's behavior is driven entirely by the repo's existing opt-in
  config; `valk-land` carries **no** host logic of its own and never
  double-pushes.
- A no-fast-forward, a red `test_skill`, or a rebase conflict **aborts** and
  preserves the branch + worktree; the user re-runs after resolving. This is
  the honest hard limit inherited from
  [`0001-isolation-not-locking.md`](./0001-isolation-not-locking.md):
  `valk-land` makes integrate-back **ergonomic and race-free**, it does not
  eliminate merge conflicts or the human judgement a real conflict needs. It
  is the cure's companion, not a second cure.
- A repo with no `test_skill` must pass `--force` to land unverified (loud
  warning) — unverified landing is always a conscious choice.
- Second entry in the Valkyrie ADR log; extends, and stays consistent with,
  ADR-0001.
