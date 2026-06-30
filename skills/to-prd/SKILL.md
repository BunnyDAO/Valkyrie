---
name: to-prd
description: Turn the current conversation context into a PRD and save it to docs/prd/ (or publish to the issue tracker if one is configured). Use after a grill-with-docs session, when the user says "turn this into a PRD", or when /valk routes here at the PRD stage.
---

# To PRD

Adapted from mattpocock/skills with Valkyrie stage tracking and a local-first default.

## On entry

```bash
python3 "$(for p in .claude/valkyrie/stage.py "$HOME/.claude/valkyrie/stage.py" "$HOME/.claude/valk/stage.py"; do [ -f "$p" ] && echo "$p" && break; done)" set prd
```

## What to do

This skill takes the current conversation context and codebase understanding and produces a PRD. **Do NOT interview the user** — synthesize what you already know from the grilling session. If the conversation does not contain a grilling session, refuse and tell the user to run `/grill-with-docs` first (Valkyrie should already be enforcing this).

## Process

1. **Explore the repo** to understand the current state of the codebase, if you haven't already. Use the project's domain glossary (`CONTEXT.md` if present) throughout the PRD, and respect any ADRs in the area you're touching.

   **Respect the domain and intent docs when they exist (all optional, no-op if absent):**
   - `DOMAIN.md` / `PRODUCT-MAP.md` — the PRD must stay within the stated bounds. Cite the
     domain it lives in; if a decision crosses a domain boundary or a cross-repo contract,
     call it out explicitly in *Implementation Decisions* and *Out of Scope*.
   - `docs/intent/<slug>.md` (if `/to-intent` was run) — the PRD's *Problem Statement* and
     *Solution* must match the recorded why, in/out-of-scope, and success criteria. If the
     grilling diverged from the brief, reconcile it before writing — do not silently drift.

2. **Sketch the major modules** you will need to build or modify. Actively look for opportunities to extract **deep modules** — small, stable interfaces hiding a lot of behavior — that can be tested in isolation.

   Check with the user that the module list matches their expectations. Ask which modules they want tests written for.

   **Note independence + verification per module:** which modules are independent (buildable/testable in parallel) vs. dependent on others, and how each is tested and built. This feeds the parallel issue breakdown in `to-issues` (where `blocked_by` becomes the parallelism map) — fewer false dependencies there means more slices can run concurrently across worktrees.

3. **Write the PRD** using the template below.

4. **Save it.** Default location: `docs/prd/<slug>.md` in the current repo. Create the directory if needed. If `gh` is configured and the user has previously asked to use issues, also create a tracker issue with the `ready-for-agent` label.

## PRD template

```markdown
# <Feature Title>

## Problem Statement
The problem the user is facing, from the user's perspective.

## Solution
The solution to the problem, from the user's perspective.

## User Stories
A LONG, numbered list. Each story:
1. As an <actor>, I want <feature>, so that <benefit>

Cover all aspects of the feature.

## Implementation Decisions
- Modules to build/modify
- Interfaces of those modules
- Technical clarifications from the user (from the grilling session)
- Architectural decisions
- Schema changes, API contracts, specific interactions

Do NOT include specific file paths or full code snippets — they go stale fast.
Exception: if a prototype produced a snippet that encodes a decision more
precisely than prose can (state machine, reducer, schema, type shape), inline
the decision-rich part and note it came from a prototype.

## Testing Decisions
- What makes a good test here (test external behavior, not internals)
- Which modules will be tested
- Prior art for similar tests

## Out of Scope
What this PRD intentionally does NOT cover.

## Further Notes
Anything else worth recording.
```

## After saving — the PRD review gate

The PRD is the contract. Every downstream issue and every line of TDD code inherits its errors. A PRD nobody read is the single most expensive failure in the workflow. So this is a **hard checkpoint**, not a "ready?" question.

### 1. Move to the review stage

```bash
python3 "$(for p in .claude/valkyrie/stage.py "$HOME/.claude/valkyrie/stage.py" "$HOME/.claude/valk/stage.py"; do [ -f "$p" ] && echo "$p" && break; done)" set prd-review
```

