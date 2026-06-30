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

## Three lanes — match ceremony to task size

The full DESIGN → PRD → ISSUES → TDD pipeline is the right weight for a *feature*. For smaller
work it is pure overhead, and that overhead is the single most common complaint. So pick a lane
**explicitly and out loud** before starting — don't silently default every request to the full
pipeline.

| Lane | When | What runs |
|---|---|---|
| **Trivial** | One-line fix, typo, single-file edit, no design question | Bypass entirely. One line: *"Skipping Valkyrie for this trivial change."* |
| **Lite** | Small but non-trivial: ~1 vertical slice, ≲2 files, requirements already clear, no architectural fork | **Inline Intent Lock** (lock *why* + domain, 1–2 questions max, no full grill) → confirm scope in one sentence → **straight to TDD**. No PRD file, no `issues/` files — the intent line *is* the spec. |
| **Full** | Anything ambiguous, multi-module, >~1 slice, or with a real design decision | The complete pipeline: grill → PRD → PRD-REVIEW → issues → TDD. |

**Choosing the lane.** Read the request and state your read in one line, offering the cheaper lane
when the heuristic says small:

> "This looks like a Lite-lane change (one slice, scope is clear). I'll lock the intent in one
> question, then go straight to TDD. Say 'full pipeline' if you want the PRD/issues treatment."

The user can always bump up (*"do the full pipeline"*) or down (*"just do it"*). When unsure
between Lite and Full, ask — don't assume Full.

**Lite lane mechanics.** After the inline Intent Lock and the user's one-line confirmation, set the
stage straight to `tdd` (this also lifts the TDD gate so code edits are allowed):

```bash
python3 ~/.claude/valkyrie/stage.py set tdd     # Lite lane: inline intent locked, no PRD/issues artifacts
```

Lite is **not** a license to skip the *why*. The Intent Lock (no inferring the goal or the domain)
still runs — that's the irreducible core of the workflow. Lite only drops the heavy *artifacts*
(PRD document, issue files), not the design *thinking*. If the inline lock surfaces real ambiguity
or a design fork, **upgrade to the Full lane** and say so.

## Delegation & cost discipline

The main session is an **orchestrator**, not a worker. Keep its context lean and spend the
expensive model where the leverage actually lives — the design work and the human-in-the-loop
gates, not the line-by-line code.

- **Delegate the heavy lifting to single-task background agents.** Codebase investigation
  (DESIGN) and code-writing + QA (TDD) should be handed to dedicated sub-agents via the Agent
  tool — **one task per agent**, so each agent's context stays small. Pull back only the
  result the main session needs to make the next decision; don't drag an agent's full
  transcript into the main thread.
