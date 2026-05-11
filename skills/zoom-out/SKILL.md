---
name: zoom-out
description: Step back from low-level code to give a higher-level map of how a module fits into the bigger picture — its callers, its collaborators, its place in the system. Use when you're unfamiliar with a section of code, when you've been zoomed in too long, or when the user types /zoom-out.
---

# Zoom Out

Adapted from mattpocock/skills.

## On entry

```bash
python3 ~/.claude/valkyrie/stage.py set zoom
```

(Stage will be restored to whatever it was before, or to `idle`, when this completes.)

## What to do

You don't know this area of code well — or you've been zoomed in too long and lost the bigger picture. Go up a layer of abstraction. Use the Agent tool with `subagent_type=Explore` to walk the codebase, then produce:

1. **A map of the relevant modules** — what they do in one line each, using the project's domain vocabulary (read `CONTEXT.md` if present).
2. **Who calls this module** — every caller, with one line on what they pass and why.
3. **What this module calls** — every collaborator, with one line on the contract.
4. **The seams** — places where behavior could be altered without editing in place. Note which are real (multiple adapters) vs. hypothetical (single adapter).
5. **Where this fits in the system** — one paragraph framing what the user is actually trying to do at this layer, in plain English.

Do NOT propose changes. Do NOT recommend refactors. The point is to *re-orient*, not to act.

End with one short question:
> "Where do you want to focus next?"

## On exit

```bash
python3 ~/.claude/valkyrie/stage.py clear
```

(Or restore to the previous stage if the orchestrator passed it in.)
