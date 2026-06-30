# to-issues

Breaks a PRD into independently-grabbable vertical slices saved as numbered markdown files under `issues/`. Each slice cuts through all integration layers and carries dependency metadata so parallel batches can be identified and run concurrently in separate worktrees.

## When to use

Type `/to-issues` or say "break this into issues", "create tickets", "slice the PRD." Also triggers when `/valk` reaches the ISSUES stage after PRD approval. Requires an approved PRD from the current conversation.

## Example

```
/to-issues
```

## Output

Issue files at `issues/<epic>-NN-<slug>.md`, each with frontmatter (`id`, `type: AFK|HITL`, `status`, `blocked_by`), a description, and acceptance criteria. In chat: one line per issue showing title, type, blockers, and user-story coverage, plus a parallel plan line showing which batches can run concurrently in their own `valk-worktree`. An interactive breakdown review runs before files are written. Statusline shows `▶ ISSUES`.
