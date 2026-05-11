---
id: 0008
title: Dirty-tree gate with non-git skip
type: AFK
status: done
blocked_by: [0007]
parent: docs/prd/ralph-afk-enforcement-guardrails.md
---

## What to build

Add `gate_working_tree_clean` to the preflight orchestrator from 0007. End-to-end:

- The gate calls `git diff --quiet` AND `git diff --cached --quiet`. Exit codes:
  - `0` (both): tree is clean. Pass.
  - `1` (either): there are changes. Fail with message: `uncommitted changes in working tree (commit/stash, or pass --allow-dirty)`.
  - `128` (either): not a git repo. Skip the check; print a one-line warning before the startup banner: `ralph-afk: warning — git: not a repo, dirty-tree check skipped`.
- New flag: `--allow-dirty`. When passed, the gate skips the check entirely (no git diff invocation) and prints: `ralph-afk: warning — dirty-tree check skipped (--allow-dirty)`.
- Distinguishing `1` vs `128` is done by capturing the exit code (don't conflate "dirty" with "no git").

## Acceptance criteria

- [x] In a git workdir with no changes, the gate passes silently and the loop runs.
- [x] In a git workdir with an uncommitted modified file, the gate blocks with the documented failure message.
- [x] In a git workdir with staged but uncommitted changes, the gate blocks with the documented failure message.
- [x] In a non-git workdir, the gate is skipped and the warning `git: not a repo, dirty-tree check skipped` appears before the startup banner.
- [x] `--allow-dirty` causes the gate to skip even when the tree IS dirty; the override warning appears.
- [x] Multi-gate failure works: a workdir with no PRD AND a dirty tree produces a punch list with both entries.
- [x] New tests in `test/test-guardrails.sh` cover the above (including a `git init` setup and modified-file fixture).

## Blocked by

- 0007 (orchestrator + GATE_FAILURES infrastructure)
