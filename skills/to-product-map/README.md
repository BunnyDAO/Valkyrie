# to-product-map

Authors or updates an umbrella `PRODUCT-MAP.md` for products assembled from multiple repos — the member repos, their build/assembly order, and the cross-repo contracts that span them. Single-repo projects do not need this.

## When to use

Type `/to-product-map` or say "document the product map", "write the cross-repo contracts", "map out all the repos." Use when a change spans more than one repo and you need the contracts written down, or when setting up the workflow for a multi-repo product for the first time. Not a workflow stage — it can run at any point without affecting the stage marker.

## Example

```
/to-product-map
```

## Output

A `PRODUCT-MAP.md` at the product's umbrella root (the installer or parent directory). Covers: member repo list with one-line purpose each, build/assembly order, and cross-repo contracts named by producer, consumer, and what breaks if the contract changes. The skill reads installer manifests and workspace files where available; anything not derivable from files is asked explicitly. Member repos can point up to it from their `DOMAIN.md` pointers section.
