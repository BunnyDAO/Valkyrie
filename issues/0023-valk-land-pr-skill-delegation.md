---
id: 0023
title: valk-land pr_skill delegation path
type: AFK
status: open
blocked_by: [0019]
parent: docs/prd/valk-land.md
---

## What to build

The delegate half of the delegate-or-local split (the PRD's load-bearing,
user-approved decision). When the repo's `.claude/valk-config.md` declares a
`pr_skill` (read via `read-valk-config.sh`), `valk-land` does **not** do the
local rebase/ff/push — it hands the land to that skill (which already pushes
the branch, opens the PR, polls CI, returns `ready_for_review`). `valk-land`
adds no host logic of its own and does **not** double-push.

Mirror `tdd`'s existing contract for the failure mode: `pr_skill` set but
the named skill not installed → STOP with a clear, actionable error (do not
silently fall back to a local land).

## Acceptance criteria

- [ ] With a `pr_skill` configured (injected config + a stub skill/marker),
      `valk-land` delegates the land: no local rebase/ff of main, no push by
      `valk-land` itself, no double-push
- [ ] `pr_skill` set but not installed → `valk-land` STOPs with a clear
      error and changes nothing (no local land fallback)
- [ ] With no `pr_skill`, behavior is the local path (unchanged from
      0019–0022) — the split is driven solely by the opt-in config
- [ ] Bash test in `test/` covers delegated / not-installed / absent
      (config injected via temp `.claude/valk-config.md`); suite stays green

## Blocked by

- 0019
