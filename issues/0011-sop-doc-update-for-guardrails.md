---
id: 0011
title: SOP §7 documentation update for guardrails
type: AFK
status: done
blocked_by: [0007, 0008, 0009, 0010]
parent: docs/prd/ralph-afk-enforcement-guardrails.md
---

## What to build

Update `SOP.md` so a teammate reading it learns about the four new pre-flight gates and their override flags. Mechanical doc work — AFK with precise criteria.

Specific edits:

- **Update §7 Usage signature** to include the four new flags:
  ```
  ralph-afk <max_iterations> \
    [--cli claude|codex] \
    [--max-hours <h>] \
    [--max-cost-usd <usd>] \
    [--prompt-file <path>] \
    [--allow-no-prd] [--allow-dirty] [--i-know-this-is-dangerous] [--no-confirm]
  ```

- **Add a new subsection in §7 titled "Pre-flight guardrails"** placed AFTER "Budget caps — what stops the loop" and BEFORE "Per-iteration progress and final summary". The subsection:
  - States the headline guarantee: *"ralph-afk refuses to start unless you have a PRD, your tree is clean, you're not in a known-dangerous directory, and you've eyeballed the issue queue."*
  - Lists the four gates in a table with columns: Gate / What it checks / Failure message / Override flag.
  - Documents the dangerous-path keyword list verbatim.
  - Explains the punch-list output format with an example.
  - Notes that overrides stack: to run truly unattended in a sensitive context, all four flags must be passed.
  - Notes the non-git fallback behavior.

- **Add new rows to the failure-modes table in §8**:
  - `ralph-afk: cannot start — fix the following:` → "Pre-flight gate(s) failed. Read the punch list, fix each item, or pass the matching override flag."
  - "I keep having to pass --allow-dirty" → "Commit your work. The gate exists because the agent will modify uncommitted changes."

- **Update the cheat sheet (§12)** to add one line about overrides:
  ```
  │  Bypass gate? --allow-no-prd / --allow-dirty / etc. │
  ```

- The `<max_iterations>` positional arg's description in usage should remain unchanged.

## Acceptance criteria

- [x] `SOP.md` §7 Usage signature includes all four new flags in the order: `--allow-no-prd`, `--allow-dirty`, `--i-know-this-is-dangerous`, `--no-confirm`.
- [x] New "Pre-flight guardrails" subsection exists between "Budget caps" and "Per-iteration progress" subsections.
- [x] The four-gate table is present with columns Gate / What it checks / Failure message / Override flag.
- [x] The dangerous-path keyword list is reproduced verbatim from `scripts/ralph-afk` (no drift).
- [x] Punch-list example shows multi-gate failure (PRD + dirty tree + dangerous path).
- [x] §8 failure-modes table has at least 2 new rows about gates.
- [x] §12 cheat sheet mentions override flags in at least one line.
- [x] No existing SOP content removed or rewritten (only additions).
- [x] Running `markdownlint SOP.md` (if installed) produces no new warnings vs. before.

## Blocked by

- 0007, 0008, 0009, 0010 (all four gates must be shipped before docs accurately describe behavior)
