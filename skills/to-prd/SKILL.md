---
name: to-prd
description: Turn the current conversation context into a PRD and save it to docs/prd/ (or publish to the issue tracker if one is configured). Use after a grill-with-docs session, when the user says "turn this into a PRD", or when /valk routes here at the PRD stage.
---

# To PRD

Adapted from mattpocock/skills with Valkyrie stage tracking and a local-first default.

## On entry

```bash
python3 ~/.claude/valkyrie/stage.py set prd
```

## What to do

This skill takes the current conversation context and codebase understanding and produces a PRD. **Do NOT interview the user** — synthesize what you already know from the grilling session. If the conversation does not contain a grilling session, refuse and tell the user to run `/grill-with-docs` first (Valkyrie should already be enforcing this).

## Process

1. **Explore the repo** to understand the current state of the codebase, if you haven't already. Use the project's domain glossary (`CONTEXT.md` if present) throughout the PRD, and respect any ADRs in the area you're touching.

2. **Sketch the major modules** you will need to build or modify. Actively look for opportunities to extract **deep modules** — small, stable interfaces hiding a lot of behavior — that can be tested in isolation.

   Check with the user that the module list matches their expectations. Ask which modules they want tests written for.

3. **Write the PRD** using the template below.

4. **Save it.** Default location: `docs/prd/<slug>.md` in the current repo. Create the directory if needed. If `gh` is configured and the user has previously asked to use issues, also create a tracker issue with the `ready-for-agent` label.

## PRD template

```markdown
# <Feature Title>

## Problem Statement
The problem the user is facing, from the user's perspective.

## Solution
The solution to the problem, from the user's perspective.

## User Stories
A LONG, numbered list. Each story:
1. As an <actor>, I want <feature>, so that <benefit>

Cover all aspects of the feature.

## Implementation Decisions
- Modules to build/modify
- Interfaces of those modules
- Technical clarifications from the user (from the grilling session)
- Architectural decisions
- Schema changes, API contracts, specific interactions

Do NOT include specific file paths or full code snippets — they go stale fast.
Exception: if a prototype produced a snippet that encodes a decision more
precisely than prose can (state machine, reducer, schema, type shape), inline
the decision-rich part and note it came from a prototype.

## Testing Decisions
- What makes a good test here (test external behavior, not internals)
- Which modules will be tested
- Prior art for similar tests

## Out of Scope
What this PRD intentionally does NOT cover.

## Further Notes
Anything else worth recording.
```

## After saving — the PRD review gate

The PRD is the contract. Every downstream issue and every line of TDD code inherits its errors. A PRD nobody read is the single most expensive failure in the workflow. So this is a **hard checkpoint**, not a "ready?" question.

### 1. Move to the review stage

```bash
python3 ~/.claude/valkyrie/stage.py set prd-review
```

The statusline now shows **▶ REVIEW-PRD** — the signal that the human owes the PRD a read before anything proceeds.

### 2. Surface the decisions inline — do NOT just print the path

The user should not have to open a file to review. Reproduce these sections from the PRD you just wrote, verbatim, in the conversation:

- **Implementation Decisions** (every bullet)
- **Out of Scope** (every bullet)
- **User Stories** (the 3–5 most consequential — not all of them if the list is long)

Then state the path: "Full PRD: `docs/prd/<slug>.md`."

### 3. Demand substantive approval

Ask the user to do ONE of:

- **Approve** by confirming at least one specific decision back to you in their own words (e.g. "yes, event-sourced orders and the Postgres write model are right"), OR
- **Redline** — name a decision to change, and what to.

**A bare "yes", "looks good", "lgtm", "sure", "proceed", or silence is NOT approval.** If you get one, respond:

> "That's not engagement with the PRD — and an unreviewed PRD is exactly what Valkyrie exists to prevent. Tell me one decision in the Implementation Decisions or Out of Scope list that you agree with or want changed, in your own words. Then we proceed."

Do not advance until the user has either confirmed a specific decision or requested a specific change. If they redline, revise the PRD, re-save, and re-run this gate from step 2.

### 4. Hand back to the orchestrator

Once the user has substantively approved, say:

> "PRD approved: `<slug>`. Handing back to /valk for issue breakdown."

Do NOT run `to-issues` yourself and do NOT set the `issues` stage — the orchestrator owns that transition and will verify the approval happened in this conversation before it proceeds.
