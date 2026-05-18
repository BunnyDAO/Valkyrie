# valk-land resolves the repo's default branch

## Problem Statement

A user finishes an isolated flow in any repo whose default branch is not named
`main` (e.g. `master`-default repos like BuildAICrew/Agent-Builder) and runs
`valk-land <name>` to integrate it back. It aborts — `git rev-parse main`
fails — and the user is forced to hand-roll the rebase/ff/push, defeating the
point of the tool. `valk-land`'s own header claims "language-agnostic and
standalone" and its companion `valk-worktree` already works on any branch, so
this is a silent, surprising asymmetry, not a documented limitation.

## Solution

`valk-land` works on any repo regardless of what its default branch is named.
It figures out the repo's actual default branch and integrates onto that. When
it genuinely cannot determine the default branch, it does the safe Valkyrie
thing — aborts and preserves state with a precise, copy-pasteable hint —
rather than guessing and risking landing onto the wrong branch. A `--base`
flag lets the user state the branch explicitly for standalone/no-remote repos
or any unusual case. On `main`-default repos, nothing changes.

## User Stories

1. As a developer landing a flow in a `master`-default repo, I want
   `valk-land <name>` to just work, so that I don't hand-roll the integrate-back.
2. As a developer in a repo with any default branch name, I want `valk-land`
   to resolve it automatically, so that the tool is genuinely
   language/branch-agnostic as advertised.
3. As a developer on a `main`-default repo, I want behavior to be exactly as
   before, so that this change is risk-free for the common case.
4. As a developer in a standalone/no-remote repo (a case Valkyrie explicitly
   supports), I want a `--base <name>` flag, so that I can still land without
   an origin remote.
5. As a developer whose `origin/HEAD` is unset (fresh clone, never ran
   `git remote set-head`), I want `valk-land` to abort with a precise hint
   (the exact remediation command, and the `--base` option), so that I can fix
   it in one step instead of decoding a raw git error.
6. As a maintainer, I want `valk-land` to **never guess** the base, so that it
   can never fast-forward/push the wrong branch — preserving the no-silent-
   corruption guarantee of ADR-0001/0002.
7. As a maintainer, I want every existing ADR-0002 safety property
   (delegate-or-local, never-force, rebase-linear, green-gate,
   unwind-on-rejected-push, run-from-main-checkout) preserved byte-for-byte,
   so that this fix changes only branch resolution and nothing else.
8. As a maintainer, I want a regression test that a `master`-default repo
   lands and an unresolved base aborts with the hint, so that the defect
   cannot silently return.
9. As a reviewer, I want the rationale recorded in an ADR, so that nobody
   re-hardcodes `main` "to simplify".

## Implementation Decisions

- **Governing ADRs**: `docs/adr/0002-valk-land-delegation-and-no-force.md`
  (unchanged safety contract) and `docs/adr/0003-valk-land-resolves-default-branch.md`
  (written this DESIGN session — the decision of record; this PRD references,
  does not duplicate it). No `CONTEXT.md` (Valkyrie has none; the canonical
  "**base** = the repo's default integration branch, a *role* not the literal
  name `main`" lives in ADR-0003).
- **Modules**: `scripts/valk-land` is the single deep change behind a tiny CLI
  surface; `test/test-valk-land.sh` is the regression pin (append, per the
  file's documented "subsequent issues append cases" convention).
- **Base resolution**: derive once from
  `git -C "$root" symbolic-ref --quiet refs/remotes/origin/HEAD`, strip the
  `refs/remotes/origin/` prefix → `$base`. Use `$base` for the local ops
  (`rev-parse`, `checkout`, `merge --ff-only`, `push origin $base`) and
  `origin/$base` for the rebase target and existence check. The unwind anchor
  becomes `pre_$base` (was `pre_main`). User-facing messages interpolate
  `$base` instead of the literal "main".
- **Never guess**: if `symbolic-ref` yields nothing (origin/HEAD unset, or no
  origin remote), abort and preserve state (consistent with ADR-0002's
  abort-and-preserve / never-"made-to-work" stance) printing a hint naming
  both remedies: `git remote set-head origin -a`, or re-run with
  `--base <name>`. Probing local `main` then `master` is rejected — it guesses
  and can integrate onto the wrong branch.
- **`--base <name>` flag**: explicit override, always wins over
  auto-resolution, usable anytime; slots alongside `--no-push`/`--force`/
  `--clean` and the positional `<name>` in the existing arg parser.
- **Verify before acting**: `origin/$base` must exist before the rebase;
  otherwise abort with the same hint rather than surfacing git's raw error.
- **`valk-worktree` untouched** — already base-agnostic; the asymmetry is
  isolated to `valk-land`.
- **Backward compatibility**: on a `main`-default repo `origin/HEAD` resolves
  to `main`, so the resolved `$base` is `main` and behavior is byte-identical
  to today.

## Testing Decisions

- Behavior is observed through **git state, filesystem, and exit code only**
  (the existing `test-valk-land.sh` discipline — "never internals").
- **Prior art / harness**: `test/test-valk-land.sh`'s `mkfixture` builds a
  seed repo → bare origin → main checkout → `valk/feat` worktree → an
  independent concurrent push. The regression mirrors it with the seed's
  default branch set to **`master`** (`git branch -M master`); `git clone`
  propagates `origin/HEAD → origin/master`, so resolution must yield `master`
  and the land must succeed (linear, ff, pushed) — the exact assertions the
  existing 0019 case makes, but proving the defect is gone.
- A second case: a fixture with `origin/HEAD` removed and **no** `--base` →
  `valk-land` exits non-zero, origin/main(or master) untouched, branch+worktree
  preserved, stderr contains the remediation hint; the same fixture **with**
  `--base <name>` lands successfully.
- A `main`-default case stays green unchanged (the existing 0019/0020 cases
  serve as the backward-compat pin — they must keep passing verbatim).
- Run via `test/run-tests.sh` (auto-discovers `test-*.sh`); the whole suite
  must be green before landing.

## Out of Scope

- Changing any ADR-0002 safety decision (delegate-or-local, never-force,
  rebase-linear, abort-and-preserve).
- Modifying `valk-worktree` or any other script.
- Any PR/host logic, or pushing to `BunnyDAO/Valkyrie` — this work lands into
  **local** Valkyrie `main` only; the user reviews before any push.
- Auto-running `git remote set-head` on the user's behalf (that mutates their
  repo config silently — the hint tells them to, it does not do it).
- A `CONTEXT.md` for Valkyrie.

## Further Notes

- `~/.local/bin/valk-land` is symlinked to the **main** Valkyrie checkout, so
  the fix only affects the live tool once landed into local `main`; all work
  stays in the isolated worktree `Valkyrie-land-default-branch` until then.
- ADR number 0003 was free at design time; re-check for collision at
  integrate-back if a concurrent session also added an ADR.
- Valkyrie's own default branch is `main`, so once landed, `valk-land` will
  resolve `main` for the Valkyrie repo itself — no behavior change there.
