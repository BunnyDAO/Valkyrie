---
name: tdd
description: Test-driven development with the red-green-refactor loop, using vertical slices (tracer bullets). Use when user wants to build features or fix bugs using TDD, mentions red-green-refactor, wants integration tests, asks for test-first development, or when /valk routes here at the TDD stage.
---

# Test-Driven Development

Adapted from mattpocock/skills with Valkyrie stage tracking.

## On entry

```bash
python3 "$(for p in .claude/valkyrie/stage.py "$HOME/.claude/valkyrie/stage.py" "$HOME/.claude/valk/stage.py"; do [ -f "$p" ] && echo "$p" && break; done)" set tdd
```

**Cost discipline.** The main session orchestrates the red-green-refactor loop and owns the
human checkpoints; where it helps, delegate a slice's actual implementation or a QA pass to a
**single-task sonnet/haiku sub-agent** (Agent tool) and bring back just the result, to keep the
main thread lean. If a delegated attempt fails QA ~twice, **escalate the sub-agent's model one
tier** (haiku → sonnet → opus) rather than grinding on the cheap tier — opus is the ceiling,
then surface to the human. (`afk` automates this per issue by default; `--no-escalate` to opt out.) See `valk` →
"Delegation & cost discipline".

## Philosophy

**Core principle**: Tests verify behavior through public interfaces, not implementation details. Code can change entirely; tests shouldn't.

**Good tests** are integration-style: they exercise real code paths through public APIs. They describe *what* the system does, not *how*. A good test reads like a specification — "user can checkout with valid cart" tells you what capability exists. These survive refactors.

**Bad tests** mock internal collaborators, test private methods, or verify through external means (querying the DB instead of using the interface). The warning sign: your test breaks when you refactor but behavior hasn't changed.

## Anti-pattern: horizontal slices

**DO NOT write all tests first, then all implementation.** That is "horizontal slicing" — RED becomes "write all tests" and GREEN becomes "write all code."

This produces **crap tests**:
- Tests written in bulk test *imagined* behavior, not *actual* behavior
- You end up testing the *shape* of things (data structures, signatures) rather than user-facing behavior
- Tests become insensitive to real changes — they pass when behavior breaks, fail when behavior is fine
- You outrun your headlights, committing to test structure before understanding the implementation

**Correct approach**: vertical slices via tracer bullets. One test → one implementation → repeat. Each test responds to what you learned from the previous cycle.

```
WRONG (horizontal):
  RED:   test1, test2, test3, test4, test5
  GREEN: impl1, impl2, impl3, impl4, impl5

RIGHT (vertical):
  RED→GREEN: test1→impl1
  RED→GREEN: test2→impl2
  RED→GREEN: test3→impl3
```

## Workflow

### 1. Pick the next slice

If `issues/` exists, read it. Pick the next issue whose `blocked_by` list is empty or all-`done`. Mark its `status` to `in_progress` in the frontmatter. If multiple are unblocked, ask the user to pick (or, when invoked from `afk`, pick the lowest id).

If no `issues/` exists, ask the user what behavior they want to build.

### 2. Plan

Before writing any code:
- [ ] Confirm interface changes needed
- [ ] Confirm which behaviors to test (prioritize)
- [ ] Identify opportunities for **deep modules** (small interface, deep implementation)
- [ ] Design interfaces for testability
- [ ] List the behaviors to test (not implementation steps)
- [ ] Get user approval on the plan (skip approval when invoked from `afk` — the issue acceptance criteria *are* the plan)

Ask: "What should the public interface look like? Which behaviors are most important to test?"

### 3. Tracer bullet

Write ONE test that confirms ONE thing:

```
RED:   write test for first behavior → it fails for the right reason
GREEN: write minimal code to pass     → it passes
```

This is your tracer bullet — proves the path works end-to-end.

### 4. Incremental loop

For each remaining behavior:

```
RED:   write next test → fails
GREEN: minimal code to pass → passes
```

Rules:
- One test at a time
- Only enough code to pass current test
- Don't anticipate future tests
- Keep tests focused on observable behavior

**GREEN signal source (config-gated):**

If `<repo>/.claude/valk-config.md` declares `test_skill: <name>`, the GREEN signal must come from invoking that skill — not from running whatever test command you infer from context. Read the config:

```bash
read-valk-config.sh test_skill
```

If the output is non-empty, invoke that skill and treat GREEN as "the skill returned success." If the output is empty, fall back to running tests the way you'd normally infer (current behavior).

This forces the project's canonical test stack to be the green signal — not vibes-level local unit tests.

### 5. Refactor

Only after tests are green. Look for:
- [ ] Extract duplication
- [ ] Deepen modules (move complexity behind simple interfaces)
- [ ] Apply SOLID where natural
- [ ] Run tests after each refactor step

**Never refactor while RED.** Get to GREEN first.

## Per-cycle checklist

```
[ ] Test describes behavior, not implementation
[ ] Test uses public interface only
[ ] Test would survive an internal refactor
[ ] Code is minimal for this test
[ ] No speculative features added
```