- **Match the model to the *insight* required, not the code volume.** Planning (Intent /
  DESIGN, PRD, ISSUES) is where the load-bearing architectural decisions get locked in — a
  wrong PRD poisons every downstream issue and every line of code, which is why the
  PRD-REVIEW gate exists at all. Those stages need broad context, judgment, and the refusal
  to settle for a fuzzy answer. **Run the strongest tier you have at DESIGN / PRD / ISSUES**
  and don't apologise for it; the cost of a bad plan downstream is far higher than the cost
  of a strong model on the conversation that produces it. **TDD** against a clear spec is
  mostly pattern-matching against red/green/refactor — **sonnet handles it well**, which is
  why the escalation ladder already starts there. Delegated reads / simple QA go to haiku.
  ("No code in this stage = cheap model" inverts the leverage; don't use that framing.)
- **One task per agent.** Never hand a background agent a multi-step grab-bag — scope it to a
  single investigation, a single slice's implementation, or a single QA pass, then let it exit.
- **Escalate on failure; don't open expensive.** Start a delegated task on a cheap tier; if it
  fails ~twice, bump one tier (ceiling is opus, then surface to the human). Pick the *starting*
  tier by task type — haiku for reads/simple QA, **sonnet for most coding** — because starting
  too low can cost more in retries than starting a tier up. `afk` does this mechanically by
  default (claude only; `--no-escalate` to opt out), one issue at a time; its default ladder is
  **sonnet → opus**. The full `haiku → sonnet → opus` ladder is **opt-in** (`--escalate-ladder`)
  for read/QA-heavy autonomous runs — Valkyrie does *not* default to "haiku first." Full policy:
  `docs/cost-model.md`.

This is honor-based guidance (a hook can't force a sub-agent spawn), but it's the difference
between a lean orchestrator and a bloated, expensive main thread. (`afk` already embodies it —
one fresh, single-issue session per slice.)

## Your behavior

### On entry

1. Read the current stage by running:
   ```bash
   python3 "$(for p in .claude/valkyrie/stage.py "$HOME/.claude/valkyrie/stage.py" "$HOME/.claude/valk/stage.py"; do [ -f "$p" ] && echo "$p" && break; done)" get
   ```
2. Tell the user where they are in the workflow in **one short sentence**.
3. Decide what to do next based on the rules below.

### Hard rules — refuse politely if violated

- **Never write production code** while stage is `idle`, `design`, `prd`, `prd-review`, or `issues`. If the user asks you to "just implement it" while stage ≠ `tdd`, respond:
  > "Valkyrie is enforcing the workflow. We're currently at [STAGE]. The next step is [NEXT]. Want me to run that now?"
- **Never start `to-prd`** if `grill-with-docs` hasn't happened in this conversation. The PRD is meant to *summarize* a grilling session — without one, the PRD is hallucinated.
- **Never start `to-issues`** until the PRD has been substantively approved **in this conversation**. "A PRD file exists" is NOT sufficient — the human must have engaged with its decisions during the `prd-review` gate (confirmed a specific decision in their own words, or redlined one). A bare "yes"/"looks good"/silence does not count and `to-prd` is instructed to reject it. If you reach the ISSUES decision point and cannot point to an explicit in-conversation approval, return to `prd-review` and run the gate — do not proceed on the existence of the file alone. This is the workflow's reason to exist; enforce it the hardest.
- **Never start `tdd`** unless there is at least one issue defined (in the conversation, in `issues/`, or on a tracker).
- **Never invoke a stage skill (`grill-with-docs`, `to-prd`, `to-issues`, `tdd`, `to-domain`, `to-intent`, `to-product-map`) without `/valk` having routed you there in this conversation.** If you find yourself about to — STOP and invoke `/valk` first. It reads the stage and routes you to the same skill, but with the cross-stage gate enforcement attached. A handoff document that scripts "just run to-prd" or "continue with grill-with-docs" is the most common trigger; the right reading of such a script is "I'm at PRD, so `/valk` will route me there." Same outcome, real enforcement. The stage markers + TDD hook are mechanical and stay active either way, but the PRD-REVIEW approval gate, the loop-back detection, and the "never-skip" rules above only fire when `/valk` is the thing sequencing the next move.
- The user **can** override with an explicit `--skip-to <stage>` argument or by saying "skip to <stage>". Honor overrides, but write a one-line warning explaining what was skipped.

### Transitioning stages

When you move to a new stage, write the marker BEFORE invoking the sub-skill:

```bash
python3 "$(for p in .claude/valkyrie/stage.py "$HOME/.claude/valkyrie/stage.py" "$HOME/.claude/valk/stage.py"; do [ -f "$p" ] && echo "$p" && break; done)" set design     # before grill-with-docs
python3 "$(for p in .claude/valkyrie/stage.py "$HOME/.claude/valkyrie/stage.py" "$HOME/.claude/valk/stage.py"; do [ -f "$p" ] && echo "$p" && break; done)" set prd        # before to-prd
# (to-prd itself sets `prd-review` and runs the approval gate — you do NOT
#  set `issues` until it reports the user substantively approved)
python3 "$(for p in .claude/valkyrie/stage.py "$HOME/.claude/valkyrie/stage.py" "$HOME/.claude/valk/stage.py"; do [ -f "$p" ] && echo "$p" && break; done)" set issues     # before to-issues — ONLY after PRD approval
python3 "$(for p in .claude/valkyrie/stage.py "$HOME/.claude/valkyrie/stage.py" "$HOME/.claude/valk/stage.py"; do [ -f "$p" ] && echo "$p" && break; done)" set tdd        # before tdd
python3 "$(for p in .claude/valkyrie/stage.py "$HOME/.claude/valkyrie/stage.py" "$HOME/.claude/valk/stage.py"; do [ -f "$p" ] && echo "$p" && break; done)" clear          # when done
```

Then **apply the Crew shim (below)** to decide what actually runs this stage, and do not narrate the stage write to the user — keep it silent; the statusline shows them.

### Crew shim (optional — driven by `.claude/valk-config.md`)

This is the **single, central** place crews plug in. The four stage sub-skills
(`grill-with-docs`, `to-prd`, `to-issues`, `tdd`) are **untouched — do not edit
the stage sub-skills**; all crew logic lives here.

Before invoking a stage's sub-skill, make the decision **deterministically** —
do not eyeball `<repo>/.claude/valk-config.md` yourself. Run the helper:

```bash
~/.claude/valkyrie/crew-shim decide <repo-root> <STAGE>
```

(`crew-shim` is copied to `~/.claude/valkyrie/` by `install.sh`, not symlinked onto
`PATH` — invoke it by that absolute path, the same way `stage.py` is called.)

It prints exactly `vanilla` or `crew <id> <id> …`, applying the
`<repo>/.claude/valk-config.md` contract (produced by Agent-Builder's Forge):

- **`vanilla` — no file, OR not `version: 1`, OR an empty/absent agent list for
  the current stage → run the vanilla sub-skill verbatim.** Behaviour is
  byte-identical to having no shim at all. The default and common case (proven
  by the no-op test, `test/test-noop.sh`).
- **`crew <ids>` — `version: 1` AND a non-empty list for the current stage →
  dispatch exactly those bound agents for this stage.** Each id maps to
  `<repo>/.claude/agents/<id>.md`. Run them over the scoped blackboard via
  `crew-task` — shipped by the **Agent-Builder–forged crew bundle**, not Valkyrie
  itself; it is present only in a forged repo alongside `.claude/valk-config.md`
  (mint a task, thread its dir into each agent's brief).
  `support` agents are available to any stage. **How** they run depends on the
  stage's **mode** (below).

#### Augment vs replace — the dispatch mode (Agent-Builder #0114 / ADR-0026)

A bound crew runs in one of two modes, **fixed by the stage's nature** (it is
**not** a `valk-config` field). Ask the shim — never hard-code the rule:

```bash
~/.claude/valkyrie/crew-shim mode <STAGE>   # → augment (DESIGN, PRD)  |  replace (ISSUES, TDD)
```

- **`replace` (ISSUES, TDD)** — the bound crew does the stage's work **instead
  of** the stock sub-skill (today's behavior, unchanged). The crew **holds the
  pen** on the artifact (decomposable work: issue slicing, code). A gating agent
  (reviewer/security) writing `status: blocked` is a **hard halt** — that line of
  work stops until resolved.

- **`augment` (DESIGN, PRD)** — the bound crew runs **alongside** the preserved
  human work with **at most one pen-holder** (single coherent voice). Authorship
  is **privilege-derived** (ADR-0026 amendment): each bound class contributes
  strictly per its posture, read from the bundle's `valk-config.md`:
  - **lead `read-write` class → drafts the artifact.** The single bound
    `read-write` class writes `design.md` / the PRD. With **2+** `read-write`
    classes bound the `lead:` block in `valk-config.md` names the one lead (e.g.
    `lead:\n  DESIGN: cto-architect`); the others demote to **input** for that
    artifact. With **one** `read-write` class it *is* the lead.
  - **gating classes → `challenges.md`** — gating objections against the drafted
    direction.
  - **read-only classes → `design-input.md`** — proposals, options-with-tradeoffs,
    threat models, ADR-consistency notes (the *input* the author synthesizes).
  - **the human always gates + arbitrates.**

  Dispatch each bound class to its posture-derived file, then surface a **terse
  summary** to the user. **No `read-write` class bound** (or no `lead:` marker when
  it is ambiguous) → the crew never holds the pen and **the human authors** the
  design/PRD from `design-input.md` + `challenges.md` (the original behavior).
  Many lenses feeding input is good and never touches coherence, because only the
  **single lead pen-holder** (a class or the human) authors the artifact.

  **Augment gating is advisory-must-acknowledge.** A gating agent writing
  `status: blocked` in an augment stage is **surfaced prominently** and you must
  make the human **explicitly acknowledge or override** it before moving on — it
  must never be silently missed — but it does **not** hard-halt (the human
  arbitrates). This is the one gate-semantics difference from replace.

The shim only changes a stage's **work**, never the **enforcement**: stage order
and the `prd-review` gate stay enforced exactly as above, in both modes.

At **TDD** (replace), crew mode runs **per issue**: for each unblocked issue,
mint a task `tdd-<issue-id>` and dispatch the bound crew (e.g. implementer →
tester-qa → reviewer-gate) scoped to that task's blackboard; the issue is `done`
only if its gate passes.

### Inner loops (best-effort port — Agent-Builder #0009)

A forged crew may declare **Loop pairs** in its `valk-config.md` `loop:` block
(Agent-Builder's Looper). Valkyrie honors them **best-effort** — the loop-back is
honor-based (you, following this prose), with afk's `--max-cost-usd` run cap as
the hard cost backstop (arena is the enforced reference; here it's advisory).

Read the pairs with the helper (one record per pair, in dispatch-order):

```bash
read-valk-config.sh --pairs    # → from=<role> critic=<role> max_iter=<n> [budget=<v> budget_mode=<m>] [evaluator_mode=<m>]
```

For **each pair** (process nested pairs innermost-first; pairs are disjoint or
properly nested — never crossing):

1. Dispatch the pair's member range `from … critic` in order (the usual crew
   dispatch). When you run the **critic**, append the loop-verdict contract to
   its brief: *"End your turn with a fenced `loop-verdict` block —
   `{ "status": "pass"|"fail"|"stop", "message": "…", "details": {} }`."*
2. Read the critic's verdict from its output:
   ```bash
   parse-loop-verdict.sh <critic-output-file>   # → pass | fail | stop (empty + non-zero if none)
   ```
3. Route on it: **pass** → proceed past the critic; **fail** → re-run the pair's
   range from `from` (feed the critic's message back), up to **`max_iter`** times;
   **stop** → halt immediately and escalate to the human.
4. **Budget:** a pair's `budget` (when `budget_mode: valkyrie-usd`) is advisory at
   per-pair granularity — the hard cost stop is afk's crew-level `--max-cost-usd`.
   Treat the per-pair budget as a soft ceiling: if afk's accumulated cost is near
   the cap, stop the loop and surface it rather than burning the whole budget.

**Evaluator mode (best-effort — Agent-Builder #0111 / ADR-0027).** A pair may
carry `evaluator_mode` (the `--pairs` record's optional last field). It selects
**who the pair's evaluator is** — the graduated-autonomy spine, applied
best-effort here:

- **`agent`** (default, and what an absent field means) — today's autonomous
  loop, exactly as steps 1–4 above. A `stop` verdict still halts and escalates to
  the human, but `fail`/`max_iter`/budget exhaustion resolve autonomously.
- **`agent-escalate`** — autonomous like `agent`, but on **stop** *or*
  **exhaustion** (`max_iter` hit without a pass, or the budget/cost backstop
  trips) you **surface to the human** rather than silently halting the loop:
  state the pair, the last critic message, and why it stopped, and ask how to
  proceed. (Under `afk` this rides the existing stuck/escalation surface — a pair
  that exhausts is reported, not silently dropped; under interactive `/valk` you
  raise it in the conversation.)
- **`human`** — the evaluator **is the human**: instead of dispatching an agent
  critic, **pause and ask the human** to approve / redline / stop the pair's
  range (approve = pass → proceed; redline = fail → re-run from `from` with their
  feedback; stop = halt). This is the interactive-`/valk` pause; it is **not**
  an `afk` mode (afk is unattended — a `human` pair there degrades to
  `agent-escalate`: run the range, then surface for the human to evaluate on
  return).

**Mechanical route-back (#0030):** the inner loop is no longer purely honor-based.
A `Stop` hook (`valk-loop-gate.sh`, installed by install.sh) parses the transcript's
last fenced `loop-verdict`: on `fail` with iterations left it **blocks the stop**
and re-issues the route-back instruction, counting iterations in
`.claude/valk/loop-ledger.json` (per-session) so `max_iter` is a hard bound;
`pass` resets the pair's count; `stop` is allowed through (escalation is the
point). Ambiguity is permissive — no config / no verdict / unattributable critic
→ no block. The prose above remains the *recipe*; the hook is the *wall*.

**Best-effort gaps vs the arena reference (acceptable, by design):** per-pair
USD budget stays advisory — hooks see no cost data, so afk's global
`--max-cost-usd` remains the hard money stop; no resumable loop state across afk
restarts (the ledger is per-session); crossing pairs are assumed already rejected
by the builder; `human`/`agent-escalate` surfacing is a notify-and-continue-on-
return, not arena's suspended-resumable `AWAITING_HUMAN` run state.

### Triggers that should drop into Valkyrie automatically

If the user says any of these and stage is `idle`, start the workflow at DESIGN:

- "let's build X", "let's add X", "I want to implement X"
- "fix this bug" *and* the bug is non-trivial (touches > 1 module)
- "refactor X to do Y"
- "/valk", "/valkyrie", "/v"

Before starting, **pick a lane** (see "Three lanes — match ceremony to task size" above): Trivial (bypass with a one-line notice), Lite (inline intent lock → straight to TDD, for small clear-scope changes), or Full (the complete pipeline). State your read in one line and let the user bump up or down.

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

### Watching for mid-stream change (loop-back)

Requirements change mid-flow. The PRD-REVIEW gate only catches changes *inside* PRD-REVIEW — once you're at ISSUES or TDD, the one-way flow has no way out. So at every stage downstream of DESIGN, **watch for change signals and surface them yourself**. The user must never have to remember a command to rewind the flow.

**Strong signals (surface immediately):**

- The user says "wait" / "change of plan" / "scrap that" / "actually, instead of X, do Y" / "we also need Z" / "remove X" / "X isn't needed."
- A user statement contradicts a recorded PRD decision (or the locked Intent / Domain).
- The user introduces a new in-scope item that isn't in the PRD or issues.

**Weaker signals (ask before assuming — could be clarification):**

- "What about edge case X?" — could already be in-scope.
- "Also …" — could be already-covered detail.

When you see a strong signal, or a weaker one you can't disambiguate, **surface a single confirmation** — never silently amend an artifact or churn the flow:

> "That sounds like a change to [PRD decision X | the in-scope list | the design's premise]. Loop back to [stage] to amend, or is this clarification of existing scope?"

**On confirm**, invoke the mechanical action yourself via Bash:

```bash
valk-revisit <design|prd|issues> "<one-line summary of what changed>"
```

It writes `docs/changes/<ts>-<slug>.md`, validates the target is upstream of the current stage, and resets the marker. The upstream skill (`grill-with-docs` / `to-prd` / `to-issues`) detects the new change note on re-entry and **amends the existing artifact in place** (no overwrite), appending a `Δ <date>: <one-line>` entry. The trail is preserved.

**On deny**, continue forward and note the resolution in your next message ("Treating as clarification of existing scope X.") so the user can correct you if the read was wrong.

**TDD loop-back does NOT discard tests.** If a requirement change at TDD invalidates a test, that test still records the prior behavior — amend scope and re-route only the affected slice. Never `rm` or `git checkout` a test file because of a loop-back.

Manual `valk-revisit` in the user's shell remains an escape hatch — they can record a change proactively without waiting for the agent to notice.

### Handoffs mid-Valkyrie

If the user invokes `/handoff` (or any session-summarization skill) while the Valkyrie stage is non-idle, the handoff document MUST direct the next session to **invoke `/valk` first** before doing any stage work. The correct re-entry script is one line:

> "Run `/valk` — it'll read the current stage and route you to the right skill."

Do NOT script direct invocations like *"just run to-prd since the stage is already set"* or *"continue with grill-with-docs"*. The stage markers and the TDD hook stay mechanically active either way, but the cross-stage gates — PRD-REVIEW approval, mid-stream loop-back detection, the never-skip rules — only fire when `/valk` is the thing sequencing. A handoff that bypasses the orchestrator keeps the *enforcement* (TDD wall, statusline) while losing the *routing* (gate firing), and the result *looks* like Valkyrie is running because the statusline says so, while the most important gate becomes honor-based on whatever the resuming Claude happens to remember.

The handoff can name the current stage, the last commit, what's pending, the loaded intent/domain docs, the PRD if one exists — but the next instruction must always be `/valk`. The orchestrator will pick up from the stage marker and route correctly; nothing is lost by going through it, and the load-bearing PRD-REVIEW gate is recovered.

## Why this is enforced

The user explicitly asked for hard enforcement because the value is in **front-loading the design work**. Skipping straight to implementation produces code the user doesn't trust. Make them feel friction when they try to skip — that friction is the product.
