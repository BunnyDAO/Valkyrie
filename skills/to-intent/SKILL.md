---
name: to-intent
description: Author a per-task intent brief — the crystal-clear WHY, scope, success criteria, and trade-offs for one change — saved to docs/intent/<slug>.md. The agent is forbidden from filling gaps with inference; every unknown is a question. Use when the user types /to-intent, wants to pin down intent before designing, or when the DESIGN Intent Lock offers to persist it.
---

# To Intent

Authors a **per-task intent brief** — the crystal-clear *why* behind one change — and saves
it to `docs/intent/<slug>.md`. Intent is the most vital and most failure-prone input in the
whole workflow: a fuzzy why poisons the design, the PRD, every issue, and every line of code.

**This skill carries the strictest no-inference rule in Valkyrie.** The *why*, the scope,
the success criteria, and the trade-offs are **human knowledge — you cannot derive them from
the code, and you must never guess them.** Every gap is a question. The only thing you may
pre-fill is the domain pointer, and only if a `DOMAIN.md`/`PRODUCT-MAP.md` already exists.

**This is an authoring helper, not a workflow stage.** Do **not** change the stage marker. It
can run standalone (before starting `/valk`) or be offered by the DESIGN Intent Lock. The
brief is optional — when absent, intent is still locked inline at the top of DESIGN and flows
into the PRD. Writing it just makes the why durable and reviewable.

## What to do

Ask, one at a time, with no assumptions. Fill every section of
[INTENT-FORMAT.md](./INTENT-FORMAT.md):

1. **Outcome** — what is true after this ships, from the user's perspective.
2. **Why** — the business / UI / technical rationale; why it matters now.
3. **Domain** — which repo / subsystem / bounded context. Read `DOMAIN.md` /
   `PRODUCT-MAP.md` if present and link them; otherwise have the user name it.
4. **In scope** — what this change covers.
5. **Out of scope** — what it deliberately does *not*. Force this; it's the most-skipped and
   most-valuable section. "We're not touching X" prevents the agent wandering.
6. **Success criteria** — how we'll *observe* it worked.
7. **Trade-offs** — what's being accepted or given up, and why that's OK.

Then **reflect and confirm**: restate the outcome + why in one or two sentences. The user
must confirm or sharpen **in their own words**. A bare "yes" / "build X" / "you get it" is
**rejected** — respond like the PRD gate:

> "That's not a locked intent. In one sentence: what's true after this ships, and what are
> we explicitly *not* doing?"

**Write** the brief to `docs/intent/<slug>.md` (kebab-case slug from the title; create the
directory if needed).

## How it feeds the flow

- `/grill-with-docs` grills this brief against the domain — it's the premise of the design.
- `/to-prd` makes the PRD's *Problem Statement* and *Solution* match this brief's why and
  scope; divergence must be reconciled, not silently dropped.

## Stamping (optional — sc-compose)

[`intent.md.j2`](./intent.md.j2) declares the required fields, failing loudly on omission:

```bash
sc-compose render skills/to-intent/intent.md.j2 --var-file intent.yaml > docs/intent/<slug>.md
```

Output is plain markdown identical in shape to this skill's. A zero-tool copy lives at
[`intent.template.md`](./intent.template.md).
