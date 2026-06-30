# grill-with-docs

Stress-tests a plan through a structured interview that locks intent, challenges domain assumptions, sharpens terminology, and cross-references the codebase. Updates `CONTEXT.md` and writes ADRs inline as decisions land. `/valk` routes here automatically at the DESIGN stage.

## When to use

Type `/grill-with-docs` or say "grill me on this", "stress-test my plan", or "challenge this design." Also triggers when `/valk` enters the DESIGN stage. Use whenever a plan is fuzzy, the scope is unclear, or you want to catch domain mismatches before writing any code.

## Example

```
/grill-with-docs I want to add real-time notifications via WebSockets
```

## Output

A back-and-forth interview, one question at a time. As decisions land, `CONTEXT.md` is updated in place and ADRs are written to `docs/adr/` where warranted. The session ends with a terse decision summary (under 200 words, decisions only) and a prompt to move to the PRD stage. Statusline shows `▶ DESIGN` for the duration.
