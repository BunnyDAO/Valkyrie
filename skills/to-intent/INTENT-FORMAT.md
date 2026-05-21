# Intent brief format

A per-task intent brief lives at `docs/intent/<slug>.md`. It records the **why** of one
change before any design work — the premise the grilling and the PRD are built on. Optional;
when absent, intent is locked inline at the top of DESIGN instead. Every field is human
knowledge: never inferred from code.

## Structure

```md
# Intent: {Short Title}

## Outcome
What is true after this ships, from the user's perspective.

## Why
The business / UI / technical rationale; why it matters now.

## Domain
Which repo / subsystem / bounded context this lives in.
Links: [DOMAIN.md](../../DOMAIN.md) · [PRODUCT-MAP.md](../../PRODUCT-MAP.md)  (if present)

## In Scope
What this change covers.

## Out of Scope
What it deliberately does NOT cover. (The most valuable section — be explicit.)

## Success Criteria
How we will observe that it worked.

## Trade-offs
What is being accepted or given up, and why that's acceptable.
```

## Rules

- **No inference.** Outcome, why, scope, criteria, and trade-offs come from the human. If a
  field is unknown, the brief isn't ready — ask, don't fill.
- **Out of scope is mandatory.** An empty "Out of Scope" is a smell; it's what keeps the
  later stages from wandering.
- **Success criteria must be observable** — something you could check, not a vibe.
- **One brief per task.** Slug-named like PRDs (`docs/intent/billing-dashboard.md`), so a
  task's why sits alongside its PRD (`docs/prd/billing-dashboard.md`).
- **Keep it short.** This is the why, not the how. The how is the PRD's job.
