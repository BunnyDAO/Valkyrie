# Valkyrie concurrency hardening (multi-terminal on one project)

## Problem Statement

People run several Claude+Valkyrie terminals against the **same checkout** of
a project at once (confirmed: 3 simultaneously, routinely — it's the intended
working style). On one shared working tree this corrupts itself: one flow's
`git add` → `git commit` gap gets scooped by another flow's `git commit -a`
(whole slices land in the wrong commit; once it produced a *broken pushed
HEAD*), a half-written file from one flow reddens the shared `tsc`/test run
for the others, and the single per-cwd stage marker is clobbered. The user
mitigated by hand all session — that overhead shouldn't exist.

## Solution

Make the **safe parallel mode trivial**, instead of nagging people out of a
workflow they want:

- One command per terminal — `valk-worktree <name>` — puts that terminal in
  its own isolated git worktree+branch (and runs the project's own setup), so
  concurrent flows can't collide *by construction*.
- A one-time, self-silencing nudge points at that command whenever you're in
  the unsafe shared checkout, and goes quiet automatically the moment you're
  isolated.
- As defense-in-depth, Valkyrie's own commit step becomes atomic so a stray
  shared-tree flow is far less destructive.

The honest framing the user should keep: isolation is the *cure*; the rest is
mitigation. No code can make two flows editing the same file, or a
half-written file reddening a shared test run, safe — only separate working
trees can.

## User Stories

1. As someone running 3 Valkyrie terminals on one project, I want each
   terminal isolated in one command, so concurrent work can't corrupt itself.
2. As that user, I want the safe mode to be *less* friction than the unsafe
   one, so I never choose the unsafe path by inertia.
3. As that user, I do NOT want a guard nagging me every prompt during my
   normal (now-isolated) workflow — the reminder must vanish once I'm in a
   worktree.
4. As that user, when I'm still in the shared checkout I want exactly one
   clear pointer to the fix, not silence-until-damage.
5. As a Valkyrie maintainer, I want `valk-worktree` language-agnostic (the
   Valkyrie repo is bash/python; consumers vary), with project-specifics
   opt-in per repo, so it works everywhere without assuming Node.
6. As an Agent-Builder user, I want my worktree to come up build-ready
   (deps + a free dev port), via a project-local hook the helper runs.
7. As a Valkyrie maintainer, I want the stage skills to commit atomically so
   a concurrent commit can't sweep an in-flight slice into the wrong commit.
8. As a Valkyrie maintainer, I want the atomic-commit change to *only add*
   commit guidance — not touch stage order, gates, or the crew-shim contract
   — so Agent-Builder's `valk-config`/crew-shim consumers are unaffected.
9. As a Valkyrie maintainer, I want the riskiest machinery (a live-flow
   registry with pids/heartbeat/stale-pruning) **not** built — a cheap
   worktree check delivers the safety net without that failure surface.
10. As a user, I want to know exactly what takes effect when: the prose fix
    live immediately, the script/hook fixes after one `install.sh`.
11. As a contributor, I want `valk-worktree` and the guard check covered by
    the repo's bash test harness, and the single-flow path proven unchanged.

## Implementation Decisions

- **(A) Atomic-commit recipe — `skills/tdd/SKILL.md`** (the only stage skill
  that mandates a commit; add a one-liner anywhere another skill commits).
  Replace the bare "Commit with a message referencing the issue id" with:
  commit via a **single `git commit -- <explicit pathspecs>`** (snapshots
  exactly those paths, ignores the rest of the shared index, no add→commit
  window); then push **sync-safe** (`git fetch`; if the remote moved
  `git pull --rebase`; then push); **never** `git add -A`, `git commit -a`,
  or `git add` then a separate `git commit`. Add the post-failed/empty-commit
  reconcile note: assume a concurrent flow swept your paths → `git fetch`,
  inspect `git log`/`git ls-files`, verify integrity, reconcile; prefer the
  integrity-fix (make the pushed tip compile) over rewriting pushed history;
  document the attribution wart in the issue. Skills are **symlinked** by
  `install.sh` into `~/.claude/skills/` → **A is live immediately, no
  reinstall**.
- **(C, centerpiece) `scripts/valk-worktree` — new; full create+remove
  lifecycle (both in scope).** Generic git core only:
  - `valk-worktree <name>` → `git worktree add ../<reponame>-<name>
    -b valk/<name>`; then if an executable `.valk-worktree-setup` exists at
    the repo root, run it; then print next steps ("cd here, you're
    isolated"). Idempotent / safe no-op if the worktree already exists.
  - `valk-worktree --remove <name>` → `git worktree remove` + drop the
    `valk/<name>` branch when merged. The lifecycle is **complete in v1** —
    a create-only helper would rot worktrees within a day (bad UX); "done
    properly" = the helper that creates also tears down.
  **Standalone-valuable & language-agnostic.** Valkyrie's value here is
  complete with **no consumer present**: with no `.valk-worktree-setup` the
  helper still does the git-only worktree/branch — still the cure. The hook
  is **pure optional aid, the exact same pattern as `valk-config.md`**
  (default path assumes nothing; vanilla-by-default). In scope for Valkyrie:
  **define + document the hook contract and ship a sample
  `.valk-worktree-setup`** so frictionless is *achievable* the moment a
  consumer drops it in. No npm/port logic is ever baked into the helper.
  `install.sh` PATH-symlinks it exactly like `scripts/afk`.
- **(B, simplified) Worktree-awareness nudge — in `scripts/valk-guard.sh`.**
  Add a cheap check (main checkout vs linked worktree, via
  `git rev-parse --git-dir`/`--git-common-dir`). If running in the **main
  checkout**, emit **one** gentle reminder pointing at `valk-worktree`;
  inside a linked worktree it is **silent** (self-extinguishing once
  isolated). **Warn-only, never blocks, no false-lock.** Explicitly **no**
  flow registry / pids / heartbeat / stale-pruning — that machinery is
  dropped as highest-risk-for-least-gain; the cheap stateless check delivers
  the backstop. `valk-guard.sh` is **copied** to `~/.claude/hooks/` by
  `install.sh` → B needs one reinstall.
- **(SOP) `SOP.md` + `docs/workflow.md`.** Document worktree-per-flow as the
  *supported* parallel mode, and the integrate-back story: each flow on its
  own `valk/<name>` branch, landed via merge/PR (no second helper — the
  branch→merge path is documented, not automated, per scope).
- **`install.sh`** gains the `valk-worktree` PATH symlink (the one reinstall
  that lands B + C). No change to stage order, gates, or the crew-shim
  contract.
- **Compatibility constraint (cross-repo blast radius):** the four stage
  sub-skills are shared and Agent-Builder's `crew-shim` + `valk-config`
  contract depend on them. A **only adds commit-recipe prose to `tdd`**; it
  must not alter stage ordering, the `prd-review` gate, or the crew-shim
  decision contract. `test-noop.sh` must stay byte-green.
- **Honest hard limit (stated, not glossed):** A shrinks only the
  commit-sweep slice; B is a backstop, not a guarantee; **C (isolation) is
  the only actual cure.** Two flows editing the same file, or a half-written
  file reddening a shared `tsc`/test run, are irreducible on one tree — no
  Valkyrie code fixes that.

## Testing Decisions

- **TDD `scripts/valk-worktree`** (bash, `test/`, `test-guardrails.sh`/
  `test-target-install.sh` style): in a temp git repo it creates the
  worktree + `valk/<name>` branch; runs `.valk-worktree-setup` iff present;
  is idempotent / a safe no-op if the worktree exists; fails cleanly on bad
  input. Behaviour observed via git state + filesystem, not internals.
- **TDD the B check in `valk-guard.sh`**: invoked from the main checkout →
  the nudge appears in output exactly once and references `valk-worktree`;
  invoked inside a linked worktree → no nudge; it never changes exit
  behaviour (warn-only).
- **`test-noop.sh` regression wall**: the single-flow path and the crew-shim
  no-op stay byte-identical (A is prose — there is *no* unit test that can
  assert an LLM obeyed it; this is stated plainly, not hidden).
- **`test-target-install.sh`**: `install.sh` still wires skills/hook/
  statusline correctly and now also PATH-symlinks `valk-worktree`.
- A's prose, the SOP docs, and the install symlink wiring are verified by
  review + the install test — not unit-tested.

## Out of Scope

- Any locking / flow-registry / pid / heartbeat / stale-pruning mechanism
  (explicitly rejected — highest risk for least marginal gain given C).
- A hard block / refusal on contention (warn-only; a stale signal must never
  lock a user out).
- Auto-creating or auto-`cd`-ing a worktree for the user (can't relocate a
  running session; too magic).
- An automated branch-integration / `valk-land` companion — **deferred to its
  own tracked follow-up PRD** (auto-rebase-vs-PR / CI-gating / conflict policy
  are real forks deserving their own grill; bolting it on here is the
  scope-creep the design deliberately cut). SOP documents the manual merge
  path meanwhile; a follow-up issue captures "design valk-land" so it is
  tracked, not vague.
- npm/Next/port logic inside `valk-worktree` (project-specific; lives in the
  opt-in `.valk-worktree-setup`).
- Changes to stage order, the `prd-review` gate, the crew-shim contract, or
  any stage sub-skill other than the `tdd` commit-recipe prose.
- Solving same-file races / shared-tree false-red runs by code (impossible —
  isolation only).
- Anything outside concurrency hardening (scope was locked to this).
- The Valkyrie-side stage marker design (already cwd-scoped; dissolves under
  worktrees — no change).

## Further Notes

- **Rollout:** A is zero-friction (skills symlinked → live on next `tdd`
  invocation). B + C require one `install.sh` run to copy the updated guard
  hook and register the `valk-worktree` command; thereafter the command is a
  live symlink.
- **Tracked follow-ups (explicit, not vague — "do the follow-ups"):**
  (1) **Agent-Builder ships a `.valk-worktree-setup`** (`npm ci` + free dev
  port) — a small task **in the Agent-Builder repo**, against Valkyrie's
  documented hook contract; *not* a Valkyrie dependency, *not* in this PRD's
  build. (2) **`valk-land`** — a separate deferred Valkyrie PRD for
  branch→master integration (its own grill). Both must exist as filed issues
  out of this effort so they are not lost; Valkyrie remains fully valuable
  without either.
- **Target-repo discipline:** this entire effort lives in
  `~/Wenrwa Projects/Valkyrie` — the PRD, issues, and all commits go there,
  **not** Agent-Builder. (The `stage.py` marker wrote Agent-Builder's path
  because it is cwd-based and the harness cwd is Agent-Builder — itself a
  small instance of the very limitation this PRD addresses; ignore that
  marker for this effort.)
- **ADR:** the Valkyrie repo has no `docs/adr/` yet. The load-bearing
  decision — *concurrency safety is achieved by making isolation (a worktree
  helper) frictionless, NOT by a locking/registry guard* — is hard-ish to
  reverse, surprising without context, and a real registry-vs-helper
  trade-off. Recommend seeding `docs/adr/0001-isolation-not-locking.md` as a
  downstream slice; this PRD is the binding record regardless.
- This is a generic-tool change: keep everything language-agnostic; the only
  Node-specific behaviour ever lives in a consumer repo's
  `.valk-worktree-setup`.
