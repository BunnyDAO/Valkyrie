---
name: to-domain
version: 0.1.0
description: Author or update a repo's DOMAIN.md — its purpose, system integration map, installer/assembly relationship, legacy constraints, and pain points. Use when the user types /to-domain, asks to capture the domain or bounds of a repo, or when a grilling session needs explicit domain bounds. Distinct from CONTEXT.md, which is the glossary.
---

# To Domain

Authors a repo's **`DOMAIN.md`** — the "where am I, what are the bounds" document. It is the
backbone of the Intent Lock: with it, every later decision can be checked against the repo's
real frame of reference instead of guessed.

**This is an authoring helper, not a workflow stage.** Do **not** change the stage marker —
it can run at any point (often before or during DESIGN). `DOMAIN.md` is plain markdown the
TDD gate always allows.

`DOMAIN.md` is **not** the glossary. Keep them separate:
- `CONTEXT.md` = terms & relationships (the glossary). Leave it to `/grill-with-docs`.
- `DOMAIN.md` = bounds, integrations, installer relationship, constraints, pain points.
- Decisions live in `docs/adr/` — `DOMAIN.md` *links* to them, it does not restate them.

## What to do

1. **Identify the repo** — the current working directory's repo. Name it.
2. **Pre-fill only what you can verify from the code.** Dependency manifests, build files,
   CI config, and the directory layout are fair game — read them and propose values. **Do
   not infer the rest.** Purpose, installer relationship, legacy gotchas, and pain points
   are human knowledge: ask, one section at a time, with a recommended answer where you
   genuinely derived one from the code.
3. **Fill each section** of [DOMAIN-FORMAT.md](./DOMAIN-FORMAT.md):
   - Repository Purpose
   - System Integration Map (depends on / depended on by / key contracts & data flows)
   - Installer / Assembly Relationship
   - Legacy Constraints & Gotchas
   - Pain Points
   - Pointers (CONTEXT.md, docs/adr/, PRODUCT-MAP.md)
4. **Write it** to `<repo-root>/DOMAIN.md`. If one exists, update in place — preserve human
   edits, only changing what the user confirms.
5. **Confirm bounds back** in one or two sentences: "This domain owns *X*, depends on *Y*,
   is assembled into the product via *Z*." The user confirms or sharpens.

## Stamping many repos (optional — sc-compose)

For a product with many repos, the same shape can be rendered deterministically with
[sc-compose](https://github.com/BunnyDAO/sc-compose) instead of interviewing each time. The
template [`domain.md.j2`](./domain.md.j2) declares the required fields up front, so a render
**fails loudly** if any are missing:

```bash
sc-compose render skills/to-domain/domain.md.j2 --var-file my-repo.yaml > DOMAIN.md
```

The rendered output is identical in shape to what this skill writes — plain markdown that
Valkyrie reads. sc-compose is an **authoring** convenience only; Valkyrie never needs it at
runtime.

A zero-tool starting point is also available at [`domain.template.md`](./domain.template.md)
— copy it to `DOMAIN.md` and fill the blanks by hand.
