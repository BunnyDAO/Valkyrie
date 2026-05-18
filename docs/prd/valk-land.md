# valk-land — ergonomic, race-free integrate-back

## Problem Statement

`valk-worktree` (#0013) made concurrent Valkyrie flows safe by giving each
its own worktree + `valk/<name>` branch. But isolation did not delete the
work — it **moved** it: every isolated flow now ends with a branch that a
human must get back onto the main branch. Today that integrate-back is fully
manual (`git switch main && git merge valk/<name>`, or open a PR, then
`valk-worktree --remove`). In the multi-terminal scenario this is exactly
where friction and races came back: you finish three slices, then hand-merge
three branches, and between your local merge and your push another flow has
already moved `origin/main` — so you re-pull, re-merge, re-push, by hand,
three times. The ergonomic cost of "explicit merge work" (ADR-0001) is real
and currently paid entirely by the operator.

## Solution

A `valk-land <name>` companion to `valk-worktree`: one command that takes a
finished `valk/<name>` branch and lands it on the main branch **the way the
repo already says it wants PRs handled** — delegating to the repo's opt-in
`pr_skill` when one is configured, and doing a safe, test-gated, race-free
local rebase+fast-forward+push when one is not. It never force-pushes, never
auto-resolves a conflict, and never destroys a worktree behind your back; on
any doubt it aborts and leaves everything exactly as it was. It makes the
merge work *ergonomic and race-free* — it does not pretend conflicts or human
judgement went away.

## User Stories

1. As a solo dev with one finished `valk/feature` branch, I want `valk-land
   feature` to get it onto `main` in one command, so I stop hand-typing
   fetch/rebase/merge/push.
2. As the 3-terminal concurrent user, I want each flow's land to rebase onto
   the *current* `origin/main` and fast-forward-push, so two flows landing
   minutes apart don't clobber each other or need a manual re-pull dance.
3. As a user in a repo that configured `pr_skill: to-azure-pr`, I want
   `valk-land` to open the PR through that existing skill (push, PR, CI
   poll), so landing behaves identically to the rest of my Valkyrie workflow
   and the review/CI gate is preserved.
4. As a user in a local-first repo with **no** `pr_skill` (the default, incl.
   Valkyrie itself), I want `valk-land` to integrate locally without
   requiring any PR host, so the tool stays standalone.
5. As a careful engineer, I want the local land to run my project's test
   signal *after* rebasing onto the moved main and **abort if it's red**,
   so I never publish a slice that was green in isolation but breaks against
   the new main.
6. As a user whose repo declares `test_skill`, I want `valk-land` to use that
   same GREEN signal the `tdd` loop uses, so "verified" means the same thing
   everywhere.
7. As a user in a repo with no test signal at all, I want `valk-land` to
   refuse to land silently — warn loudly and make me pass `--force` — so an
   unverifiable land is always a conscious choice.
8. As a user whose branch conflicts with the moved main, I want `valk-land`
   to abort cleanly (branch + worktree untouched) and print the exact steps
   to resolve it *in my worktree*, so a conflict is a clear handoff, not a
   half-applied mess.
9. As a user, I never want `valk-land` to force-push or rewrite already-
   pushed history to make a land "work".
10. As an AFK-loop user, I want a successful land to *not* tear down my
    worktree by default, so the next slice reuses the deps-installed checkout
    instead of paying `npm ci` / `.valk-worktree-setup` again.
11. As a user who *is* done with the worktree, I want a `--clean` flag that
    lands then removes the worktree+branch in one go — but refuses if I'm
    standing inside that worktree, so it can't pull the rug out from under me.
12. As a returning maintainer, I want a one-command default that prints the
    exact `valk-worktree --remove <name>` next-step after a green land, so
    cleanup is obvious without being automatic.
13. As a Valkyrie maintainer, I want `valk-land` to touch no stage sub-skill,
    orchestrator, or crew-shim, so the single-flow/no-op path and the
    prd-review gate are provably unchanged.
14. As a future reader, I want the "why delegate-or-local / why never
    force-push / why rebase-linear" decision recorded as an ADR, so nobody
    "fixes" it into always-PR or force-push later.

## Implementation Decisions

- **New module: `scripts/valk-land`** — a standalone bash script
  (`#!/usr/bin/env bash`, macOS bash 3.2-portable; the repo's existing
  `scripts/*` are the style guide). Language-agnostic and standalone, the
  same posture as `valk-worktree`. Naming mirrors it exactly: `valk-land
  <name>` ↔ branch `valk/<name>` ↔ worktree `../<repo>-<name>`.
- **Land mechanism (delegate-or-local).** `valk-land` reads the repo's
  `.claude/valk-config.md` via the **existing** `scripts/read-valk-config.sh`
  parser (the same one `tdd` uses) for `pr_skill`:
  - `pr_skill` set (and the skill installed) → delegate the land to that
    skill (it already pushes the branch, opens the PR, polls CI, returns
    `ready_for_review`). `valk-land` adds no host logic of its own and does
    **not** double-push.
  - `pr_skill` absent / `none` (the local-first default, including Valkyrie
    itself) → the **local integrate path** below.
  This is the same opt-in precedent as `valk-config.md` and
  `.valk-worktree-setup`: default path assumes nothing.
- **Local integrate mechanic.** `git fetch`; **rebase `valk/<name>` onto
  fresh `origin/main`**; then fast-forward the main branch; then (default)
  sync-safe push. Linear, review-friendly history. `valk-land` is invoked
  against / resolves the **main checkout** and never force-updates a branch
  that is checked out elsewhere; it never force-pushes and never rewrites
  already-pushed history.
- **Local safety gate.** *After* the rebase and *before* finalizing/pushing,
  run the repo's GREEN signal — the `test_skill` from `valk-config.md` (same
  contract as the `tdd` loop), else an inferred runner. **Red → abort the
  land**, leaving `valk/<name>` and the worktree exactly as they were
  (nothing lost). No `test_skill` and none inferable → warn loudly and
  require an explicit `--force` to land unverified.
