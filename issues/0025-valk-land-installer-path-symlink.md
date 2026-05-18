---
id: 0025
title: install.sh PATH-registers valk-land like afk/valk-worktree
type: AFK
status: open
blocked_by: [0019]
parent: docs/prd/valk-land.md
---

## What to build

Register `valk-land` on `PATH` so it is a first-class command. Extend
`install.sh §5` to PATH-symlink `scripts/valk-land` exactly the way it
already does `scripts/afk` and `scripts/valk-worktree` (global install;
back up a non-symlink, chmod +x, symlink into `~/.local/bin`). The
project-scoped `--target` install path and its isolation guarantees are
unchanged.

## Acceptance criteria

- [ ] A global `install.sh` PATH-symlinks `valk-land` →
      `scripts/valk-land`, with the same backup/`+x` handling as
      `afk`/`valk-worktree`
- [ ] Verified behaviorally via a **sandboxed `HOME`** install (mirroring
      the `valk-worktree` installer-test pattern) so the dev machine is
      never mutated; `afk` + `valk-worktree` stay registered (no regression)
- [ ] `test-target-install.sh` stays green (scoped install unaffected)
- [ ] Full suite stays green

## Blocked by

- 0019 (the `scripts/valk-land` script must exist to be symlinked)
