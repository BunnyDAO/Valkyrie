---
id: 0028
title: valk-land auto-resolves the repo's default branch
type: AFK
status: done
blocked_by: []
parent: docs/prd/valk-land-default-branch.md
---

## What to build

`valk-land <name>` works on a repo whose default branch is not named `main`.

End-to-end behavior: `valk-land` determines the consumer repo's default
branch from `git -C "$root" symbolic-ref --quiet refs/remotes/origin/HEAD`
(strip the `refs/remotes/origin/` prefix) into a single resolved `$base`. That
one `$base` is used for every branch operation it previously hardcoded to
`main`: the rebase target becomes `origin/$base`, the unwind anchor becomes
`pre_$base` (`rev-parse $base`), the local fast-forward is `checkout $base` +
`merge --ff-only $branch`, the push is `push origin $base`, and the
user-facing messages interpolate `$base`. Before the rebase, `origin/$base`
must exist; if it does not, abort and preserve state with a hint to run
`git remote set-head origin -a` (the `--base` escape hatch is issue 0029).

Every ADR-0002 safety property is preserved byte-for-byte: delegate-or-local,
never force-push, rebase-linear, green-gate-before-finalize,
unwind-on-rejected-push, run-from-main-checkout guard. Governing decision:
`docs/adr/0003-valk-land-resolves-default-branch.md` — do not restate it.

## Acceptance criteria

- [ ] A `master`-default fixture (mirror `mkfixture` in
      `test/test-valk-land.sh`, seed `git branch -M master`; `git clone`
      propagates `origin/HEAD → origin/master`) lands: history linear, local
      `master` fast-forwarded to `origin/master`, feature + concurrent commits
      both present, exit 0
- [ ] The existing `main`-default cases (0019/0020) pass **verbatim,
      unchanged** (backward-compat pin — on a `main` repo `$base` resolves to
      `main`, behavior byte-identical)
- [ ] No literal `main`/`origin/main` branch operation remains in
      `scripts/valk-land` (all go through the resolved `$base`)
- [ ] `origin/$base` missing before rebase → aborts, origin untouched,
      branch + worktree preserved, stderr names `git remote set-head origin -a`
- [ ] `test/run-tests.sh` (whole Valkyrie suite) green

## Blocked by

- None — can start immediately
