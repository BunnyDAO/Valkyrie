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

## After saving

Tell the user the PRD path in one line:
> "PRD saved to `docs/prd/<slug>.md`. Ready to break it into issues?"

Do NOT run `to-issues` yourself — the orchestrator handles the transition.
