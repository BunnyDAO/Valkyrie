---
name: tdd
description: Test-driven development with the red-green-refactor loop, using vertical slices (tracer bullets). Use when user wants to build features or fix bugs using TDD, mentions red-green-refactor, wants integration tests, asks for test-first development, or when /valk routes here at the TDD stage.
---

# Test-Driven Development

Adapted from mattpocock/skills with Valkyrie stage tracking.

## On entry

```bash
python3 ~/.claude/valkyrie/stage.py set tdd
```

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
1. Update the issue frontmatter `status: done`
2. Commit with a message referencing the issue id (e.g. `feat: add billing dashboard (#0003)`)
3. Tell the user: "Issue 000N done. Next unblocked: 000M. Continue?"

If invoked by `afk`, just exit cleanly — the loop will pick the next issue on its next iteration with a fresh context.