The statusline now shows **▶ REVIEW-PRD** — the signal that the human owes the PRD a read before anything proceeds.

### 2. Surface decisions in chat — terse, decision-ready

Do NOT paste large PRD sections into chat. The file holds the exhaustive content; chat holds the decision-ready summary. Emit:

- **Path:** `docs/prd/<slug>.md`
- **Decisions** (≤5 bullets): the most load-bearing Implementation Decisions, each as `<decision> — <one-line why>`. Skip generic items.
- **Out of scope** (≤3 bullets): only non-obvious exclusions.
- **Risk / open question** (≤2 bullets): anything that could derail issue breakdown.

Total: under 200 words. No prose paragraphs. If a section has nothing load-bearing, omit it — don't pad.

### 3. Force engagement via AskUserQuestion (single-approve, names full scope)

Immediately after the summary, call `AskUserQuestion` (**single-select**, NOT multiSelect) with exactly three options. The single Approve option must name the *total* decision count so the user can't mistake it for picking one decision:

- `question` text: **"This PRD has N decisions above. Approving builds ALL N of them — this is the committed scope, not a pick-list. Approve to ship the whole set, Redline if any decision is wrong, or Open the file first to read."**
- **`"Approve — build all N decisions (full scope)"`** — description: `"Every decision above ships together. This is the committed scope."`
- **`"Redline a decision"`** — description: `"Pause — name which decision to change and what to change."`
- **`"Open the file first"`** — description: `"Wait — read docs/prd/<slug>.md fully before deciding."`

After the user responds:

- **Approve** → gate satisfied. Proceed to step 4.
- **Redline** → ask the user which decision and what to change; revise the PRD; re-save; re-run step 2.
- **Open the file first** → respond: *"Waiting — open `docs/prd/<slug>.md` and ping me when ready; I'll re-run the gate."* Do NOT proceed.

If the user replies in prose instead of clicking, the same rule applies — they must explicitly approve all or name a specific decision to redline. A bare "yes" / "lgtm" / "proceed" / "looks good" is NOT approval. Respond:

> "That's not engagement with the PRD. Click 'Approve — build all N' to commit to the full scope, or name one decision to redline. Then we proceed."

**Design note — do NOT switch this to a per-decision multiSelect checklist.** A previous version tried that: it created a dangerous fail-direction (a user who forgets to tick one decision has it silently interpreted as a redline), and it rendered unreliably with long decision labels + descriptions (text bleeding between rows; duplicated options). The single Approve option whose label *says* "all N" eliminates the false "pick one" exclusivity that triggered the original complaint, without those failure modes. The summary above + the "Open the file first" path provide the deep-read engagement.

### 4. Hand back to the orchestrator

Once the user has substantively approved (every decision ticked), say:

> "PRD approved: `<slug>`. Committed scope: <comma-separated decision names>. Handing back to /valk for issue breakdown."

Do NOT run `to-issues` yourself and do NOT set the `issues` stage — the orchestrator owns that transition and will verify the approval happened in this conversation before it proceeds.

## Re-entry on revisit (loop-back)

If `docs/changes/` contains a `.md` file **newer than `docs/prd/<slug>.md`**, this invocation is a re-entry — the user (or `/valk`) looped back via `valk-revisit prd "<what>"`. Read the newest change note and treat it as the revision brief:

- **Amend `docs/prd/<slug>.md` in place — do NOT regenerate from scratch.** Update only the sections the change touches (typically In Scope / Out of Scope / Implementation Decisions / Solution). Decisions not touched by the brief stand as-is.
- Under a `## Change log` heading at the very bottom (create on first revision), append: `- Δ <YYYY-MM-DD>: <one-line summary>` and cite the change-note path.
- **Re-run the PRD-REVIEW gate** (steps 1–4 above): `stage.py set prd-review`, re-surface the decisions inline with the *changed* ones marked `(Δ)`, and run the confirm-each checklist over the **full** decision set so the user re-approves the amended PRD. Old approval does not carry over.

If multiple change notes are newer than the PRD, apply them in chronological order, one Δ entry each. The change log must accurately enumerate the revision history — it is the artifact's trail.
