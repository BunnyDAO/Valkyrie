---
name: to-product-map
version: 0.1.0
description: Author or update an umbrella PRODUCT-MAP.md for a product assembled from multiple repos — member repos, build/assembly order, and cross-repo contracts. Use when the user types /to-product-map, when a change spans repos, or when a multi-repo product needs its cross-repo bounds written down. Single-repo projects do not need this.
---

# To Product Map

Authors an umbrella **`PRODUCT-MAP.md`** for products assembled from many repos — the
cross-repo view that a single repo's `DOMAIN.md` can't give: which repos exist, the order
they're assembled in, and the contracts that span them. With it, a change that crosses repo
boundaries can be checked against real contracts instead of guessed.

**Only for multi-repo products.** A single-repo project doesn't need a `PRODUCT-MAP.md` —
its `DOMAIN.md` is enough. **Generalizes to any number of repos — never assume a fixed
count.**

**This is an authoring helper, not a workflow stage.** Do **not** change the stage marker.

## Where it lives

At the product's **umbrella root** — the installer/super-repo, or the parent directory that
holds the member repos. Member repos point up to it from their `DOMAIN.md` "Pointers"
section (`../PRODUCT-MAP.md`). Put it wherever that relative pointer resolves for your layout.

## What to do

1. **Establish the member set.** If a manifest exists (installer config, a repos list, git
   submodules, a workspace file), read it and propose the list. Otherwise **ask** — do not
   guess which repos are in scope.
2. **For each member repo:** name it, one line on what it owns, and a link to its `DOMAIN.md`
   (offer `/to-domain` for any repo that lacks one).
3. **Build / assembly order** — how the installer combines them: order, packaging,
   versioning rules. This is human knowledge; ask unless an installer manifest states it.
4. **Cross-repo contracts** — the APIs, events, and shared types that cross repo boundaries:
   name each one, its producer, its consumer(s), and what breaks if it changes. **No
   inference here** — these are exactly the things that cause silent multi-repo breakage.
5. **Write it** to `<umbrella-root>/PRODUCT-MAP.md`, following
   [PRODUCT-MAP-FORMAT.md](./PRODUCT-MAP-FORMAT.md). Update in place if it exists.

## Stamping (optional — sc-compose)

[`product-map.md.j2`](./product-map.md.j2) declares the required fields, so a render fails
loudly if any are missing:

```bash
sc-compose render skills/to-product-map/product-map.md.j2 --var-file product.yaml > PRODUCT-MAP.md
```

The output is plain markdown identical in shape to this skill's; sc-compose is an authoring
convenience only, never a runtime dependency. A zero-tool copy lives at
[`product-map.template.md`](./product-map.template.md).
