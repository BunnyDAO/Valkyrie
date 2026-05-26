---
name: grill-with-docs
description: Grilling session that challenges your plan against the existing domain model, sharpens terminology, and updates documentation (CONTEXT.md, ADRs) inline as decisions crystallise. Use when user wants to stress-test a plan, get grilled on their design, says "grill me", or when /valk routes here at the DESIGN stage.
---

# Grill With Docs

Adapted from mattpocock/skills with Valkyrie stage tracking.

## On entry

Mark the stage so the statusline shows DESIGN:

```bash
python3 ~/.claude/valkyrie/stage.py set design
```

## Intent Lock — first, before any grilling

Before exploring *how* to build anything, lock **why** and **where**. This is the most
failure-prone moment in the workflow: if intent is fuzzy or the domain is wrong, every
downstream decision inherits the error. **You are forbidden from filling gaps with
inference here.** Every unknown is a question, never an assumption.

Run it as a tight exchange, in order:

1. **Why** — what's true after this ships, the business/UI/technical rationale, why it
   matters now, and the trade-offs being accepted. If any of these is unstated, ask —
   do not guess.
2. **Where (the domain)** — which repo / subsystem / bounded context this lives in.
   - If a `DOMAIN.md` (and `PRODUCT-MAP.md` for multi-repo products) exists, read it and
     state the bounds back: "We're in the *X* domain — it owns *Y*, depends on *Z*."
   - If none exists, have the user name the domain in words (a `DOMAIN.md` is **not**
     required). If this repo will see more work, offer `/to-domain` to capture it.
3. **Reflect and confirm** — restate the intent in one or two sentences and the domain in
   one. The user must confirm or sharpen **in their own words**. A bare "yes" / "build X"
   / "you know what I mean" is **not** a lock — push back exactly like the PRD gate does:
   > "That's not a locked intent yet. In one sentence: what's true after this ships, and
   > what domain are we in?"
4. **Offer to persist** — once locked, offer `/to-intent` to write `docs/intent/<slug>.md`
   (optional; the intent also flows into the PRD regardless).

Only once intent + domain are locked do you move into the grilling below. If the user
opened with a crystal-clear why and domain, acknowledge it and move on — don't manufacture
friction. The rule is *no inference*, not *no momentum*.

## What to do

Interview the user relentlessly about every aspect of this plan until you reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one at a time. For each question, provide your **recommended answer** so the user can react rather than ideate from scratch.

**Ask questions one at a time.** Wait for the user's answer before moving on. A grilling session is a back-and-forth, not an interrogation list.

**If a question can be answered by exploring the codebase, explore the codebase instead.** Don't waste user attention on things you can verify yourself. **Delegate each exploration to its own single-task sonnet/haiku sub-agent** (Agent tool) — one agent per question — and when several questions are independent, **spawn them in parallel** (multiple Agent calls in a single message). Bring back just the answers; DESIGN writes no code, so keep the main session lean (see `valk` → "Delegation & cost discipline").

## Domain awareness

During codebase exploration, also look for existing documentation. Three distinct
artifacts may exist — keep them separate, they do different jobs:

- **`CONTEXT.md`** — the **glossary** (terms, relationships). Format below.
- **`DOMAIN.md`** — the repo's **bounds**: purpose, system integration map, installer/
  assembly relationship, legacy constraints, pain points. If present, read it before
  grilling and **ground every challenge in its stated bounds**. If the user's plan reaches
  outside those bounds, *flag it*: "DOMAIN.md says this repo owns X and depends on Y — but
  that change touches Z, which is out of this domain. Is that intended?" Authored by
  `/to-domain`; no-op if absent.
- **`PRODUCT-MAP.md`** — for multi-repo products: the member repos, build/assembly order,
  and cross-repo contracts. If a change spans repos, read it and name the contracts at
  risk. Authored by `/to-product-map`; no-op if absent.

`DOMAIN.md` / `PRODUCT-MAP.md` are *optional*. When absent, behave exactly as before.

### File structure

Most repos have a single context:

```
/
├── CONTEXT.md
├── docs/
│   └── adr/
│       ├── 0001-event-sourced-orders.md
│       └── 0002-postgres-for-write-model.md
└── src/
```

If a `CONTEXT-MAP.md` exists at the root, the repo has multiple contexts. The map points to where each one lives:

```
/
├── CONTEXT-MAP.md
├── docs/
│   └── adr/                          ← system-wide decisions
├── src/
│   ├── ordering/
│   │   ├── CONTEXT.md
│   │   └── docs/adr/                 ← context-specific decisions
│   └── billing/
│       ├── CONTEXT.md
│       └── docs/adr/
```

