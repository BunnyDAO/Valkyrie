---
id: 0001
title: Test harness foundation for ralph-afk
type: AFK
status: done
blocked_by: []
parent: docs/prd/ralph-afk-budget-caps.md
---

## What to build

A self-contained test harness that lets later slices verify `ralph-afk` end-to-end without making real LLM calls. The harness lives under a new `test/` directory in the repo root and provides:

- Stub `claude` and `codex` executables (shell scripts) that, when invoked, emit deterministic canned `stream-json` output with known token counts and a configurable model name. The stubs read a fixture file from an env var (e.g. `STUB_FIXTURE=...`) so each test can choose the canned output it wants.
- A runner script that puts the stubs first on PATH, sets up a clean temp working directory containing fixture `issues/` and `docs/prd/`, runs `ralph-afk` against them, and asserts on exit code, stdout, and the stage marker.
- A single smoke test: run today's `ralph-afk 2` against a stubbed `claude` that just emits one canned `usage` event per call, confirm the loop completes 2 iterations and clears the stage on exit. This proves the harness wires up correctly before any new feature builds on it.
- A README in `test/` that documents how to add a new test (one paragraph + an example).

The harness should run in seconds, deterministically, with no network access. Tests are shell-based — no test framework dependency.

## Acceptance criteria

- [x] `test/` directory exists with stub `claude` + `codex` executables and a runner script.
- [x] `STUB_FIXTURE=<path> claude --print --output-format stream-json --verbose` emits the contents of `<path>` and exits 0.
- [x] Running the test runner from a clean checkout runs the smoke test and exits 0.
- [x] Smoke test exercises real `ralph-afk` (no mocks of the script under test) against a stubbed CLI and asserts iteration count, exit code, and stage marker.
- [x] Test runner can be invoked from any directory; it sets up its own temp workdir.
- [x] `test/README.md` shows how to add a new test in <10 lines.
- [x] Total test runtime under 5 seconds.

## Blocked by

None — can start immediately.
