# Domain: <Repository Name>

## Repository Purpose
<One clear paragraph: exactly what this repository owns in the overall product, and what it
deliberately does not.>

## System Integration Map
- **Depends on:** <repos/services this one needs — and what for>
- **Depended on by:** <repos/services that consume this one — and what they rely on>
- **Key contracts & data flows:** <the APIs, events, schemas, or shared types that cross the
  boundary; the things that break other people if you change them>

## Installer / Assembly Relationship
<How this repo is pulled into the final product: submodule / package / copy / build step;
build order; versioning rules; and the constraints that creates.>

## Legacy Constraints & Gotchas
<Old patterns, deprecated libs, performance rules, things that cannot be easily changed.>

## Pain Points
<The fragile areas any change must respect.>

## Pointers
- Glossary: [CONTEXT.md](./CONTEXT.md)
- Decisions: [docs/adr/](./docs/adr/)
- Cross-repo map: [PRODUCT-MAP.md](../PRODUCT-MAP.md)   <!-- only for multi-repo products -->
