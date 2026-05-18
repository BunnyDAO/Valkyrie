# `.valk-worktree-setup` — per-project worktree bootstrap hook

An **optional, opt-in** executable a consumer repo may drop at its root. When
present, `valk-worktree <name>` runs it once, right after creating the new
linked worktree, to bring that fresh checkout to a working state (install
deps, pick a free port, seed `.env`, …).

**Without this file, `valk-worktree` still fully works** — it does the pure
git worktree + `valk/<name>` branch, which is the entire concurrency cure.
The hook is convenience only, the same opt-in precedent as
[`.claude/valk-config.md`](./valk-config-format.md): Valkyrie core stays
language-agnostic; repo-specific setup lives in the repo.

## Location

`<repo-root>/.valk-worktree-setup`

One file per repo, at the **main checkout's** root (where `valk-worktree`
reads it from — `git rev-parse --show-toplevel`). Not searched up the tree.
Not read from `$HOME`.

## Contract

| Aspect | Guarantee |
|---|---|
| **Runs when** | Only on **create**, only after `git worktree add` succeeded. Never on `--remove`, never on the idempotent no-op (worktree already existed). |
| **Runs iff** | The file exists **and is executable** (`chmod +x`). A non-executable file is ignored — it does not run and is not an error. This is what keeps the helper standalone. |
| **Working directory** | The **new worktree's root** (the fresh `../<repo>-<name>` checkout). Relative paths in the hook resolve there, so `npm ci`, `cp .env`, etc. land in the isolated tree — not the main checkout. |
| **Arguments** | None. The hook infers everything from its cwd (the new worktree) and the environment it inherits. |
| **Environment** | Inherits the caller's environment unchanged. No special vars are injected; the contract is intentionally minimal. |
| **Exit code** | A non-zero exit **warns** (`valk-worktree: .valk-worktree-setup exited non-zero (worktree kept)`) but **does not unwind** the worktree. The worktree already exists and is usable; partial setup is the user's to finish, not a reason to destroy their isolated tree. |
| **stdout/stderr** | Passed through to the user's terminal. Keep it quiet on success; be loud on failure. |
| **Idempotency** | Not required by the contract (it runs once per fresh worktree), but writing it idempotently is good practice in case a user re-runs it by hand. |

## Language-agnostic by design

The sample shipped at [`docs/samples/valk-worktree-setup`](./samples/valk-worktree-setup)
is a `bash` skeleton with **commented** Node and Python blocks — pick one,
delete the rest, or write your own in any language (the file just has to be
executable; `#!/usr/bin/env bash`, `#!/usr/bin/env python3`, anything). Valkyrie
never assumes a stack.

## Quick start

```bash
cp "$(dirname "$(command -v valk-worktree)")"/../*/docs/samples/valk-worktree-setup \
   .valk-worktree-setup        # or just copy it from the Valkyrie repo
chmod +x .valk-worktree-setup  # the +x is what arms it
$EDITOR .valk-worktree-setup   # keep the block for your stack, delete the rest
git add .valk-worktree-setup && git commit -m "chore: worktree bootstrap hook"
```

Thereafter every `valk-worktree <name>` in that repo lands a ready-to-work
isolated checkout.

## Relationship to `valk-worktree --remove`

`--remove` does **not** run any teardown hook. It force-removes the worktree
and drops the `valk/<name>` branch only if merged. If your setup creates
external resources (a database, a bound port held by a daemon), tear those
down yourself before `--remove`, or make them ephemeral to the worktree dir
so removing the directory is sufficient. A dedicated teardown hook is
deliberately out of scope for v1.

## Versioning

This contract is at `v0`. Breaking changes (e.g. injected env vars, a
teardown counterpart) will be additive or gated; until then the guarantees
above are stable.