- **Conflict policy.** Any rebase conflict → `git rebase --abort`; branch +
  worktree untouched; print the precise manual-resolve steps to run **in the
  worktree**. `valk-land` never auto-resolves.
- **Push semantics.** Local path default = sync-safe fast-forward push to
  `origin` after the gate passes (a clean ff because we just rebased onto
  current `origin/main`; if `origin` moved *again* mid-land → abort, preserve
  everything, tell the user to re-run). `--no-push` stays purely local. PR
  path: pushing belongs to the `pr_skill`.
- **Cleanup coupling (opt-in).** Default on a green land: remove nothing —
  print the exact `valk-worktree --remove <name>` next-step (the branch is
  now merged, so that command's merged-only drop is safe). `--clean` does
  land+teardown in one go, but **refuses if `cwd` is inside the target
  worktree** (instructs the user to `cd` out first). `valk-land` and
  `valk-worktree` stay composable and independently understandable.
- **Compatibility constraint (explicit, same blast-radius care as the
  concurrency-hardening PRD).** `valk-land` is a new script only. It touches
  **no** stage sub-skill, **not** the `valk` orchestrator, **not** the
  crew-shim. Therefore `test-noop.sh`, the `prd-review` gate, and the
  crew-shim decision contract stay **byte-untouched**. It only *reuses*
  `read-valk-config.sh` read-only.
- **Installer.** `install.sh §5` PATH-symlinks `scripts/valk-land` exactly
  as it already does `scripts/afk` and `scripts/valk-worktree` (global; the
  scoped `--target` install test stays green).
- **Docs.** `SOP.md` and `docs/workflow.md` change the documented
  integrate-back from "manual" to "**manual or `valk-land`**" —
  `valk-land` becomes the supported ergonomic path; the manual merge/PR path
  stays documented and valid.
- **Proposed ADR `docs/adr/0002-valk-land-delegation-and-no-force.md`** —
  records the load-bearing, hard-to-reverse, surprising-without-context
  trade-off: why `valk-land` delegates-or-goes-local instead of always
  opening a PR, why it never force-pushes, why rebase-linear. It must stay
  consistent with and reference `docs/adr/0001-isolation-not-locking.md`
  (the parent decision). The PRD is the record; the ADR is seeded during
  implementation, not pre-created.
- **Honest hard limit (state plainly).** `valk-land` removes the
  *ergonomic* cost of integrate-back and makes it race-free; it does **not**
  remove merge conflicts or the need for human judgement. It is the cure's
  companion, not a second cure. Consistent with ADR-0001.

## Testing Decisions

- Good tests here assert **observable git/filesystem/exit-code behavior**,
  never script internals — the same discipline as `test-valk-worktree.sh`
  and `test-valk-guard-worktree.sh` (the prior art to mirror).
- Harness: a new `test/test-valk-land.sh`, auto-discovered by
  `test/run-tests.sh` (bash, **not** vitest). Build a temp repo with a
  **simulated origin** (a bare clone), one or more `valk/<name>` branches,
  and exercise: clean local land (rebase→ff→push, `origin/main` advanced);
  `--no-push` stays local; **moved-origin** mid-land aborts + preserves;
  induced **conflict** → `rebase --abort`, branch+worktree intact, guidance
  printed, non-zero-but-safe exit; **test-gate red** → land aborted, nothing
  pushed; no `test_skill` → refuses without `--force`, lands with it;
  `pr_skill` configured (injected via a temp `.claude/valk-config.md` +
  stub skill/marker) → delegates, no local push, no double-push; `--clean`
  removes worktree+branch on success but **refuses from inside** the
  worktree; default green land leaves the worktree intact and prints the
  remove hint.
- Regression guard: the suite is **11/11 green today and must stay green**;
  `test-noop.sh` must stay **byte-green** (it proves the untouched
  single-flow / crew-shim path).

## Out of Scope

- `valk-land` does **not** verify the issue's `status: done` — that is the
  `tdd` skill's job.
- It does **not** auto-resolve merge conflicts.
- It does **not** land multiple branches in one invocation — one
  `valk/<name>` per call, mirroring `valk-worktree`.
- **No GitHub/Azure/host logic baked into `valk-land`** — host behavior is
  entirely delegated to the opt-in `pr_skill`.
- It does **not** replace the manual merge/PR path, which stays documented
  and valid.
- It does **not** force-push or rewrite already-pushed history under any
  circumstance.
- No changes to stage sub-skills, the orchestrator, the crew-shim, or the
  `prd-review` gate.

## Further Notes

- Parent issue: `issues/0018-followup-valk-land-deferred-prd.md` (the
  deliberately-deferred placeholder this PRD discharges).
- Direct dependency on the shipped `valk-worktree` lifecycle (#0013): the
  `valk/<name>` ↔ `../<repo>-<name>` convention and `--remove`'s merged-only
  branch drop are the contract `valk-land` integrates with.
- Reuses, read-only, the existing `read-valk-config.sh` `pr_skill` /
  `test_skill` contract documented in `docs/valk-config-format.md`.
