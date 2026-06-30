# to-domain

Authors or updates a repo's `DOMAIN.md` — its purpose, system integration map, installer/assembly relationship, legacy constraints, and pain points. Distinct from `CONTEXT.md` (the glossary): domain is about bounds and integrations, not terminology.

## When to use

Type `/to-domain` or say "capture the domain", "document this repo's bounds", "write the domain file." Run it once when a repo is new to the workflow, or when the grilling session's Intent Lock surfaces an unclear domain boundary. Not a workflow stage — it can run at any point without affecting the stage marker.

## Example

```
/to-domain
```

## Output

A `DOMAIN.md` file at the repo root covering: Repository Purpose, System Integration Map, Installer/Assembly Relationship, Legacy Constraints, Pain Points, and Pointers to related docs. The skill pre-fills only what it can verify from manifests and build files; everything else is asked one section at a time. Ends with a one-sentence bounds confirmation for the user to approve or sharpen.
