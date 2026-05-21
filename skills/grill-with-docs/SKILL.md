---
name: grill-with-docs
description: Grilling session that challenges your plan against the existing domain model, sharpens terminology, and updates documentation (CONTEXT.md, ADRs) inline as decisions crystallise. Use when user wants to stress-test a plan, get grilled on their design, says "grill me", or when /valk routes here at the DESIGN stage.
---

# Grill With Docs

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

## Domain awareness

During codebase exploration, also look for existing documentation:

### File structure

Most repos have a single context:

```
/
├── CONTEXT.md
├── docs/
│   └── adr/
│       ├── 0001-event-sourced-orders.md
│       └── 0002-postgres-for-write-model.md
└── src/
```

If a `CONTEXT-MAP.md` exists at the root, the repo has multiple contexts. The map points to where each one lives:

```
/
├── CONTEXT-MAP.md
├── docs/
│   └── adr/                          ← system-wide decisions
├── src/
│   ├── ordering/
│   │   ├── CONTEXT.md
│   │   └── docs/adr/                 ← context-specific decisions
│   └── billing/
│       ├── CONTEXT.md
│       └── docs/adr/
```

Create files lazily — only when you have something to write. If no `CONTEXT.md` exists, create one when the first term is resolved. If no `docs/adr/` exists, create it when the first ADR is needed.

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in `CONTEXT.md`, call it out immediately. "Your glossary defines 'cancellation' as X, but you seem to mean Y — which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account' — do you mean the Customer or the User? Those are different things."

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. If you find a contradiction, surface it: "Your code cancels entire Orders, but you just said partial cancellation is possible — which is right?"

### Update CONTEXT.md inline

When a term is resolved, update `CONTEXT.md` right there. Don't batch these up — capture them as they happen. Use the format in [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md).

`CONTEXT.md` should be totally devoid of implementation details. Do not treat `CONTEXT.md` as a spec, a scratch pad, or a repository for implementation decisions. It is a glossary and nothing else.

### Offer ADRs sparingly

Only offer to create an ADR when all three are true:

1. **Hard to reverse** — the cost of changing your mind later is meaningful
2. **Surprising without context** — a future reader will wonder "why did they do it this way?"
3. **The result of a real trade-off** — there were genuine alternatives and you picked one for specific reasons

If any of the three is missing, skip the ADR. Use the format in [ADR-FORMAT.md](./ADR-FORMAT.md).

## What to grill on

Beyond the domain/language work above, cover the standard design surface:

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

When you stop, summarize the session in chat — terse, decision-only.

- **Decisions** (5–10 bullets, each ≤ one line): `<decision> — <one-line why>`. Skip exploration; only resolved choices.
- **Docs updated** (paths only): `CONTEXT.md` if you wrote to it, plus any `docs/adr/*.md` files you created.

Total: under 200 words. Do NOT recap the conversation, restate the user's questions, or narrate the grilling process — the user lived it; they don't need a transcript.

Then say:

> "Ready to turn this into a PRD?"

If they say yes, the Valkyrie orchestrator will route to `to-prd` next. Do NOT run `to-prd` yourself — let the orchestrator handle the transition so the stage marker stays consistent.
