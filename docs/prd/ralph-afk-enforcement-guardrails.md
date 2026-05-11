# ralph-afk enforcement guardrails

## Problem Statement

`ralph-afk` now has budget caps (hours, dollars, iterations) — but it has zero technical safeguards against the most common foot-guns of unattended runs:

- Running against a repo with no PRD (so the agent invents what to build).
- Running with uncommitted changes the user cares about (the agent will modify them).
- Running in a directory like `auth/`, `payments/`, or `infra/` where surprise diffs are catastrophic.
- Running without seeing the issue queue first, so the user discovers in the morning that issue 0007 was the wrong one.

Today these are SOP rules — written down in §7 "Hard rules" — and nothing else. A junior engineer who skipped the SOP can still kick off a 10-iteration overnight run that modifies their working tree in `payments/` against a non-existent PRD. The headline guarantee ("ralph-afk will spend at most $X / N hours") tells you nothing about *what code* it spent the budget on.

## Solution

Add four pre-flight checks that run before the loop starts. Each check turns a current SOP rule into an actual gate, with a per-flag override so a deliberate user can still proceed. All four checks run together; failures are collected and reported as a punch list so the user fixes them in one pass.

Headline guarantee after this lands: *"ralph-afk refuses to start unless you have a PRD, your tree is clean, you're not in a known-dangerous directory, and you've eyeballed the issue queue."* Each "unless" can be waived explicitly.

## User Stories

1. As an engineer kicking off an AFK run, I want it to refuse if there's no PRD, so that I can't run the agent against guesses.
2. As an engineer kicking off an AFK run, I want it to refuse if my working tree has uncommitted changes, so that the agent doesn't modify work I'm in the middle of.
3. As an engineer who knows my dirty changes are throwaway scratch, I want a `--allow-dirty` flag so I can override that gate per-run.
4. As an engineer working in `payments/` or `infra/`, I want the loop to refuse to start so I can't accidentally let an autonomous loop edit those areas.
5. As an engineer who legitimately needs to run `ralph-afk` in a sensitive directory, I want a `--i-know-this-is-dangerous` flag so I have to *name* what I'm waiving.
6. As an engineer launching the loop, I want to see the list of issues it'll work on (id + title) and confirm before it starts, so I can spot a wrong queue at a glance.
7. As a CI/cron operator, I want a `--no-confirm` flag so the loop can run unattended without an interactive prompt.
8. As an engineer working in a non-git directory, I want the dirty-tree check to skip with a clear warning rather than refuse, so the new feature doesn't break my existing usage.
9. As an engineer who hits multiple gates at once, I want all failures reported in one error message, so I can fix everything in one round-trip rather than re-running three times.
10. As a reviewer, I want each waiver to use a self-documenting flag name (`--allow-dirty`, not `--no-guardrails`), so a PR that adds an override is reviewable.

## Implementation Decisions

### Modules

The work is one bash file edit (`scripts/ralph-afk`) — no new files. Conceptually it splits into:

- **Pre-flight checker** — runs after argv parsing and the existing CLI/PATH validation, before the main loop. Calls each gate function in turn, collects failures into an array, prints them as a punch list if any, exits non-zero.
- **Four gate functions** — each returns 0 (pass) or 1 (fail) and writes a one-line failure message to a shared accumulator when failing.
- **Issue-queue summarizer** — used by the confirmation prompt; reads `issues/*.md`, filters to unblocked, prints `id + title` in dependency order.
- **Confirmation prompt** — reads from stdin, accepts `y/Y/yes/YES`, anything else aborts.

### Interfaces (bash function signatures)

```bash
gate_prd_exists           # () -> 0|1, appends failure msg to GATE_FAILURES on fail
gate_working_tree_clean   # () -> 0|1, skipped with warning if not a git repo
gate_dangerous_path       # () -> 0|1, scans $PWD against hardcoded list
gate_confirm              # () -> 0|1, prints queue + prompts, waits for stdin
preflight                 # () -> 0|1, runs all gates, prints punch list, exits if any failed
queue_summary             # () -> stdout: "  0001 — Test harness foundation\n  0002 — ..."
```

### Gate semantics

| Gate | Default behavior | Override flag | Waived check action |
|---|---|---|---|
| `gate_prd_exists` | Fail if `docs/prd/` doesn't exist or has no non-empty `.md` file | `--allow-no-prd` | Print warning that PRD check skipped; continue |
| `gate_working_tree_clean` | Fail if `git diff --quiet` or `git diff --cached --quiet` returns non-zero | `--allow-dirty` | Print warning; continue |
| `gate_dangerous_path` | Fail if any keyword in the hardcoded list appears as a case-insensitive substring of `$PWD` | `--i-know-this-is-dangerous` | Print warning naming the matched keyword; continue |
| `gate_confirm` | Print active caps + queue, prompt `Proceed? [y/N]`, abort on anything but `y/Y/yes/YES` | `--no-confirm` | Skip the prompt entirely; continue |

### Hardcoded dangerous-path keyword list (case-insensitive substring of `$PWD`)

```
auth payment billing migration migrations infra terraform prod production secrets credentials .env
```

False positives (e.g. `author-tools` matching `auth`) are accepted; the override is one keystroke away. Tuning the list later requires editing `ralph-afk` and re-installing — that's the point (auditable).

### Non-git working tree

`git diff --quiet` returns:
- `0` if no changes
- `1` if there are changes
- `128` if not a git repo

We distinguish `128` and treat it as "no git, can't check, skip with warning":

