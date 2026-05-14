---
id: 0009
title: Dangerous-path gate
type: AFK
status: done
blocked_by: [0007]
parent: docs/prd/afk-enforcement-guardrails.md
---

## What to build

Add `gate_dangerous_path` to the preflight orchestrator. End-to-end:

- The gate scans `$PWD` for case-insensitive substrings against this hardcoded list (in `afk`):
  ```
  auth payment billing migration migrations infra terraform prod production secrets credentials .env
  ```
- If any keyword matches, the gate fails with: `working directory looks dangerous (matched '<keyword>') — pass --i-know-this-is-dangerous to proceed`.
- Only the FIRST matching keyword is named in the message (avoid spam if a path matches multiple).
- New flag: `--i-know-this-is-dangerous`. When passed, the gate skips the check and prints: `afk: warning — dangerous-path check skipped (--i-know-this-is-dangerous, would have matched '<keyword>')`. The would-have-matched info is helpful even when overridden.
- The keyword list is hardcoded in the script (auditable in PR diffs); not configurable via env or file in this slice.

## Acceptance criteria

- [x] In a workdir whose path contains `auth` (e.g. `/tmp/xyz-auth-service/`), the gate blocks with the documented failure message naming `auth`.
- [x] In a workdir whose path contains `production`, the gate blocks naming `production`.
- [x] In a workdir whose path contains no dangerous substrings, the gate passes silently.
- [x] When multiple keywords match, the first match is reported (not all).
- [x] `--i-know-this-is-dangerous` causes the gate to skip even when a keyword matches; the override warning includes the keyword that would have matched.
- [x] The match is case-insensitive: `/tmp/Production/` triggers, `/tmp/PROD/` triggers, `/tmp/production/` triggers.
- [x] Multi-gate failure works: dangerous path + no PRD produces a punch list with both entries.
- [x] New tests in `test/test-guardrails.sh` cover the above.

## Blocked by

- 0007 (orchestrator + GATE_FAILURES infrastructure)
