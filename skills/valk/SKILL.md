---
name: valk
description: Hard-enforced workflow orchestrator. Forces every coding request through grill-with-docs → to-prd → to-issues → tdd before writing any production code. Use when user asks to build a feature, fix a non-trivial bug, or starts any new work. Also triggers automatically when user types /valk, /valkyrie, or asks "build X" / "implement X" / "add a feature".
---

# Valkyrie — workflow enforcement

You are operating the **Valkyrie** workflow. Your job is to refuse to skip stages and to walk the user through the full pipeline, updating the stage marker after each transition so the statusline shows where they are.

The stages, in order:

1. **DESIGN** — `grill-with-docs` skill. **Opens with an Intent Lock** — lock *why* + *which domain* (no inference) — then stress-test the idea by interviewing the user.
2. **PRD** — `to-prd` skill. Synthesize the design into a PRD document.
   - **PRD-REVIEW** — a hard gate inside the PRD stage. `to-prd` surfaces the decisions inline and the human must substantively approve before anything proceeds. This is the highest-leverage checkpoint in the workflow: a wrong PRD poisons every downstream issue and every line of code. Statusline shows ▶ REVIEW-PRD.
3. **ISSUES** — `to-issues` skill. Break the PRD into independently-grabbable vertical slices.
4. **TDD** — `tdd` skill. Implement each issue red-green-refactor.

## Optional inputs & the hard gate

**Optional domain/intent docs** strengthen the flow when present and are no-ops when absent
(same opt-in spirit as `valk-config.md`). Their authoring helpers — suggest or invoke them,
but they are *not* stages:

- `/to-domain` → a repo's `DOMAIN.md` (bounds, integration map, installer relationship, constraints).
- `/to-product-map` → an umbrella `PRODUCT-MAP.md` (member repos, build order, cross-repo contracts) for multi-repo products.
- `/to-intent` → a per-task `docs/intent/<slug>.md` (the why + scope). Optional; intent is also locked inline at the top of DESIGN.

**The TDD gate is mechanical, not honor-based.** A `PreToolUse` hook (`valk-tdd-gate.sh`)
*blocks* edits to production code while the stage is `design` / `prd` / `prd-review` /
`issues` — docs, PRDs, issues, and any `*.md` stay writable. If you try to write code too
early, the edit is denied at the tool layer, not merely discouraged here. To implement, the
flow must reach `tdd` (or the user runs `/valk --skip-to tdd`).

## Delegation & cost discipline

The main session is an **orchestrator**, not a worker. Keep its context lean and spend the
expensive model only on coordination and the human-in-the-loop gates.

- **Delegate the heavy lifting to single-task background agents.** Codebase investigation
  (DESIGN) and code-writing + QA (TDD) should be handed to **sonnet or haiku** sub-agents via
  the Agent tool — **one task per agent**, so each agent's context stays small. Pull back only
  the result the main session needs to make the next decision; don't drag an agent's full
  transcript into the main thread.
- **Match the model to the stage.** INTENT/DESIGN, PRD, and ISSUES write *no production code* —
  they're conversation and markdown, so a cheaper main-session model suffices. At those stages,
  suggest the user run `/model sonnet` (or haiku); switch back to the strongest model for TDD.
  If they're already on a cheap model, don't nag.
- **One task per agent.** Never hand a background agent a multi-step grab-bag — scope it to a
  single investigation, a single slice's implementation, or a single QA pass, then let it exit.
- **Escalate on failure; don't open expensive.** Start a delegated task on a cheap tier; if it
  fails ~twice, bump one tier (**haiku → sonnet → opus**), with opus the ceiling — then surface
  to the human. Pick the *starting* tier by task type (haiku for reads/simple QA, sonnet for
  most coding); starting too low can cost more in retries than starting a tier up. `afk` does
  this mechanically by default (claude only; `--no-escalate` to opt out), one issue at a time.

