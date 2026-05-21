# PRODUCT-MAP.md Format

`PRODUCT-MAP.md` lives at a multi-repo product's umbrella root. It records the **cross-repo**
view: the member repos, how they're assembled, and the contracts that span them. Read by
`/grill-with-docs` and `/to-prd` when a change spans repos. Optional; absent → no change in
behavior. Single-repo projects don't need it.

It complements per-repo `DOMAIN.md` files — it does not replace them. Each repo still owns
its own `DOMAIN.md`; this map links them and captures only what lives *between* repos.

## Structure

```md
# Product Map: {Product Name}

## Overview
One paragraph: what the assembled product is, and how the repos combine into it.

## Member Repos
- **{repo-a}** — {what it owns, one line} — [DOMAIN.md]({path/to/repo-a/DOMAIN.md})
- **{repo-b}** — {what it owns, one line} — [DOMAIN.md]({path/to/repo-b/DOMAIN.md})
- … (as many as the product has — no fixed count)

## Build / Assembly Order
How the installer assembles the members: order, packaging (submodule / package / copy),
versioning rules, and any "must ship before / after" constraints.

## Cross-Repo Contracts
- **{contract name}** — {producer repo} → {consumer repo(s)}: {what it is; what breaks
  downstream if it changes}
- … (one per contract that crosses a repo boundary)
```

## Rules

- **Generalize to any N.** List every member repo the product actually has; never hardcode
  or assume a count.
- **Contracts are the point.** The cross-repo contracts section is the highest-value part —
  it's what makes a multi-repo change safe. Name each contract concretely (endpoint, event,
  shared type), both sides, and the blast radius.
- **Link, don't restate.** Point to each repo's `DOMAIN.md` rather than duplicating its
  bounds here.
- **Verifiable facts may be read** (a member list from an installer manifest, submodules).
  Assembly order and contract semantics are human knowledge — ask, don't infer.
