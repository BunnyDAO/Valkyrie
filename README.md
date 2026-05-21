# Valkyrie

<div align="center">
  <img width="563" height="759" 
       alt="Valkyrie slaying Tech Debt" 
       src="https://github.com/user-attachments/assets/3efca85e-34ce-4d72-b1a0-70b008beaef9" />
</div>

A hard-enforced, design-first AI coding workflow for Claude Code (and Codex CLI). Forces every coding request through the same four stages — DESIGN → PRD → ISSUES → TDD — and shows you which one you're in via a statusline that lives at the bottom of your terminal.

The goal: **5x your engineers without overcomplicating things** by making them think before they prompt and review a real PRD before they merge.

## What you get

- **A stage-aware statusline** — adapted from [moonbox3/ccstatusbar](https://github.com/moonbox3/ccstatusbar). Shows context %, model, git branch, and a colored ▶ STAGE pill.
- **An orchestrator skill — `/valk`** — the entry point. It hard-enforces the four core workflow skills below, routing every coding request through DESIGN → PRD → ISSUES → TDD in order. Try to skip a stage and it refuses, names the stage you're in, and runs the correct next step instead.
- **The four core workflow skills** (enforced by `/valk` above), adapted from [mattpocock/skills](https://github.com/mattpocock/skills):
  - `/grill-with-docs` — interview you relentlessly about your design (DESIGN stage)
  - `/to-prd` — synthesize the grilling into a PRD, then **gate**: surface the decisions inline and refuse to proceed until you substantively approve or redline (PRD + PRD-REVIEW)
  - `/to-issues` — break the PRD into independently-grabbable vertical slices (ISSUES stage)
  - `/tdd` — implement each slice red-green-refactor (TDD stage)
- **Two escape-hatch skills**: `/zoom-out` (re-orient on unfamiliar code) and `/refactor-spaghetti` (find deepening opportunities in tangled code).
- **Optional domain & intent docs (progressive enhancement)** — three authoring skills that strengthen the flow *only when you use them*, and are no-ops otherwise: `/to-domain` (a repo's `DOMAIN.md` — bounds, integrations, installer relationship, constraints), `/to-product-map` (an umbrella `PRODUCT-MAP.md` for multi-repo products), and `/to-intent` (a per-task intent brief). DESIGN also opens with an **Intent Lock** that forbids filling the *why* and domain with inference.
- **A hard TDD gate** — a `PreToolUse` hook (`valk-tdd-gate.sh`) that *mechanically* blocks production-code edits until the TDD stage, so "no code before TDD" is a wall, not a polite refusal. Docs, PRDs, issues, and any `*.md` stay writable.
- **An `afk` loop runner** — chew through issues autonomously while you sleep, with `--cli claude` or `--cli codex`. Inspired by the Ralph pattern from Geoffrey Huntley and Matt Pocock.

## Install

```bash
git clone https://github.com/BunnyDAO/Valkyrie.git
cd Valkyrie
./install.sh
```

> **Note:** This clones to your current directory. To clone to a specific location (e.g., your home directory), use `git clone https://github.com/BunnyDAO/Valkyrie.git ~/valkyrie && cd ~/valkyrie`

That's it. It will:
- Symlink the skills into `~/.claude/skills/`
- Copy the statusline + stage helper into `~/.claude/valkyrie/`
- Patch `~/.claude/settings.json` to use the statusline
- Symlink `afk` into `~/.local/bin/`

Restart Claude Code to pick up the new statusline.

### Optional: full ccstatusbar usage segments

If you want the OAuth-backed `5h:13%` and `wk:25%` segments from ccstatusbar, install it alongside:

```bash
curl -fsSL https://raw.githubusercontent.com/moonbox3/ccstatusbar/v1.0.1/install.sh | bash
```

Valkyrie's statusline auto-detects `~/.claude/ccstatusbar.py` and delegates to it for those segments, then appends the STAGE pill.

## How to use

For the full end-to-end flow (interactive + AFK + config gates), see [`docs/workflow.md`](docs/workflow.md).

### Standard flow

Just describe what you want to build:

> "Let's add a billing dashboard."

`/valk` activates automatically. The statusline switches to **▶ DESIGN** and Claude starts grilling you. When you've resolved the decision tree, it moves to **▶ PRD**, then **stops at ▶ REVIEW-PRD** — it shows you the PRD's decisions inline and won't continue until you engage with them (a bare "yes" is rejected). After you approve, **▶ ISSUES**, then **▶ TDD**.

If at any point you try to skip ahead — *"just write it"* — Claude will refuse, tell you what stage you're in, and offer to run the next correct step.

### Skip-ahead override

Power users can short-circuit:

> "/valk --skip-to tdd"

Or:

> "Skip to to-prd, I already have the design in my head."

You'll get a one-line warning explaining what was skipped.

### AFK mode

Once `to-issues` has saved a list to `issues/`, run the loop:

```bash
afk 10                                       # 10 iters; defaults: 4h cap, $50 cap, claude CLI
afk 10 --cli codex                           # same, but use codex
afk 50 --max-hours 12 --max-cost-usd 200     # overnight run with a larger budget
```

**Inputs:**
- **N** (positional, required) — max iterations to run.
- **`--max-hours <H>`** — wall-clock cap. Default `4`. Loop exits at the next iteration boundary once hit.
- **`--max-cost-usd <USD>`** — spend cap. Default `50`. Uses the CLI's own `total_cost_usd` when reported (accurate); falls back to recomputing from token usage × placeholder rates in `~/.claude/valkyrie/rates.json` only when the CLI doesn't report one (crash/kill/timeout, or the `codex` CLI). Each iteration's basis is shown as `[reported]` or `[estimated]`. **Under a Claude subscription (not API key) this figure is notional, not a bill** — see SOP §7.
- **`--cli claude|codex`** — which CLI to drive. Default `claude`.

**`VALK_COST_MODE`** (env var, not a flag) — `auto` (default), `dollars`, or `tokens`. `auto` shows tokens when the run is on a Claude subscription (`apiKeySource: none` — dollars would be notional) and dollars when it's billed via an API key. Set `export VALK_COST_MODE=tokens` on a personal Pro/Max machine; commercial-API teammates leave it unset or set `dollars`. The `--max-cost-usd` cap is unchanged in both modes (a proxy ceiling in token mode). See SOP §7.

The loop picks the next unblocked issue, spawns the CLI with a fresh context, and lets it implement the slice. **Whichever cap is hit first wins** — iterations, hours, or dollars. The statusline shows **▶ AFK**. Logs land in `.claude/valk/afk-logs/`, and a per-iteration row (including `cost_source`) is appended to `.claude/valk/afk-cost-history.csv`.

### Running flows in parallel

Multiple Valkyrie flows on one project? Don't share a checkout — give each
its own git worktree, or they corrupt each other (commit sweeps, false-red
runs). One command each way:

```bash
valk-worktree <name>      # isolate this terminal in ../<repo>-<name> on valk/<name>
# … run /valk … /tdd in that worktree …
valk-land <name>          # integrate-back: delegates to pr_skill, else rebase+test-gate+ff+push
valk-worktree --remove <name>   # cleanup (or `valk-land --clean`)
```

Full how-to (lifecycle, the test gate, conflict handling, the
`.valk-worktree-setup` hook): **SOP.md → "Running multiple flows in
parallel"** and `docs/workflow.md`.

### Per-project config (opt-in PR workflow)

Repos can opt into a "the deliverable is a PR" workflow by adding `<repo>/.claude/valk-config.md`. With this file, `/tdd` and `afk` change what "done" means: instead of flipping a frontmatter field, the slice is only marked done after a pull request is opened and its CI build passes green.

Minimal opt-in (Azure DevOps + TrueTest):

```markdown
---
pr_skill: to-azure-pr      # name of a PR-opening skill installed in the env
test_skill: run-truetest   # name of a test-runner skill (the GREEN signal in /tdd)
azure_devops:
  repository: <repo-name>
---
```

When `pr_skill` is set, `afk`'s done-check derives state from the agent-written `pr_url:` field in the issue file — not the `status:` field. An agent that flips `status: done` without opening a PR is forced to `stuck`. The CSV cost-history gains a `pr_url` column so you can compute cost-per-PR-opened instead of cost-per-iteration.

**This is opt-in.** Repos without `.claude/valk-config.md` see no change in behavior — `/tdd` marks issues done locally and `afk` reads the frontmatter, exactly as before.

Full format spec: [`docs/valk-config-format.md`](docs/valk-config-format.md). The
`valk-config.md` file and the crew shim it drives come from **HiveOp / crew**
([crew.hiveop.io](https://crew.hiveop.io)) — see [`docs/crew.md`](docs/crew.md) for what crew
is and how it binds to Valkyrie.

### Optional domain & intent docs

Out of the box, Valkyrie knows nothing about *your* codebase's bounds — so DESIGN grilling can
only push on what you say in the moment. These optional docs give the workflow a durable,
written frame of reference, so the agent grounds its questions in your real domain instead of
inferring. **All are no-ops when absent** — write none and behavior is exactly as before; write
more and enforcement scales up.

They are deliberately **four single-purpose docs**, not one big one — each stays small and
doesn't rot into the others:

- **`CONTEXT.md`** — the *glossary* (terms & relationships). Written inline by `/grill-with-docs`. **Unchanged by this feature.**
- **`DOMAIN.md`** — the repo's *bounds*. Written by `/to-domain`.
- **`docs/adr/*.md`** — *decisions*. `DOMAIN.md` **links** to them; it never restates them.
- **`PRODUCT-MAP.md`** — the *cross-repo* view, for multi-repo products. Written by `/to-product-map`.

…plus a per-task **`docs/intent/<slug>.md`** (the *why* of one change) written by `/to-intent`.

| Doc | Lives at | Write it when | Holds |
|---|---|---|---|
| `DOMAIN.md` | repo root | a repo will see repeated work, or its integrations/constraints are non-obvious | purpose; system integration map (depends-on / depended-on-by / key contracts); installer/assembly relationship; legacy constraints; pain points |
| `PRODUCT-MAP.md` | product umbrella root | your product is assembled from multiple repos | member repos; build/assembly order; cross-repo contracts |
| `docs/intent/<slug>.md` | per task | a task's *why* is non-trivial and worth pinning before design | outcome; why; in/out of scope; success criteria; trade-offs |

Once a `DOMAIN.md` exists, `/grill-with-docs` reads it before grilling, grounds every challenge
in its bounds, and **flags drift** when a plan reaches outside them; `/to-prd` then keeps the
PRD inside them. `PRODUCT-MAP.md` does the same for changes that span repos. And DESIGN always
opens with an **Intent Lock** — it makes you state the *why* and name the domain first, and is
forbidden from filling those gaps with inference (every unknown becomes a question).

**What a `DOMAIN.md` looks like:**

```md
# Domain: payments-svc

## Repository Purpose
Owns payment capture and refunds. Does NOT own ledger balances (that's ledger-svc).

## System Integration Map
- Depends on: ledger-svc (reads balances)
- Depended on by: checkout-web (calls the capture API)
- Key contracts & data flows: POST /capture; emits the PaymentCaptured event

## Installer / Assembly Relationship
Built as an npm package, after ledger-svc, before checkout-web. Must keep the v1 /capture ABI.

## Legacy Constraints & Gotchas
Retry path in capture.ts predates idempotency keys — must not double-charge.

## Pain Points
capture.ts retry logic is fragile; only touch it with tests.

## Pointers
- Glossary: ./CONTEXT.md  ·  Decisions: ./docs/adr/  ·  Cross-repo: ../PRODUCT-MAP.md
```

**And the umbrella `PRODUCT-MAP.md` that ties those repos together:**

```md
# Product Map: Acme Checkout

## Overview
Three repos assembled by the installer into the Acme Checkout product.

## Member Repos
- **ledger-svc** — owns account balances — [DOMAIN.md](ledger-svc/DOMAIN.md)
- **payments-svc** — payment capture & refunds — [DOMAIN.md](payments-svc/DOMAIN.md)
- **checkout-web** — the storefront UI — [DOMAIN.md](checkout-web/DOMAIN.md)

## Build / Assembly Order
ledger-svc → payments-svc → checkout-web. payments-svc must keep the v1 /capture ABI.

## Cross-Repo Contracts
- **PaymentCaptured event** — payments-svc → ledger-svc: ledger debits on this event;
  reshaping or renaming it breaks balance updates.
- **POST /capture** — checkout-web → payments-svc: the storefront's capture call; breaking
  its shape breaks checkout.
```

Field-by-field specs for each: [`DOMAIN-FORMAT.md`](skills/to-domain/DOMAIN-FORMAT.md),
[`PRODUCT-MAP-FORMAT.md`](skills/to-product-map/PRODUCT-MAP-FORMAT.md),
[`INTENT-FORMAT.md`](skills/to-intent/INTENT-FORMAT.md). End-to-end walkthrough (single- and
multi-repo): [`docs/workflow.md`](docs/workflow.md).

The builder skills write plain markdown. Teams stamping many repos can instead render the
co-located `*.j2` templates with [sc-compose](https://github.com/BunnyDAO/sc-compose), which
declares required fields up front and **fails loudly** if any is missing. sc-compose is an
authoring convenience only — Valkyrie reads plain markdown and never needs it at runtime.

### Cost discipline (cheaper models + single-task delegation)

The first stages — INTENT/DESIGN, PRD, ISSUES — write **no production code**; they're
conversation and markdown. So don't pay the strongest model for them:

- **Match the model to the stage.** At DESIGN, switch the main session with `/model sonnet`
  (or haiku); switch back to your strongest model for TDD.
- **Keep the main session an orchestrator.** Delegate codebase investigation and
  code-writing/QA to **single-task sonnet/haiku sub-agents**, pulling back only the result —
  so the main thread's context stays small. `/valk` and the stage skills are wired to nudge
  this, and `afk` already runs one fresh single-issue session per slice.
- **Escalate, don't open expensive.** On repeated failure, bump one tier — the full ladder is
  **haiku → sonnet → opus** (opus the ceiling, then a human). `afk` does this mechanically per
  issue **by default** (claude only), retrying a failing issue at the next tier before giving up.
  Its default ladder is **sonnet → opus** (afk writes code, so haiku-first just churns); pass
  `--escalate-ladder "haiku sonnet opus"` to start cheaper for read/QA-heavy work, or
  `--no-escalate` to turn it off.
- **Parallelize across worktrees.** `/to-issues` treats `blocked_by` as the parallelism map and
  emits a batch plan; run each independent batch in its own `valk-worktree` to work concurrently
  (integrate back with `valk-land`).

To make it the default for **every** session (not just Valkyrie workflows), drop this into your
`~/.claude/CLAUDE.md`:

```md
## Cost discipline (orchestration)
- Use sonnet or haiku background agents for investigations, code-writing, and QA wherever appropriate and possible.
- Keep the main session focused on orchestration so goals are met and context stays small.
- Give each background agent a single task to limit its context overhead.
```

### Escape hatches

- `/zoom-out` — when you're lost in unfamiliar code
- `/refactor-spaghetti` — when the architecture needs deepening

Both update the stage and restore it when done.

### Testing

Two layers:

- **`bash test/run-tests.sh`** — stub-based unit suite. Free, deterministic, fast. Covers cost caps, time caps, guardrails, CSV format. Run on every change.
- **`bash test/run-integration-tests.sh`** — real-Claude integration suite. Costs ~$1 per full run. Drives `afk` against fixture repos with hook traces captured to `test/integration/last-run/<scenario>/reports/trace.jsonl` for offline audit. Run manually before any rollout.

The full interactive flow (DESIGN → PRD → ISSUES → TDD with a human in the loop) has a manual smoke procedure documented in [`test/integration/MANUAL-SMOKE.md`](test/integration/MANUAL-SMOKE.md) — ~15 min, ~$2–5 in API credits.

## Project layout

```
Valkyrie/
├── install.sh                 # one-shot installer
├── README.md                  # this file
├── SOP.md                     # the org rollout SOP
├── .claude-plugin/
│   └── plugin.json            # so this can also install as a Claude plugin
├── statusline/
│   ├── statusline.py          # adapted ccstatusbar with STAGE pill
│   └── stage.py               # tiny CLI for skills to read/write stage state
├── skills/
│   ├── valk/            # master orchestrator (hard enforcement)
│   ├── grill-with-docs/              # design interrogation
│   ├── to-prd/                # PRD synthesis
│   ├── to-issues/             # vertical-slice issue breakdown
│   ├── tdd/                   # red-green-refactor
│   ├── to-domain/             # author a repo's DOMAIN.md (optional)
│   ├── to-product-map/        # author an umbrella PRODUCT-MAP.md (optional)
│   ├── to-intent/             # author a per-task intent brief (optional)
│   ├── zoom-out/              # re-orient on unfamiliar code
│   └── refactor-spaghetti/    # find deepening opportunities
└── scripts/
    ├── afk                    # autonomous loop, claude or codex
    ├── valk-guard.sh          # UserPromptSubmit: nudge into the flow
    └── valk-tdd-gate.sh       # PreToolUse: block code edits before TDD
```

## Credits

- Statusline: [moonbox3/ccstatusbar](https://github.com/moonbox3/ccstatusbar)
- Skills: [mattpocock/skills](https://github.com/mattpocock/skills)
- Ralph pattern: Geoffrey Huntley, popularized by Matt Pocock at [aihero.dev](https://www.aihero.dev/)
