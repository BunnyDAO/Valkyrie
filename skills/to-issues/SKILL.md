---
name: to-issues
description: Break a plan, spec, or PRD into independently-grabbable issues using vertical slices (tracer bullets), saved locally to issues/ as numbered markdown files with dependency metadata, or published to the issue tracker if one is configured. Use after /to-prd, when user wants to convert a plan into tickets, or when /valk routes here at the ISSUES stage.
---

# To Issues

Adapted from mattpocock/skills with a local-first default so it works without a GitHub repo.

## On entry

```bash
python3 ~/.claude/valkyrie/stage.py set issues
```

## Process

### 1. Gather context

Work from whatever is already in the conversation context. If the user passes a path or issue reference, fetch it. If the previous stage was `to-prd`, the PRD is in `docs/prd/<slug>.md` — read it.

### 2. Explore the codebase (if you haven't yet)

Issue titles and descriptions should use the project's domain vocabulary (`CONTEXT.md` if present) and respect ADRs.

### 3. Draft vertical slices

Each issue is a **thin vertical slice** that cuts through ALL integration layers (schema → API → UI → tests), NOT a horizontal slice of one layer.

Slices may be **HITL** (human-in-the-loop, requires architectural review) or **AFK** (away-from-keyboard, can be implemented and merged autonomously by `afk`). Prefer AFK over HITL where possible — AFK is what makes the workflow scale.

Rules:
- Each slice delivers a narrow but COMPLETE path through every layer
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones

**Parallelization analysis.** `blocked_by` *is* the parallelism map — two slices with no
dependency path between them can run **concurrently, in separate worktrees**. As you slice:

- **Minimize false dependencies.** Add a `blocked_by` edge only when one slice genuinely needs
  another's merged output. Every spurious edge serializes work that could have run in parallel.
- **Find the independent chains** in the resulting dependency DAG — those are your parallel
  batches. Maximize how many can proceed at once.
- **Map each chain to a worktree:** `valk-worktree <name>` gives a chain its own checkout +
  `valk/<name>` branch; `valk-land <name>` integrates it back. The DAG is the source of truth —
  don't add new frontmatter for parallelism.
- For each slice, note **how it gets tested and built** (its GREEN signal), so a parallel
  runner knows what "done" means without re-deriving it.

### 4. Surface the breakdown — terse, decision-ready

Do NOT paste full issue bodies into chat. The files (saved in step 5) hold full content. In chat, emit ONE line per issue:

`N. <title> [HITL|AFK] — blocked by: <ids or "none"> — covers: <user-story #s>`

After the per-issue lines, add one **Parallel plan** line showing the independent batches and
their worktrees, e.g.:

`Parallel: [0001→0003] ∥ [0002→0004] ∥ [0005] — run each batch in its own valk-worktree`

Then call `AskUserQuestion` with these options:

- **Approve breakdown** — proceed to save (step 5).
- **Split issue N** — pauses for the user to name which and how.
- **Merge issues N+M** — pauses for the user to name which.
- **Resequence / flip HITL↔AFK** — pauses for the user to specify.

Iterate until Approve is selected. On any other option, revise the slice list and re-surface from the top of this step.

If the user replies in prose, it must name a specific change (split N, merge N+M, flip N's type) or specifically approve. A bare "yes" / "looks good" is NOT approval — ask which option above they mean.

### 5. Save the issues

**Default — local files (works without GitHub):**

Create `issues/` in the repo root if it doesn't exist. Save each slice as:

```
issues/0001-<slug>.md
issues/0002-<slug>.md
...
```

Use the template below. Number in dependency order — blockers first — so `afk` can pick the next unblocked one trivially.

**If `gh` is set up and the user opts in:** also `gh issue create` for each slice, with the `ready-for-agent` label, in dependency order so the "Blocked by" field can reference real issue numbers.

## Issue template

```markdown
---
id: 0001
title: <short descriptive name>
type: AFK            # or HITL
status: open         # open | in_progress | done | stuck
blocked_by: []       # list of issue ids, e.g. [0001, 0002]
parent: docs/prd/<slug>.md   # path to the PRD (optional)
work_item_id:        # numeric tracker ID (Azure Boards / Jira / etc.) — required if .claude/valk-config.md sets pr_skill
pr_url:              # filled in by the PR skill after the slice is merged-ready (leave blank when authoring)
---

## What to build

A concise description of this vertical slice. Describe end-to-end behavior,
not layer-by-layer implementation. Avoid file paths and code snippets — they
go stale. Exception: prototype-derived schemas/types/state-machines may be
inlined for precision.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Blocked by

- 0001 (or "None — can start immediately")
```

**Frontmatter note:** `work_item_id` and `pr_url` are only meaningful when the repo has opted into a PR workflow via `<repo>/.claude/valk-config.md` (`pr_skill: to-azure-pr` or similar). For repos without that config, omit both fields and the rest of the workflow proceeds with the existing local-only behavior.

## After saving

Tell the user how many issues were created and where, and restate the parallel plan so they can
fan the independent batches across worktrees:
> "Created N issues in `issues/`. Parallel batches: [0001→0003] ∥ [0002→0004] — spin up a
> `valk-worktree` per batch to run them concurrently, or **`!afk N`** to chew through them
> sequentially in your own shell (the `!` prefix runs in your terminal so you own the loop
> and see the `Proceed? [y/N]` confirmation). Ready to start TDD on the first unblocked one?"

If the user instead replies "yes, do afk N" / "go" / similar, you may launch `afk N` yourself
via Bash with `run_in_background: true` — afk auto-confirms when stdin isn't a TTY, so the
background tool call won't hang on the prompt. Don't auto-launch a multi-hour autonomous loop
without a clear go-ahead.

Do NOT start `tdd` yourself — let the orchestrator transition.

## Re-entry on revisit (loop-back)

If `docs/changes/` contains a `.md` file **newer than any file in `issues/`**, this invocation is a re-entry — the user (or `/valk`) looped back via `valk-revisit issues "<what>"`. Read the newest change note and treat it as the revision brief:

- **Amend existing issue files in place** — do NOT regenerate the whole set. Update only the issues the change touches (scope, acceptance criteria, dependencies).
- For requirements **dropped** by the change, set `status: obsolete` in the affected issue's frontmatter and add a one-line `Obsoleted by:` comment citing the change-note path. Do NOT delete the file — the trail matters.
- For **new** requirements from the change, create new numbered issue files (continue the sequence; never renumber) with a frontmatter line `from_change: docs/changes/<ts>-<slug>.md`.
- Append `- Δ <YYYY-MM-DD>: <one-line summary> (issues affected: 0003, 0007; new: 0012)` to `issues/CHANGES.md` (create on first revision).
- If the change invalidates the dependency graph in the PRD's parallel plan, re-run the "After saving" summary with the updated graph and **explicitly call out** which previously-parallel slices are now serial (or vice versa).

If multiple change notes are newer than `issues/`, apply them in chronological order, one Δ entry each.

**TDD invariant:** if any of the affected issues has already produced tests/code in a downstream stage, the loop-back does NOT discard them — coordinate with `/valk`'s loop-back rule (TDD work amends scope, never `rm`s tests).
