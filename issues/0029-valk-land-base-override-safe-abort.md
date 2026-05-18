---
id: 0029
title: valk-land --base override + safe abort when the base is unresolvable
type: AFK
status: done
blocked_by: [0028]
parent: docs/prd/valk-land-default-branch.md
---

## What to build

`valk-land` never guesses the base, and a user can always state it explicitly.

End-to-end behavior, building on the resolved-`$base` plumbing from 0028:

- A new `--base <name>` flag joins the existing options
  (`--no-push`/`--force`/`--clean` + positional `<name>`) in the arg parser.
  An explicit `--base` **always wins** over auto-resolution and is usable in
  any repo (covers standalone / no-remote / unusual-remote, a local-first
  case ADR-0002 explicitly supports).
- When the base cannot be resolved (`origin/HEAD` unset, or no origin remote)
  **and** no `--base` was given, `valk-land` aborts and preserves state. The
  hint is **extended** from 0028 to name *both* remedies: run
  `git remote set-head origin -a`, **or** re-run with `--base <name>`.
- Probing local branches is never done — an unresolved base is a stop, not a
  guess (ADR-0001/0002 no-silent-corruption guarantee; ADR-0003).

Governing decision: `docs/adr/0003-valk-land-resolves-default-branch.md` — do
not restate it.

## Acceptance criteria

- [ ] Fixture with `origin/HEAD` removed (`git remote set-head origin -d`) and
      **no** `--base`: `valk-land` exits non-zero, origin ref untouched,
      `valk/<name>` branch + its worktree preserved, stderr contains the hint
      naming **both** `git remote set-head origin -a` and `--base <name>`
- [ ] Same fixture **with** `--base <name>`: lands successfully (linear, ff,
      pushed)
- [ ] `--base <name>` overrides even when `origin/HEAD` *is* resolvable
      (explicit wins)
- [ ] Unknown-option / missing `--base` argument handled consistently with
      the existing parser's error behavior
- [ ] 0028's `master`-default and the `main`-default 0019/0020 cases still
      pass unchanged
- [ ] `test/run-tests.sh` (whole Valkyrie suite) green

## Blocked by

- 0028