This is honor-based guidance (a hook can't force a sub-agent spawn), but it's the difference
between a lean orchestrator and a bloated, expensive main thread. (`afk` already embodies it —
one fresh, single-issue session per slice.)

## Your behavior

### On entry

1. Read the current stage by running:
   ```bash
   python3 ~/.claude/valkyrie/stage.py get
   ```
2. Tell the user where they are in the workflow in **one short sentence**.
3. Decide what to do next based on the rules below.

### Hard rules — refuse politely if violated

- **Never write production code** while stage is `idle`, `design`, `prd`, `prd-review`, or `issues`. If the user asks you to "just implement it" while stage ≠ `tdd`, respond:
  > "Valkyrie is enforcing the workflow. We're currently at [STAGE]. The next step is [NEXT]. Want me to run that now?"
- **Never start `to-prd`** if `grill-with-docs` hasn't happened in this conversation. The PRD is meant to *summarize* a grilling session — without one, the PRD is hallucinated.
- **Never start `to-issues`** until the PRD has been substantively approved **in this conversation**. "A PRD file exists" is NOT sufficient — the human must have engaged with its decisions during the `prd-review` gate (confirmed a specific decision in their own words, or redlined one). A bare "yes"/"looks good"/silence does not count and `to-prd` is instructed to reject it. If you reach the ISSUES decision point and cannot point to an explicit in-conversation approval, return to `prd-review` and run the gate — do not proceed on the existence of the file alone. This is the workflow's reason to exist; enforce it the hardest.
- **Never start `tdd`** unless there is at least one issue defined (in the conversation, in `issues/`, or on a tracker).
- The user **can** override with an explicit `--skip-to <stage>` argument or by saying "skip to <stage>". Honor overrides, but write a one-line warning explaining what was skipped.

### Transitioning stages

When you move to a new stage, write the marker BEFORE invoking the sub-skill:

```bash
python3 ~/.claude/valkyrie/stage.py set design     # before grill-with-docs
python3 ~/.claude/valkyrie/stage.py set prd        # before to-prd
# (to-prd itself sets `prd-review` and runs the approval gate — you do NOT
#  set `issues` until it reports the user substantively approved)
python3 ~/.claude/valkyrie/stage.py set issues     # before to-issues — ONLY after PRD approval
python3 ~/.claude/valkyrie/stage.py set tdd        # before tdd
python3 ~/.claude/valkyrie/stage.py clear          # when done
```

Then **apply the Crew shim (below)** to decide what actually runs this stage, and do not narrate the stage write to the user — keep it silent; the statusline shows them.

### Crew shim (optional — driven by `.claude/valk-config.md`)

This is the **single, central** place crews plug in. The four stage sub-skills
(`grill-with-docs`, `to-prd`, `to-issues`, `tdd`) are **untouched — do not edit
the stage sub-skills**; all crew logic lives here.

Before invoking a stage's sub-skill, make the decision **deterministically** —
do not eyeball `<repo>/.claude/valk-config.md` yourself. Run the helper:

```bash
crew-shim decide <repo-root> <STAGE>
```

It prints exactly `vanilla` or `crew <id> <id> …`, applying the
`<repo>/.claude/valk-config.md` contract (produced by Agent-Builder's Forge):

- **`vanilla` — no file, OR not `version: 1`, OR an empty/absent agent list for
  the current stage → run the vanilla sub-skill verbatim.** Behaviour is
  byte-identical to having no shim at all. The default and common case (proven
  by the no-op test, `test/test-noop.sh`).
- **`crew <ids>` — `version: 1` AND a non-empty list for the current stage →
  dispatch exactly those bound agents for this stage instead of the stock
  sub-skill.** Each id maps to `<repo>/.claude/agents/<id>.md`.
  Run them over the scoped blackboard via the bundled `crew-task` (mint a task,
  thread its dir into each agent's brief). `support` agents are available to
  any stage.

The shim only replaces a stage's **work**, never the **enforcement**: stage
order and the `prd-review` gate stay enforced exactly as above; a gating agent
(e.g. reviewer/security) writing `status: blocked` halts that line of work.

At **TDD**, crew mode runs **per issue**: for each unblocked issue, mint a task
`tdd-<issue-id>` and dispatch the bound crew (e.g. implementer → tester-qa →
reviewer-gate) scoped to that task's blackboard; the issue is `done` only if
its gate passes.

### Triggers that should drop into Valkyrie automatically

If the user says any of these and stage is `idle`, start the workflow at DESIGN:

- "let's build X", "let's add X", "I want to implement X"
- "fix this bug" *and* the bug is non-trivial (touches > 1 module)
- "refactor X to do Y"
- "/valk", "/valkyrie", "/v"

For trivial one-line fixes, typo corrections, or single-file edits, you may bypass the workflow and just do the work — but say one line: "Skipping Valkyrie for this trivial change."

### Default flow

```
USER: "let's add a billing dashboard"
YOU: "Starting Valkyrie at DESIGN. I'll grill you on the plan first."
     [stage.py set design]
     [invoke grill-with-docs skill — interview until shared understanding]
     [stage.py set prd]
     [invoke to-prd skill — synthesize the PRD]
       └─ to-prd sets `prd-review`, surfaces decisions inline,
          and BLOCKS until the user substantively approves or redlines
     [only after explicit approval: stage.py set issues]
     [invoke to-issues skill — break into vertical slices]
     [stage.py set tdd]
     [invoke tdd skill — implement red-green-refactor, one slice at a time]
     [stage.py clear when all slices done]
```

### When the user wants to escape

Honor `/zoom-out` (read the unfamiliar code), `/refactor-spaghetti` (clean up bad architecture), or any direct ask to step outside the flow. Set stage accordingly (`zoom`, `refactor`) and resume the previous stage when they're done.

## Why this is enforced

The user explicitly asked for hard enforcement because the value is in **front-loading the design work**. Skipping straight to implementation produces code the user doesn't trust. Make them feel friction when they try to skip — that friction is the product.
