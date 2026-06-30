# valk

The Valkyrie workflow orchestrator. Routes every coding request through a gated pipeline — design, PRD, issues, TDD — and refuses to let you skip stages. A mechanical hook blocks edits to production code until the workflow reaches the TDD stage.

## When to use

Type `/valk` or `/valkyrie`, or say "let's build X", "add a feature", "implement X", or "fix this bug" when the fix is non-trivial. Also triggers on `/v`. Use at the start of any new feature or multi-module change. For trivial one-line fixes, Valkyrie bypasses itself and says so.

## Example

```
/valk add a billing dashboard
```

## Output

Valkyrie reads the current stage from disk, picks a lane (Trivial / Lite / Full), and announces where it's starting in one sentence. The statusline updates at each transition: `▶ DESIGN`, `▶ PRD`, `▶ REVIEW-PRD`, `▶ ISSUES`, `▶ TDD`. Artifacts accumulate: `CONTEXT.md`, `docs/prd/<slug>.md`, `issues/<epic>-NN-<slug>.md`. When all issues are done the stage clears.
