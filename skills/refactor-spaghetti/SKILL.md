---
name: refactor-spaghetti
description: Find architectural friction in a codebase and propose deepening opportunities — refactors that turn shallow modules into deep ones, with leverage and locality. Use when user wants to improve architecture, find refactoring opportunities, consolidate tightly-coupled code, clean up spaghetti, or types /refactor-spaghetti.
---

# Refactor Spaghetti

Adapted from mattpocock/skills `improve-codebase-architecture`. Surface architectural friction and propose **deepening opportunities** — refactors that turn shallow modules into deep ones. The aim is testability and AI-navigability.

## On entry

```bash
python3 "$(for p in .claude/valkyrie/stage.py "$HOME/.claude/valkyrie/stage.py" "$HOME/.claude/valk/stage.py"; do [ -f "$p" ] && echo "$p" && break; done)" set refactor
```

## Vocabulary (use these terms exactly)

- **Module** — anything with an interface and an implementation (function, class, package, slice).
- **Interface** — everything a caller must know to use the module: types, invariants, error modes, ordering, config. Not just the type signature.
- **Implementation** — the code inside.
- **Depth** — leverage at the interface: a lot of behavior behind a small interface. **Deep** = high leverage. **Shallow** = interface nearly as complex as the implementation.
- **Seam** — where an interface lives; a place behavior can be altered without editing in place. (Use this, not "boundary.")
- **Adapter** — a concrete thing satisfying an interface at a seam.
- **Leverage** — what callers get from depth.
- **Locality** — what maintainers get from depth: change, bugs, knowledge concentrated in one place.

Three load-bearing principles:

- **Deletion test**: imagine deleting the module. If complexity vanishes, it was a pass-through. If complexity reappears across N callers, it was earning its keep.
- **The interface is the test surface.**
- **One adapter = hypothetical seam. Two adapters = real seam.**

## Process

### 1. Explore

Read `CONTEXT.md` and `docs/adr/` first if they exist. Then use the Agent tool with `subagent_type=Explore` to walk the codebase. Don't follow rigid heuristics — explore organically and note where you experience friction:

- Where does understanding one concept require bouncing between many small modules?
- Where are modules **shallow** — interface nearly as complex as the implementation?
- Where have pure functions been extracted just for testability, but the real bugs hide in how they're called (no **locality**)?
- Where do tightly-coupled modules leak across their seams?
- Which parts of the codebase are untested, or hard to test through their current interface?

Apply the **deletion test** to anything you suspect is shallow.

### 2. Present candidates

Numbered list. For each candidate:

- **Files** — what's involved
- **Problem** — why the current architecture causes friction
- **Solution** — plain English description of what would change
- **Benefits** — explained in terms of locality, leverage, and how tests would improve

**Use CONTEXT.md vocabulary for the domain, and the architecture vocabulary above for the structure.** If `CONTEXT.md` defines "Order," talk about "the Order intake module" — not "the FooBarHandler," not "the Order service."

**ADR conflicts**: if a candidate contradicts an existing ADR, only surface it when the friction is real. Mark it: *"contradicts ADR-0007 — but worth reopening because…"*

Do NOT propose interfaces yet. Ask: "Which would you like to explore?"

### 3. Grilling loop

Once the user picks a candidate, drop into a grilling conversation. Walk the design tree — constraints, dependencies, the shape of the deepened module, what sits behind the seam, what tests survive.

Side effects happen inline as decisions crystallize:
- Naming a module after a concept not in `CONTEXT.md`? Add the term.
- Sharpening a fuzzy term during the conversation? Update `CONTEXT.md` right there.
- User rejects a candidate with a load-bearing reason? Offer an ADR.

## On exit

```bash
python3 "$(for p in .claude/valkyrie/stage.py "$HOME/.claude/valkyrie/stage.py" "$HOME/.claude/valk/stage.py"; do [ -f "$p" ] && echo "$p" && break; done)" clear
```
