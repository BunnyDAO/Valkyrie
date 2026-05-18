---
id: 0024
title: valk-land cleanup coupling — opt-in --clean
type: AFK
status: open
blocked_by: [0019]
parent: docs/prd/valk-land.md
---

## What to build

Couple `valk-land` to `valk-worktree --remove` ergonomically but never by
surprise. On a successful land:

- **Default:** remove nothing. Print the exact `valk-worktree --remove
  <name>` next-step (the branch is now merged, so that command's
  merged-only branch drop is safe). This lets the AFK loop reuse the
  deps-installed checkout for the next slice.
- **`--clean`:** after a green land, also tear down the worktree + drop the
  (now-merged) branch in one go — but **refuse if `cwd` is inside the target
  worktree**, instructing the user to `cd` out first (so it can't pull the
  rug out from under the caller).

`valk-land` and `valk-worktree` stay independently understandable and
composable.

## Acceptance criteria

- [ ] Default green land removes nothing and prints the exact
      `valk-worktree --remove <name>` hint
- [ ] `--clean` on a green land removes the worktree and drops the merged
      `valk/<name>` branch (reusing the existing `valk-worktree --remove`
      behavior, not a reimplementation)
- [ ] `--clean` invoked with `cwd` inside the target worktree refuses with a
      clear "cd out first" message and removes nothing
- [ ] `--clean` does nothing destructive if the land itself did not succeed
- [ ] Bash test in `test/` covers default-hint / `--clean` / refuse-from-
      inside / no-op-on-failed-land; full suite stays green

## Blocked by

- 0019
