# tdd

Implements each issue using strict red-green-refactor vertical slices — one test, one implementation, repeat. Tests verify behavior through public interfaces only; implementation details are never the test target. `/valk` routes here at the TDD stage after issues are approved.

## When to use

Type `/tdd` or say "implement this with TDD", "do the red-green loop", or "start building." Also triggers when `/valk` reaches the TDD stage. Requires at least one issue defined (in `issues/`, in the conversation, or on a tracker).

## Example

```
/tdd
```

## Output

Per issue: a tracer bullet test that fails for the right reason, minimal code to make it pass, then a refactor pass. Each completed slice gets a concise git commit scoped to its pathspecs. If the issue has a `## Manual test checklist`, the skill pauses and asks for confirmation before flipping `status: done`. Statusline shows `▶ TDD`. If `pr_skill` is configured in `valk-config.md`, a PR is opened and its URL written back to the issue frontmatter.
