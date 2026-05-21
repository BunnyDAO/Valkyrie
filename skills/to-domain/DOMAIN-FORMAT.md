# DOMAIN.md Format

`DOMAIN.md` lives at a repo's root. It records the repo's **bounds** — what it owns, what it
touches, how it is assembled into the larger product, and what a change must respect. It is
read by `/grill-with-docs` (to ground challenges and flag drift) and `/to-prd` (to keep the
PRD inside the stated bounds). All optional: no `DOMAIN.md`, no change in behavior.

It is **not** the glossary (`CONTEXT.md`) and **not** a decision log (`docs/adr/`). Link to
those; don't restate them.

## Structure

```md
# Domain: {Repository Name}

## Repository Purpose
One clear paragraph: exactly what this repository owns in the overall product, and what it
deliberately does not.

## System Integration Map
- **Depends on:** repos/services this one needs (and what for)
- **Depended on by:** repos/services that consume this one (and what they rely on)
- **Key contracts & data flows:** the APIs, events, schemas, or shared types that cross the
  boundary — the things that break other people if you change them

## Installer / Assembly Relationship
How this repo is pulled into the final product: submodule / package / copy / build step;
build order; versioning rules; and the constraints that creates (e.g. "must stay ABI-compatible
with X", "ships before Y in the installer").

## Legacy Constraints & Gotchas
Old patterns, deprecated libs, performance rules, things that cannot be easily changed and
will bite a newcomer.

## Pain Points
The fragile areas any change must respect — where the bodies are buried.

## Pointers
- Glossary: [CONTEXT.md](./CONTEXT.md)
- Decisions: [docs/adr/](./docs/adr/)
- Cross-repo map: [PRODUCT-MAP.md](../PRODUCT-MAP.md)   ← only for multi-repo products
```

## Rules

- **Bounds, not implementation.** Describe what the repo owns and touches, not how its code
  works line by line. If it would go stale on the next refactor, it doesn't belong here.
- **Name the contracts.** The integration map's value is naming exactly what breaks others.
  Be specific: endpoint names, event names, shared type names — not "some APIs".
- **Don't duplicate ADRs.** When a bound exists *because* of a decision, link the ADR.
- **Don't duplicate the glossary.** Terms go in `CONTEXT.md`; link it.
- **Verifiable facts may be read from the code** (dependencies, build order). Judgment —
  purpose, constraints, pain points — comes from a human. Never invent these.
