---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use when user wants to stress-test a plan, get grilled on their design, says "grill me", or when /valk routes here at the DESIGN stage.
---

# Grill Me

Adapted from mattpocock/skills with Valkyrie stage tracking.

## On entry

Mark the stage so the statusline shows DESIGN:

```bash
python3 ~/.claude/valkyrie/stage.py set design
```

## What to do

Interview the user relentlessly about every aspect of this plan until you reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one at a time. For each question, provide your **recommended answer** so the user can react rather than ideate from scratch.

**Ask questions one at a time.** Wait for the user's answer before moving on. A grilling session is a back-and-forth, not an interrogation list.

**If a question can be answered by exploring the codebase, explore the codebase instead.** Don't waste user attention on things you can verify yourself.

## What to grill on

- **Scope** — what's in, what's out, what's "nice-to-have"
- **Users & actors** — who triggers this flow, who consumes the output
- **Failure modes** — what happens when the network drops, the input is empty, two users race
- **Data model** — what entities exist, what their lifecycles are, where state lives
- **Boundaries** — which existing modules this touches, which new ones it requires
- **Migration / rollout** — does anything need to be backfilled, feature-flagged, or shimmed for backwards-compat
- **Observability** — how will the user know it's working, how will they debug it when it isn't

## When to stop

Stop when:
- Every branch you can think of has been resolved or explicitly deferred
- The user has answered a question with "I don't care, you decide" twice in a row (decision fatigue — they're done designing)
- The user explicitly says "ok, that's enough, write it up"

When you stop, summarize the resolved decisions in 5–10 bullets, then say:
> "Ready to turn this into a PRD?"

If they say yes, the Valkyrie orchestrator will route to `to-prd` next. Do NOT run `to-prd` yourself — let the orchestrator handle the transition so the stage marker stays consistent.
