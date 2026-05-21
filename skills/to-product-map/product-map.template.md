# Product Map: <Product Name>

## Overview
<One paragraph: what the assembled product is, and how the repos combine into it.>

## Member Repos
- **<repo-a>** — <what it owns, one line> — [DOMAIN.md](<path/to/repo-a/DOMAIN.md>)
- **<repo-b>** — <what it owns, one line> — [DOMAIN.md](<path/to/repo-b/DOMAIN.md>)
<!-- add one line per member repo — no fixed count -->

## Build / Assembly Order
<How the installer assembles the members: order, packaging, versioning rules, and any
"must ship before/after" constraints.>

## Cross-Repo Contracts
- **<contract name>** — <producer repo> → <consumer repo(s)>: <what it is; what breaks
  downstream if it changes>
<!-- one per contract that crosses a repo boundary -->