```
ralph-afk: warning — git: not a repo, dirty-tree check skipped
```

This preserves existing usage in non-git project directories.

### Confirmation prompt format

```
ralph-afk: caps active — 10 iterations | 4h00m | $50.00

Queue (3 issues, in dependency order):
  0001 — Test harness foundation
  0002 — --max-hours time cap
  0003 — rates.json + cost computation core + install.sh wiring

Proceed? [y/N]: _
```

`--no-confirm` skips the prompt entirely; the queue is still printed (so it lands in CI logs).

### Pre-flight failure punch list

When any gate fails, print the union and exit non-zero. Each failure is one line, prefixed with `✗`:

```
ralph-afk: cannot start — fix the following:
  ✗ no PRD found in docs/prd/ (run /to-prd, or pass --allow-no-prd to override)
  ✗ uncommitted changes in working tree (commit/stash, or pass --allow-dirty)
  ✗ working directory looks dangerous (matched 'auth') — pass --i-know-this-is-dangerous to proceed

Queue would have been: 3 issues. Re-run after fixing.
```

The "queue would have been" hint lets the user verify the queue is what they expected even when the run is blocked.

### Order of operations in `ralph-afk`

```
[existing] argv parsing + validation
[existing] env setup (REPO, ISSUES_DIR, ...)
[NEW]      preflight (runs gates, exits if any failed)
[existing] startup banner
[existing] main loop
```

Pre-flight runs after env setup so it can use `$REPO`, `$ISSUES_DIR`, etc. It runs *before* the startup banner because the banner is for the loop that's about to run; if pre-flight fails, the banner would be misleading.

## Testing Decisions

External behavior only — public surface is the CLI flags and the side effects (exit code, stdout, prevention of the main loop running).

**Test cases:**

1. **No PRD → block.** Workdir with no `docs/prd/`. Expect non-zero exit, "no PRD found" in output, no iterations.
2. **Empty PRD dir → block.** Workdir with `docs/prd/` but no files. Same as above.
3. **PRD with empty file → block.** Workdir with `docs/prd/x.md` (zero bytes). Same as above.
4. **PRD with content → pass.** Workdir with `docs/prd/x.md` containing text.
5. **`--allow-no-prd` waiver works.** Workdir with no PRD + flag → loop runs, banner shows the warning.
6. **Git dirty tree → block.** Init a git repo, modify a file, don't commit. Expect block.
7. **`--allow-dirty` waiver works.**
8. **Non-git → skip with warning.** Workdir with no `.git/`. Expect loop runs, banner mentions skipped check.
9. **Dangerous path → block.** Workdir name contains `auth`. Expect block.
10. **`--i-know-this-is-dangerous` waiver works.**
11. **Multi-gate failure → punch list.** No PRD + dirty tree + dangerous path. Expect all three failures in one error.
12. **Confirmation prompt accepts `y`, `Y`, `yes`, `YES`.** Pipe each to stdin, expect loop runs.
13. **Confirmation prompt rejects anything else.** Pipe `n`, `no`, empty, garbage. Expect abort with non-zero exit.
14. **`--no-confirm` skips the prompt.** No stdin needed.
15. **Queue summary content.** With 3 fixture issues, expect 3 lines `id — title` in dependency order.

**Test scaffold:** extend `test/` with one new file, `test-guardrails.sh`. Re-uses the fake-HOME + workdir pattern from existing tests. Some cases require a git repo inside the workdir; tests `git init` and stage/modify as needed.

**Prior art:** existing `test/test-max-cost-usd.sh` already sets up fake $HOME + temp workdir + stub PATH; reuse the same helpers.

## Out of Scope

- `--prompt-file` requiring `--bypass-tdd` (deferred; small unrelated tweak).
- PRD hash snapshot for future drift detection (deferred; foundation for a feature that doesn't exist).
- Configurable dangerous-pattern list via `rates.json` or env var (deferred; ship hardcoded, add tuning if real usage shows the list is wrong).
- Detecting whether the user *read* the PRD (not detectable; outside the scope of automation).
- Slug-based PRD-to-issue alignment check (rejected in design; encodes too much workflow into the gate).
- Mtime-based PRD freshness checks (rejected; gives false confidence — `touch` defeats it).
- A global `--no-guardrails` escape hatch (rejected; per-flag forces deliberate waiving).
- Modifying the existing budget caps or CSV history (orthogonal feature — this PR doesn't touch them).

## Further Notes

- The order of override flags in `--help` should mirror the order of checks (PRD → dirty-tree → dangerous-path → confirm), so a user reading `--help` learns the gate hierarchy in priority order.
- All four override flags are documented in `SOP.md` §7 alongside the existing `--max-hours` and `--max-cost-usd` flags. Adding the section is part of this work.
- The dangerous-path keyword list is exactly 12 substrings. If the false-positive rate is annoying in practice, the followup move is **not** to make the list configurable — it's to switch to path-segment matching (Q6's option (b)). That's a one-line change and reverts the false-positive trade-off.
- Pre-flight failures should print to stderr; the queue summary in the confirmation prompt prints to stdout. Lets piped/scripted invocations distinguish "config error" from "interactive prompt waiting."
- `--no-confirm` does NOT bypass the other three gates. To run truly unattended in a sensitive context, you must pass each waiver flag explicitly (`--no-confirm --allow-dirty --i-know-this-is-dangerous --allow-no-prd`). This is intentional — the verbosity is a deterrent.
