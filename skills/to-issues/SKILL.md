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

### 4. Quiz the user

Present the proposed breakdown as a numbered list. For each slice, show:

- **Title** — short descriptive name
- **Type** — HITL / AFK
- **Blocked by** — which other slices must complete first
- **User stories covered** — which PRD user stories this addresses

Ask:
- Does the granularity feel right? (too coarse / too fine)
- Are the dependency relationships correct?
- Should any slices be merged or split further?
- HITL/AFK markings correct?

Iterate until the user approves.

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

Tell the user how many issues were created and where:
> "Created N issues in `issues/`. Ready to start TDD on the first unblocked one? Or `afk N` to chew through them all autonomously."

Do NOT start `tdd` yourself — let the orchestrator transition.