Create files lazily — only when you have something to write. If no `CONTEXT.md` exists, create one when the first term is resolved. If no `docs/adr/` exists, create it when the first ADR is needed.

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in `CONTEXT.md`, call it out immediately. "Your glossary defines 'cancellation' as X, but you seem to mean Y — which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account' — do you mean the Customer or the User? Those are different things."

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. If you find a contradiction, surface it: "Your code cancels entire Orders, but you just said partial cancellation is possible — which is right?"

### Update CONTEXT.md inline

When a term is resolved, update `CONTEXT.md` right there. Don't batch these up — capture them as they happen. Use the format in [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md).

`CONTEXT.md` should be totally devoid of implementation details. Do not treat `CONTEXT.md` as a spec, a scratch pad, or a repository for implementation decisions. It is a glossary and nothing else.

### Offer ADRs sparingly

Only offer to create an ADR when all three are true:

1. **Hard to reverse** — the cost of changing your mind later is meaningful
2. **Surprising without context** — a future reader will wonder "why did they do it this way?"
3. **The result of a real trade-off** — there were genuine alternatives and you picked one for specific reasons

If any of the three is missing, skip the ADR. Use the format in [ADR-FORMAT.md](./ADR-FORMAT.md).

## What to grill on

Beyond the domain/language work above, cover the standard design surface:

- **Scope** — what's in, what's out, what's "nice-to-have"
- **Users & actors** — who triggers this flow, who consumes the output
- **UX & interaction** — for every user-facing control, nail down what it does on click / press / hover / keyboard; the empty / loading / error / partial / over-quota / offline states; what happens on cancel, back, refresh, browser-close mid-flow; concurrency (two users acting at once; the same user in two tabs); persistence and recovery on mid-flow failure. Under-specified UX is the single most expensive thing to defer — push until each interaction is concrete, not "TBD."
- **Failure modes** — what happens when the network drops, the input is empty, two users race
- **Data model** — what entities exist, what their lifecycles are, where state lives
- **Boundaries** — which existing modules this touches, which new ones it requires
- **Migration / rollout** — does anything need to be backfilled, feature-flagged, or shimmed for backwards-compat
- **Observability** — how will the user know it's working, how will they debug it when it isn't

## When to stop

Stop when:
- Every branch you can think of has been resolved or explicitly deferred
- The user has answered a question with "I don't care, you decide" twice in a row (decision fatigue — they're done designing). **Exception:** never accept "you decide" for a **UX & interaction** question — what a control does, what an error state looks like, what happens on cancel / refresh / concurrent edits — those get pushed until concrete. Under-specified UX leaving DESIGN is the workflow's most expensive failure after a wrong PRD.
- The user explicitly says "ok, that's enough, write it up"

When you stop, summarize the session in chat — terse, decision-only.

- **Decisions** (5–10 bullets, each ≤ one line): `<decision> — <one-line why>`. Skip exploration; only resolved choices.
- **Docs updated** (paths only): `CONTEXT.md` if you wrote to it, plus any `docs/adr/*.md` files you created.

Total: under 200 words. Do NOT recap the conversation, restate the user's questions, or narrate the grilling process — the user lived it; they don't need a transcript.

Then say:

> "Ready to turn this into a PRD?"

If they say yes, the Valkyrie orchestrator will route to `to-prd` next. Do NOT run `to-prd` yourself — let the orchestrator handle the transition so the stage marker stays consistent.

## Re-entry on revisit (loop-back)

If `docs/changes/` contains a `.md` file newer than any DESIGN artifact you'd touch (`CONTEXT.md`, the latest `docs/adr/*.md`, `docs/intent/<slug>.md`), this invocation is a re-entry — the user (or `/valk`) looped back via `valk-revisit design "<what>"`. Read the newest change note and treat it as the re-grill brief:

- **Re-grill only the branches the change affects** — do NOT re-run Intent Lock or the full grilling. If the change implies the intent or domain shifted, re-confirm those *briefly* in one or two questions; otherwise leave them locked.
- Update `CONTEXT.md` for any new / changed terms (inline, same format).
- If the change demands a new architectural commitment, write a new ADR under `docs/adr/` — do not edit prior ADRs in place (their decisions are historical record).
- At the end, summarize what the revisit changed (terse — decisions only, not the conversation) and append `- Δ <YYYY-MM-DD>: <one-line summary>` to a `## Change log` at the bottom of `CONTEXT.md` (create on first revision) so the trail is preserved.

If multiple change notes are newer than the artifacts, apply them in chronological order, one Δ entry each.