## On completion

When all acceptance criteria are checked off:

1. **Commit — concurrency-safe recipe (do exactly this).** Other Valkyrie
   flows may share this working tree; a `git add` then a separate `git
   commit` is a race window another flow's `git commit -a` will scoop. So:

   - Stage only this slice's files by **explicit pathspec**, then commit
     **scoped to those same pathspecs**:

     ```bash
     git add -- <file> [<file> …]
     git commit -m "<type>: <summary> (<issue-id>)" \
                -m "Co-Authored-By: …" \
                -- <file> [<file> …]
     ```

     The commit's `-- <pathspecs>` is the actual protection: it commits
     **only** those paths regardless of what another flow staged in the
     shared index. The `-m` flags **must come before** `--` (anything after
     `--` is parsed as a pathspec). `git add` is still required for new
     files — the pathspec on `commit`, not the absence of `add`, is what
     makes it safe. **Never** `git add -A`, **never** `git commit -a`,
     **never** a bare `git commit` with no pathspec.
   - Push sync-safe: `git fetch`; if the remote moved, `git pull --rebase`;
     then push.
   - If the commit comes back **empty/failed**, assume a concurrent flow
     already swept those paths into its own commit: `git fetch`, inspect
     `git log` / `git ls-files`, verify the pushed tip still builds,
     reconcile. Prefer the integrity-fix (make the pushed tip compile) over
     rewriting already-pushed history; record the attribution wart in the
     issue rather than force-pushing.

   The message still references the issue id (e.g.
   `feat: add billing dashboard (pvp-v1-03)`).

2. **Manual test gate.** Before any flip to `status: done`, read the issue file
   and look for a `## Manual test checklist` section. Unit tests don't cover
   interaction quality — a real trial run shipped a UX that needed substantive
   rework once a human actually used the app (the original click-and-drag was
   wrong; it became obvious only on manual use that a freeform brush was the
   right interaction). The agent had already flipped `status: done` and moved
   on, so the workflow gave no place to catch it.

   - **No `## Manual test checklist` section** → proceed to step 3.
   - **Section present, every item already ticked (`- [x]`)** → proceed to step 3.
   - **Section present, one or more items unchecked (`- [ ]`)** → STOP. List the
     unchecked items verbatim in chat, then call `AskUserQuestion` (**single-
     select**, NOT multiSelect) with exactly these three options:

     - `question`: *"Issue <issue-id> has N unchecked manual test items above. Manual
       checks catch what unit tests can't — UX feel, file rendering,
       interactions. Confirm before I flip status: done."*
     - **`"Manual checklist passes — flip status: done"`** —
       description: `"I've run every item and they pass. Tick them and complete the issue."`
     - **`"Manual checklist failed — keep this issue open"`** —
       description: `"Something doesn't work; the issue stays open while I fix or rework."`
     - **`"Haven't tested yet — wait"`** —
       description: `"I'll come back; don't flip done until I confirm."`

     On **passes** → edit the issue file, flip each `- [ ]` under the manual
     checklist to `- [x]`, then proceed to step 3.
     On **failed** → STAY on this issue. Ask the user what's wrong; treat as
     continued TDD on the same id (more red-green-refactor; another commit later).
     Do NOT proceed to step 3.
     On **wait** → STAY on this issue. Respond: *"Standing by — ping me when
     you're ready to confirm."* Do NOT proceed.

   Prose replies follow the same rule — explicit `pass` / `fail` / `wait`, not a
   bare "ok" / "yes" / "lgtm." If invoked by `afk` (autonomous mode), there is
   no human to ask — log the unchecked items to the issue's frontmatter as
   `stuck_reason: manual_checklist_pending` and exit cleanly so the loop moves
   on; the issue stays `status: open` for the next interactive session.

3. **Read the repo's `.claude/valk-config.md`** to decide what "done" means:

   ```bash
   PR_SKILL=$(read-valk-config.sh pr_skill)
   ```

   - **`PR_SKILL` is empty or `none`** → current behavior. Update issue frontmatter `status: done`. Tell the user "Issue <issue-id> done."
   - **`PR_SKILL` is set** (e.g. `to-azure-pr`) → invoke that skill via the Skill tool. The skill pushes the branch, opens the PR, waits for CI, and returns a JSON result. Then:
     - `ready_for_review: true` → write the `pr_url` into the issue frontmatter alongside `status: done`. Tell the user: "Issue <issue-id> done. PR: <url>"
     - `ready_for_review: false` → leave issue `status: open` and write `stuck_reason: <ci_status>` into the frontmatter. Tell the user what blocked the green signal.
   - **`PR_SKILL` is set but the named skill is not installed** → STOP. Tell the user: "Config requires /<name> but it's not available. Install it or set pr_skill: none in .claude/valk-config.md."

4. If invoked by `afk`, exit cleanly — the loop reads the result on its next iteration with a fresh context.

**Why this matters**: "done" without a PR is a frontmatter flip; "done" with a PR is a reviewable artifact. The config gate ensures repos that haven't opted in see no change in behavior.
