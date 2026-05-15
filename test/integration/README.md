# `test/integration/` — real-Claude behavior tests for AFK

A second test layer that runs the actual `afk` script against real Claude (paid) and audits what the agent did via captured hook traces. Complements `test/run-tests.sh` (stub-based unit suite) which verifies AFK *mechanics* but never observes real agent behavior.

## When to run

- Before a team-wide rollout
- After non-trivial changes to `scripts/afk`, `skills/tdd/`, or `skills/to-issues/`
- Periodically (nightly suggested) to catch model-drift behavior regressions

**Do not run on every PR.** This is paid and slow. The stub suite is the per-PR gate.

## How to run

```bash
# All scenarios
bash test/run-integration-tests.sh

# One scenario by name
bash test/integration/run-integration.sh trivial-slice

# Stage the fixture but don't actually invoke Claude (free; useful while iterating on fixtures)
bash test/integration/run-integration.sh --dry-run trivial-slice
```

## Cost

Each scenario invokes Claude once via `afk 1` with `--max-cost-usd 1.0` (default budget). Current pricing puts a small slice at ~$0.10–$0.50. v1 has 2 scenarios → expect ~$0.20–$1.00 per full suite run. Budget cap is enforced; if a scenario somehow blows past it, AFK's own cost-cap mechanism kills the run.

## Architecture

```
test/integration/
├── log-hook.py             # passive JSONL trace logger (always exits 0)
├── run-integration.sh      # per-scenario driver
├── fixtures/
│   ├── trivial-slice/      # fixture repo + .claude/settings.json.tmpl
│   └── stuck-on-ambiguity/
├── assertions/
│   ├── trivial-slice.sh    # behavior + cost + filesystem checks
│   └── stuck-on-ambiguity.sh
├── last-run/               # preserved per-scenario artifacts (gitignored)
│   └── <scenario>/
│       ├── reports/trace.jsonl   # the hook trace
│       ├── run.out               # afk stdout/stderr
│       ├── afk_exit              # afk exit code
│       └── <rest of work tree>
└── MANUAL-SMOKE.md         # the interactive-flow smoke procedure (not auto)
```

**Pattern**: each scenario gets a fresh mktemp HOME and work-repo. The fixture is copied in, `.claude/settings.json.tmpl` is rewritten to use the absolute `log-hook.py` path, `git init + commit` runs so AFK's preflight gates pass, then `afk` runs against the temp repo. Trace events accumulate at `$VALK_TRACE_FILE` and are preserved alongside the work tree for assertions.

## How to add a new scenario

1. `mkdir -p fixtures/<name>/{issues,docs/prd,src,.claude}` — drop a fixture repo in
2. Add `.claude/valk-config.md` with desired `pr_skill` / `test_skill` (use `none` for host-independent scenarios)
3. Copy `.claude/settings.json.tmpl` from an existing fixture (it's identical across fixtures)
4. Write the issue file(s) — one per slice you want the agent to attempt
5. Write `assertions/<name>.sh` reading `$PRESERVE_DIR` and `$AFK_EXIT`; check trace events, filesystem state, cost, etc.
6. Dry-run first: `bash run-integration.sh --dry-run <name>` to verify fixture staging works
7. Then run with real Claude and refine assertions against the actual trace

## Caveats

- The trace records every Bash invocation but not the *outcome* of commands run inside Bash (e.g., AFK + `az repos pr create` would show the Bash call but not whether the PR opened). Source-of-truth for PR state remains the issue frontmatter's `pr_url:` field, written by the `/tdd` skill via the configured `pr_skill`.
- Hook ordering: this fixture's `settings.json` wires `log-hook.py` to all 10 events. Real installations wire `valk-guard.sh` to `UserPromptSubmit`. If both are present, hooks fire sequentially — verify that `log-hook.py` going first doesn't suppress `valk-guard.sh`'s `additionalContext` injection.
- Model drift: behavior tests against real Claude WILL produce different traces over time as the model is updated. Assertions in this suite are tolerant (look for *categories* of events, not exact sequences) but expect to re-baseline periodically.
