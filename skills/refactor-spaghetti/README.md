# refactor-spaghetti

Surfaces architectural friction in a codebase and proposes deepening opportunities — refactors that turn shallow modules into deep ones, improving testability and locality. Exploration first, then a grilling conversation on whichever candidate the user picks.

## When to use

Type `/refactor-spaghetti` or say "clean up the architecture", "find refactoring opportunities", "this code is a mess", "improve the module structure." Also invokable from inside a Valkyrie flow as an escape hatch. The previous stage is restored when done.

## Example

```
/refactor-spaghetti the checkout flow
```

## Output

A numbered list of refactoring candidates, each with the files involved, the architectural problem, the proposed solution in plain English, and the benefits in terms of leverage and locality. No interface proposals yet — the user picks a candidate first. The skill then drops into a grilling conversation, updating `CONTEXT.md` inline as terms are named and offering ADRs when a load-bearing decision is made. Statusline shows `▶ refactor` for the duration.
