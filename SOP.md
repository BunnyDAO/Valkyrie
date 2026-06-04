# Valkyrie — Engineering SOP

**Audience:** every engineer at the company.
**Time to first use:** 5 minutes.
**Goal:** 5x throughput by forcing every prompt through a design-first workflow you can review.

> If you're going to ship code an AI wrote, you have to read a PRD first. Valkyrie makes you read it once and then trust the LLM to summarize the rest. Front-load the design — recover the time at every later step.

---

## TL;DR (the only thing you have to remember)

```
Don't tell the AI to "build X."
Say "let's build X" — and let /valk walk you through DESIGN → PRD → ISSUES → TDD.
```

The statusline at the bottom of your terminal will show you which stage you're in. If you try to skip a stage, the AI will refuse and route you back. That refusal is the product.

---

## 1. Install (one time)

```bash
git clone https://github.com/BunnyDAO/Valkyrie.git ~/valkyrie
cd ~/valkyrie
./install.sh
```

Then **restart Claude Code**. You should see a colored ▶ STAGE pill in your statusline.

If you also want OAuth-backed usage segments (`5h:13%`, `wk:25%`):

```bash
curl -fsSL https://raw.githubusercontent.com/moonbox3/ccstatusbar/v1.0.1/install.sh | bash
```

### Where things live after install

`install.sh` is idempotent and writes to two scopes — global (every Claude Code session sees it) and per-project (each repo tracks its own state).

| Artifact | Path | Scope | What it does |
|---|---|---|---|
| Skills | `~/.claude/skills/{valk,grill-with-docs,to-prd,to-issues,tdd,zoom-out,refactor-spaghetti}/` | Global | The workflow logic. Symlinks back into the repo, so `git pull` updates them. |
| Statusline + stage helper | `~/.claude/valkyrie/{statusline.py,stage.py}` | Global | Renders the ▶ STAGE pill; reads/writes the stage file. |
| UserPromptSubmit hook | `~/.claude/hooks/valk-guard.sh` | Global, runs every prompt | Soft-start enforcement — nudges build prompts into `/valk`. See §2. |
| PreToolUse TDD gate | `~/.claude/hooks/valk-tdd-gate.sh` | Global, runs on edit/Bash tool calls | Hard wall — mechanically blocks production-code edits before TDD. See §2. |
| PostToolUse telemetry | `~/.claude/hooks/valk-telemetry.sh` | Global, runs on file tool calls | The AFK audit log — records file Read/Edit during active stages. See §7. |
| Settings glue | `~/.claude/settings.json` | Global | Wires the statusline + hook. Patched in place. |
| Stage marker | `<repo>/.claude/valk/stage` | Per-project | Current workflow stage. Each repo tracks its own. |
| AFK logs | `<repo>/.claude/valk/afk-logs/` | Per-project | One log file per `afk` iteration. |
| PRDs | `<repo>/docs/prd/<slug>.md` | Per-project | Output of `/to-prd`. |
| Issues | `<repo>/issues/0001-*.md` | Per-project | Output of `/to-issues`. Vertical slices with frontmatter. |
| Domain/intent docs (optional) | `<repo>/DOMAIN.md`, `<repo>/PRODUCT-MAP.md`, `<repo>/docs/intent/*.md` | Per-project | Output of `/to-domain`, `/to-product-map`, `/to-intent`. No-op if absent. |
| Telemetry (AFK audit log) | `<repo>/.claude/valk/telemetry/<session>.jsonl` | Per-project | File Read/Edit trail per session. See §7. |
| `afk` binary | `~/.local/bin/afk` → repo | Global | The autonomous loop. Run from any project directory. |

**What's accessible from any directory:** the slash commands (`/valk`, `/grill-with-docs`, etc.), the hook, the statusline, the `afk` binary. **What's project-local:** the stage marker, AFK logs, PRDs, issues. That separation is intentional — you can have two repos in different stages at once without them clobbering each other.

To update everything later: `cd ~/valkyrie && git pull && ./install.sh`.

---

## 2. Hard enforcement — the UserPromptSubmit hook

The skill auto-triggers on phrases like "let's build X" via its skill description. That's *soft* enforcement — Claude usually obeys, but can drift mid-conversation.

For **hard** enforcement, install the `UserPromptSubmit` hook. Hooks are shell commands Claude Code runs at specific lifecycle events; this one inspects every prompt you submit and injects a non-negotiable system reminder when you write a build/fix/refactor prompt while the stage is idle. Claude cannot ignore it the way it can ignore a CLAUDE.md line.

### How the hook works

1. You hit enter on a prompt.
2. Claude Code pipes the prompt JSON to `~/.claude/hooks/valk-guard.sh` via stdin.
3. The script checks the current stage (via `stage.py get`) and pattern-matches the prompt against build/fix/refactor language.
4. If both conditions hit, the script writes a JSON `additionalContext` payload to stdout. That context is prepended to the prompt Claude sees, with the directive: *"You MUST invoke the valk skill before writing any code."*
5. Otherwise the hook exits silently — no friction.

### Install the hook

The repo's `install.sh` does this for you. To do it manually:

**a)** Drop `valk-guard.sh` into `~/.claude/hooks/` and make it executable:

```bash
mkdir -p ~/.claude/hooks
cp scripts/valk-guard.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/valk-guard.sh
```

**b)** Add the hook entry to `~/.claude/settings.json` (merge with your existing settings):

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/Users/<you>/.claude/hooks/valk-guard.sh"
          }
        ]
      }
    ]
  }
}
```

**c)** That's it — no restart required. Claude Code re-reads `settings.json` on every prompt submission, so the hook is live on your very next message. (Verified: see "Verifying it's live" below.)

### What it does NOT block

- Prompts that explicitly say `skip valk`, `trivial change`, `one-line fix`, or pass `--skip-to`
- Prompts that start with `/valk`, `/valkyrie`, `/grill-with-docs`, `/to-prd`, `/to-issues`, `/tdd`, `/zoom-out`, `/refactor-spaghetti`
- Anything submitted while the stage is mid-workflow (the skill itself owns that turf)

### Smoke test (CLI — proves the script works)

```bash
echo '{"prompt":"lets build a billing dashboard"}' | ~/.claude/hooks/valk-guard.sh
# expect: a JSON block with hookSpecificOutput.additionalContext
echo '{"prompt":"what is 2+2"}' | ~/.claude/hooks/valk-guard.sh
# expect: empty (no enforcement)
```

### Verifying it's live in Claude Code

If you want to confirm Claude Code is actually invoking the hook on each prompt (not just that the script works in isolation), add a one-line debug log temporarily:

```bash
# add near the top of ~/.claude/hooks/valk-guard.sh, after PROMPT=...:
printf '[%s] %q\n' "$(date '+%H:%M:%S')" "$PROMPT" >> ~/.claude/hooks/valk-guard.log
```

Submit any prompt in Claude Code, then `cat ~/.claude/hooks/valk-guard.log`. If you see an entry, the hook is wired in. Remove the line + the log file when you're done.

### Working in new sessions, new projects

- **New chat / new conversation, same machine:** nothing to do. The hook is global (`~/.claude/hooks/`) and loaded per-prompt. Just open Claude Code.
- **Different project directory:** same answer. The hook is global; the *stage* is per-project (each project tracks its own DESIGN/PRD/ISSUES/TDD state in `<cwd>/.claude/valk/stage`).
- **New machine / onboarding a teammate:** clone the repo and run `./install.sh`. It's idempotent.

### Disabling temporarily

If you need the hook off for a session, comment out the `hooks` block in `~/.claude/settings.json`. The change applies on your next prompt — no restart. Don't delete the script — you'll want it back.

### The PreToolUse TDD gate — the second, harder layer

The UserPromptSubmit hook nudges you *into* the workflow. It doesn't stop the model from
drifting once inside — and honor-based stage rules drift, especially in long sessions and AFK
runs. The **PreToolUse gate** (`~/.claude/hooks/valk-tdd-gate.sh`, installed and wired by
`install.sh`) closes that gap mechanically:

- While the stage is `design` / `prd` / `prd-review` / `issues`, edits to **production code**
  are **denied at the tool layer** — `Edit` / `Write` / `NotebookEdit`, plus best-effort
  coverage of file-writing `Bash` (e.g. `echo … > foo.ts`). The model literally cannot write
  source before TDD.
- **Workflow artifacts stay writable at every stage:** anything under `docs/`, `issues/`,
  `.claude/valk/`, and any `*.md` — so PRDs, issue files, and `DOMAIN.md` are never blocked.
- **Not gated:** `idle` (you're not in a flow), `tdd` / `afk` (implementation), and
  `refactor`. To implement, reach `tdd` or run `/valk --skip-to tdd`.

Smoke test:

```bash
printf '{"tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"src/x.ts"}}' "$PWD" \
  | ~/.claude/hooks/valk-tdd-gate.sh        # at design stage → JSON with permissionDecision "deny"
```

**Honest limits:** airtight for the edit tools (clear `file_path`); best-effort for `Bash`
(only blocks writes that clearly target a source file); disableable, since it's your machine.
The threat model is **model drift, not sabotage** — against drift it's a real wall. Disable it
the same way as the guard: remove its entry from the `hooks` block in `settings.json`.

**Handoff gotcha.** If you `/handoff` mid-Valkyrie (e.g. nearing context limit), the resuming session **must invoke `/valk` first**, not stage skills directly. The stage marker + TDD gate keep mechanical enforcement intact, but the orchestrator's cross-stage gates (PRD-REVIEW approval, mid-stream loop-back detection, the never-skip rules) only fire when `/valk` is the thing routing — a handoff that scripts *"just run to-prd directly"* keeps the statusline looking right while silently turning the load-bearing PRD gate honor-based. `valk/SKILL.md` now refuses to invoke a stage skill without `/valk` having routed there, but the cleanest fix is the handoff itself: tell the next session *"Run `/valk`"* as the first instruction.

---

## 3. The four stages — what they're for

| Stage | Skill | What you do | What you DON'T do |
|---|---|---|---|
| **DESIGN** | `/grill-with-docs` | First answer the **Intent Lock** (the *why* + which domain — stated, not guessed), then the AI's design questions, one at a time. | Skip ahead. Outsource thinking. Let it infer your intent. |
| **PRD** | `/to-prd` | Read the PRD it generates. ~5 minutes. Edit anything wrong. | Treat the PRD as a formality. |
| **PRD-REVIEW** | (gate in `/to-prd`) | Engage with the decisions it shows you inline. Confirm one in your own words, or redline one. | Reply "yes"/"lgtm" — the gate rejects it and won't proceed. |
| **ISSUES** | `/to-issues` | Confirm the vertical-slice breakdown. Adjust dependencies. | Accept thick slices that touch one layer only. |
| **TDD** | `/tdd` | Watch the red-green-refactor loop. Catch test smells. | Let it write all tests upfront — that's horizontal slicing. |

**The DESIGN stage is where the value compounds.** If you spend 20 minutes there, you'll save 2 hours in TDD because the AI isn't guessing what you want.

### Optional: make it domain-aware

By default the AI only knows what you tell it in the moment. These optional docs give it a
written frame of reference so it grounds its grilling in your real domain instead of guessing.
**All are no-ops when absent** — adopt them at your own pace; enforcement scales with what you
write.

- **`/to-domain`** → a repo's **`DOMAIN.md`** at the repo root. Write it for any repo that'll
  see repeated work, or whose integrations/constraints are non-obvious. Captures: purpose,
  system integration map (depends-on / depended-on-by / key contracts), installer/assembly
  relationship, legacy constraints, pain points. Once it exists, grilling grounds every
  challenge in it and **flags drift** when a plan reaches outside its bounds, and the PRD stays
  inside them.
- **`/to-product-map`** → an umbrella **`PRODUCT-MAP.md`**, *only* for a product assembled from
  many repos: member repos, build/assembly order, cross-repo contracts. Generalizes to any
  number of repos. Read whenever a change spans repos.
- **`/to-intent`** → a per-task brief at **`docs/intent/<slug>.md`** for any change whose *why*
  is non-trivial: outcome, why, in/out of scope, success criteria, trade-offs. The DESIGN
  **Intent Lock** captures this inline regardless; the file just makes it durable and reviewable.

Keep them single-purpose — that's why they're separate files: `CONTEXT.md` = glossary
(unchanged), `DOMAIN.md` = bounds, `docs/adr/` = decisions, `PRODUCT-MAP.md` = cross-repo view.

Field-by-field specs ship inside each skill (`skills/to-domain/DOMAIN-FORMAT.md`,
`skills/to-product-map/PRODUCT-MAP-FORMAT.md`, `skills/to-intent/INTENT-FORMAT.md`). A worked
`DOMAIN.md` example is in `README.md` → "Optional domain & intent docs"; the full single- and
multi-repo walkthrough is in `docs/workflow.md`.

Builder skills write plain markdown; teams stamping many repos can render the co-located
`*.j2` templates with [sc-compose](https://github.com/BunnyDAO/sc-compose) for fail-loud
required-field validation.

**Worked example (end to end).** Say your product is assembled from `ledger-svc`,
`payments-svc`, and `checkout-web`:

1. **Once, at the umbrella root:** `/to-product-map` → writes `PRODUCT-MAP.md` — the three
   repos, the build order, and the cross-repo contracts (e.g. the `PaymentCaptured` event).
2. **Once per repo:** `/to-domain` in `payments-svc` → writes its `DOMAIN.md` (owns capture &
   refunds, depends on `ledger-svc`, must keep the v1 `/capture` ABI).
3. **Now do real work:** "let's add refunds." DESIGN opens with the **Intent Lock** — it reads
   `payments-svc/DOMAIN.md`, makes you state the *why* (no guessing), and flags that refunds
   touch `ledger-svc` via a cross-repo contract in `PRODUCT-MAP.md`. You resolve that *before*
   any code exists.
4. → **PRD** (kept inside those bounds) → **REVIEW-PRD** → **ISSUES** → **TDD**. The TDD gate
   blocks any production-code edit until you actually reach TDD.

Write none of these docs and step 3 still runs — it just has less to ground itself in. That's
"enforcement scales with what you write" in practice.

### Cost discipline — model tier follows leverage, delegate the rest

The expensive model belongs where the *leverage* is. INTENT / DESIGN / PRD / ISSUES write no
production code, but they're where the load-bearing architectural decisions get locked in —
a wrong PRD poisons every downstream issue and every line of code, which is exactly why the
PRD-REVIEW gate exists. So the model-tier rule inverts the obvious one:

- **Match the model to the *insight* required, not the code volume.** Run DESIGN / PRD /
  ISSUES on the strongest tier you have — broad context, judgment, and refusing to settle
  for a fuzzy answer is what those stages are worth paying for. TDD against a clear spec is
  mostly pattern-matching against red/green/refactor — **drop to `/model sonnet` once you
  reach TDD**, which is where the escalation ladder already starts. Delegated reads / simple
  QA go to haiku. The cost of a bad plan downstream — extra iterations, refactors, or worse,
  wrong code that passes tests — is far higher than the cost of a strong model on the
  conversation that produces the plan.
- **Keep the main session an orchestrator.** Hand codebase investigation (DESIGN) and
  code-writing/QA (TDD) to **single-task sonnet/haiku sub-agents** and pull back only the
  result, so the main thread's context stays small. `/valk` and the stage skills nudge this;
  `afk` already runs one fresh single-issue session per slice.
- **Escalate instead of starting expensive.** On repeated failure bump one tier (full order
  **haiku → sonnet → opus**, opus the ceiling, then a human). `afk` does this **by default**
  (claude only): it retries a failing issue at the next tier per iteration before marking it
  stuck. Its default ladder is **sonnet → opus** (afk writes code); pass
  `--escalate-ladder "haiku sonnet opus"` to start cheaper for read/QA-heavy work. Tune shots
  per tier with `--escalate-tries N` (default 1); disable with `--no-escalate`. (Each attempt is
  one iteration — counts against the caps.)
- **Parallelize across worktrees.** `/to-issues` treats `blocked_by` as the parallelism map and
  prints the independent batches; spin up a `valk-worktree` per batch to run them concurrently,
  then `valk-land` each back. (Sequential alternative: `afk N`.)

To make this the default for **every** session — not just Valkyrie runs — add this block to
your `~/.claude/CLAUDE.md` (it's auto-loaded once per session, so it costs nothing per turn —
unlike pasting it each time):

```md
## Cost discipline (orchestration)
- Use sonnet or haiku background agents for investigations, code-writing, and QA wherever appropriate and possible.
- Keep the main session focused on orchestration so goals are met and context stays small.
- Give each background agent a single task to limit its context overhead.
```

---

## 4. The standard workflow

### Step 1 — Start a feature

In Claude Code, just say what you want:

> Let's add a billing dashboard that shows MRR and churn.

The statusline switches to **▶ DESIGN**. The AI starts grilling you.

### Step 2 — Get grilled

The AI asks questions one at a time, with its recommended answer. Read each one. Either accept its recommendation or push back. Don't say "I don't care" — that's a smell. If you really don't care, say "you decide" and move on; after two of those in a row, it'll stop and write up.

### Step 3 — Read the PRD

Stage flips to **▶ PRD**. The AI saves a PRD to `docs/prd/<slug>.md`, then the statusline flips to **▶ REVIEW-PRD** and the AI **stops**. It reproduces the Implementation Decisions, Out of Scope, and key User Stories *inline in the conversation* — you don't have to go open the file (though the path is there if you want the full thing). This is your last chance to catch architectural drift cheaply, and the workflow will not move past it on autopilot.

To proceed you must **engage**: confirm a specific decision back in your own words ("yes — event-sourced orders, Postgres write model"), or name one to change. A bare "yes", "looks good", "lgtm", or silence is **rejected** — the gate tells you that's not engagement and asks again. If you redline, the AI revises the PRD and re-runs the gate. Only a substantive approval advances the workflow to ISSUES. This is the gate the whole tool exists for: an unread PRD poisons every issue and every line of code downstream.

### Step 4 — Approve issues

Stage flips to **▶ ISSUES**. The AI proposes a vertical-slice breakdown — each slice cuts through ALL layers (schema, API, UI, tests). Make sure:

- No slice is "implement the schema" or "build the API" — those are horizontal
- Dependencies between slices are correct (issue 0003 needs 0001 done first)
- AFK slices (no human decisions needed) are correctly marked AFK

The issues are saved to `issues/0001-*.md`, `issues/0002-*.md`, etc.

### Step 5 — Implement

Stage flips to **▶ TDD**. Two paths:

**A) HITL (you stay at the keyboard).** Just keep talking to the AI. It picks the next unblocked issue, writes one test, makes it pass, repeats. Watch for test smells (mocking internals, testing implementation).

**B) AFK (you walk away).** Run the loop:

```bash
afk 10                # 10 iterations, default claude
afk 10 --cli codex    # 10 iterations, codex
afk 10 --cli copilot  # 10 iterations, GitHub Copilot CLI
```

AFK is **interactive** — it prints the queue and the active caps, then waits at `Proceed? [y/N]` before launching anything. That gate is a deliberate safety guard against accidental cron / script launches of a multi-hour autonomous loop.

- **From a Claude chat, prefer `!afk N`** — the `!` runs the command in your own shell, so the confirmation prompt fires in your terminal and you own the loop (Ctrl-C, monitor logs, etc.).
- **From automation or when you ask Claude to launch it in the background**, pass `--no-confirm`: e.g. `afk N --no-confirm --cli codex`. Closed stdin *without* `--no-confirm` aborts on purpose — that's what stops a stray pipe or background tool call from kicking off hours of work unattended.

The loop picks issues in dependency order, spawns a fresh-context agent for each, and exits when done or the iteration cap is hit. Logs in `.claude/valk/afk-logs/`.

### Step 6 — Review the diff

When the loop is done, **review the diff like any human PR**. The PRD you read in Step 3 is your spec — does the diff match it? If not, that's a bug; reject and re-prompt.

---

## 5. When you're allowed to skip the workflow

Valkyrie is enforced *by default*, but you can override:

| Situation | What to say |
|---|---|
| Typo fix, one-line change | "Skip Valkyrie for this trivial change" — or just edit the file yourself. |
| You already have a PRD written | "/valk --skip-to issues" |
| You're hot-fixing a P0 incident | Skip to TDD. Log the bypass in your incident postmortem. |
| You're prototyping to learn — not shipping | Skip the workflow. Throw away the prototype. |

If you find yourself overriding more than once a week, you're abusing it. The friction is the product.

---

## 6. The escape hatches

- `/zoom-out` — when you're lost in unfamiliar code. Returns a map of modules + callers, in the project's domain vocabulary. Doesn't propose changes — just re-orients.
- `/refactor-spaghetti` — when you smell shallow modules or tightly-coupled code. Surfaces deepening opportunities, then drops into a grilling conversation about which to take.

Both are stage-aware — they update the statusline and restore the previous stage when they exit.

---

## 7. AFK mode — the multiplier

`afk` runs the workflow autonomously by spawning a fresh-context CLI session for each issue. Pattern borrowed from Geoffrey Huntley's "Ralph" loop and Matt Pocock's streaming variant. It works because:

1. Each issue is a vertical slice, demoable on its own — independent scope.
2. Each iteration gets a fresh context — no degradation, no leftover state.
3. The PRD + issues files ARE the agent's memory — written to disk, re-read each iteration.

### Prerequisites

- An `issues/` directory in your repo, populated by `/to-issues` (`0001-*.md`, `0002-*.md`, ...) with proper frontmatter (`status:`, `blocked_by:`).
- `claude` or `codex` CLI on your PATH.
- The PRD already written and **read by you** (`docs/prd/<slug>.md`). Do not skip this — the PRD is your spec.

### Usage

```bash
afk <max_iterations> \
  [--cli claude|codex|copilot] \
  [--max-hours <h>] \
  [--max-cost-usd <usd>] \
  [--prompt-file <path>] \
  [--allow-no-prd] [--allow-dirty] [--i-know-this-is-dangerous] [--no-confirm]
```

Examples:

```bash
afk 10                                       # iter cap 10, defaults: 4h, $50
afk 10 --max-hours 2 --max-cost-usd 25       # tighter caps
afk 50 --max-hours 12 --max-cost-usd 200     # overnight run with explicit budget
afk 10 --cli codex                           # codex instead of claude
afk 10 --cli copilot                         # GitHub Copilot CLI instead of claude
afk 5  --prompt-file pm.md                   # custom per-iteration prompt
```

### Budget caps — what stops the loop

Three independent caps run concurrently. Whichever crosses first wins; the final summary banner names the reason.

| Cap | Default | Flag | What "hit" means |
|---|---|---|---|
| Iterations | required positional `N` | — | `N` iterations completed |
| Wall-clock time | **4 hours** | `--max-hours <h>` (decimals OK) | `now - start >= h × 3600` checked at iter boundary |
| USD spend | **$50.00** | `--max-cost-usd <usd>` | cumulative cost ≥ cap, checked at iter boundary (reported cost when available, else estimated — see below) |

**Caps are checked at iteration boundaries**, never mid-iter. The current iteration always finishes cleanly, so a cap can be overshot by one iter's worth of work. That's the right trade-off — killing mid-iter would leave issues in a half-modified state.

**How cost is determined (layered).** Each iteration's log is scanned for the CLI's own `total_cost_usd` (the terminal `result` event — Anthropic's client-side estimate):

- **Reported** (`cost_source=reported`): if `total_cost_usd > 0` is present, that value is used verbatim. `rates.json` is not consulted. This is the accurate path and the default for the `claude` CLI.
- **Estimated** (`cost_source=estimated`): if the result event is absent (crash / kill / timeout) or `total_cost_usd` is `0.0`, or the CLI is `codex` (no cost field), cost is recomputed from `usage` events × per-million-token rates in `~/.claude/valkyrie/rates.json`. **`rates.json` is placeholder data and deliberately overestimates** — fine as a conservative cap, not a real bill.

The per-iter line and the final summary tell you which basis was used (`[reported]` / `[estimated]`, and a `cost basis:` line in the summary). If the summary says `estimated from rates.json (placeholder — not real $)`, the dollar figure is a safety-rail number, not your invoice.

> **Subscription vs API — read this before quoting a dollar figure.** If engineers run `claude` via a Claude **subscription** (Pro/Max/Team) rather than an API key, `total_cost_usd` is a *notional API-equivalent* value for usage that was **not billed per-token at all** (the AFK session shows `apiKeySource: none`). In that mode neither the reported nor the estimated number is money that left the company. The real constraint is **rate-limit consumption** — AFK competing with engineers' interactive sessions for the shared 5-hour / weekly limits. When reporting AFK economics for a subscription team, frame it as "consumed X% of our rate-limit budget and produced N PRs," not "spent $X." Quoting a dollar figure for subscription usage is a category error that will mislead the rollout decision.

**This is now automatic — `cost_mode`.** AFK no longer just warns; it presents the right unit:

- **`dollars`** — per-iter line shows `spend $X / $Y`, summary shows `spend:` + `cost basis:`. Use this on the **commercial API account** (real per-token billing).
- **`tokens`** — per-iter line shows `tokens 2.34M (cap proxy $X / $Y) [subscription]`, summary shows `tokens:` + `cap proxy:` + `cost basis: token counts — real constraint is rate limits`. Use this for **personal Pro/Max** runs where dollars are notional.

Selection (`VALK_COST_MODE` env var):

| Value | Behavior |
|---|---|
| unset / `auto` (default) | `apiKeySource: none` → **tokens**; any other value (API key) or absent → **dollars**. Real `claude` always emits `apiKeySource`, so auto is correct in practice. |
| `tokens` | force token display regardless of auth |
| `dollars` | force dollar display regardless of auth |

Set it per-machine in your shell rc. **Commercial-API teammates**: leave unset (auto detects the API key → dollars) or `export VALK_COST_MODE=dollars` to be explicit. **Personal Pro/Max**: `export VALK_COST_MODE=tokens` so notional dollars never mislead you. The `$` cap (`--max-cost-usd`) is unchanged in both modes — in token mode it remains a proxy ceiling that still stops runaway loops; only the *display* differs.

**Hard refusals** (loop exits non-zero) when budget tracking can't be trusted:
- Estimated path only: `rates.json` missing or malformed → fix and re-run `./install.sh`. (The reported path does not need `rates.json`.)
- Estimated path only: an iteration emits a model not in `rates.json` (after stripping `-YYYYMMDD` and `[…]` context suffixes) → add the model to `rates.json`, commit, `./install.sh`.
- An iteration's CLI exits non-zero with no `usage` events AND no reported cost → loop exits with `reason: cost tracking failed` and names the offending log file.

A clean exit (code 0) with no `usage` events is treated as $0 and the loop continues — that's a legitimate no-op.

### Pre-flight guardrails

Before the loop starts, four gates run. Each one turns a "you should" SOP rule into a "you can't unless" gate. Each has its own override flag — pass the flag and you've explicitly named the risk you're accepting.

**Headline guarantee:** *"afk refuses to start unless you have a PRD, your tree is clean, you're not in a known-dangerous directory, and you've eyeballed the issue queue."*

| Gate | What it checks | Failure message | Override |
|---|---|---|---|
| **PRD exists** | `docs/prd/` contains at least one non-empty `.md` file | `no PRD found in docs/prd/ (run /to-prd, or pass --allow-no-prd to override)` | `--allow-no-prd` |
| **Working tree clean** | `git diff --quiet` AND `git diff --cached --quiet` both return 0 | `uncommitted changes in working tree (commit/stash, or pass --allow-dirty)` | `--allow-dirty` |
| **Path not dangerous** | `$REPO` (case-insensitive) does not contain any of the keywords listed below | `working directory looks dangerous (matched '<keyword>') — pass --i-know-this-is-dangerous to proceed` | `--i-know-this-is-dangerous` |
| **Confirmed by you** | Stdin reads `y/Y/yes/YES` after the queue summary prints | `aborted at confirmation prompt.` (on stderr) | `--no-confirm` |

The dangerous-path keyword list is hardcoded in `scripts/afk` (auditable in PR diffs):

```
credentials  production  migrations  migration  terraform  payment  billing
secrets      .env        infra       auth       prod
```

Ordered longest-first so the failure message names the most specific match (`production` rather than `prod` for `/tmp/production-cfg/`).

**Non-git workdirs:** the dirty-tree check is skipped with a one-line warning (`git: not a repo, dirty-tree check skipped`) rather than blocking. Existing non-git usage continues to work.

**Multi-gate failures collect into a punch list** — each failed gate adds one line; the loop exits after reporting all of them so you can fix everything in one pass:

```
afk: cannot start — fix the following:
  ✗ no PRD found in docs/prd/ (run /to-prd, or pass --allow-no-prd to override)
  ✗ uncommitted changes in working tree (commit/stash, or pass --allow-dirty)
  ✗ working directory looks dangerous (matched 'auth') — pass --i-know-this-is-dangerous to proceed
Queue would have been: 3 issues. Re-run after fixing.
```

The "Queue would have been" hint lets you verify the queue is what you expected even when the run is blocked.

**Overrides stack:** to run truly unattended in a sensitive context (e.g. CI in a `prod-` repo), you must pass each waiver flag explicitly:

```bash
afk 10 --no-confirm --allow-dirty --i-know-this-is-dangerous --allow-no-prd
```

This verbosity is intentional — the friction is the product. If you find yourself stacking all four every run, ask whether the gates are wrong or your workflow is.

### Per-iteration progress and final summary

After every iteration, one cumulative status line lands on stdout:

```
iter 3/10 done | elapsed 1h12m / 4h00m | spend $4.50 / $50.00 (~9%)
```

When the loop exits — for any reason, including Ctrl-C — a structured summary banner prints:

```
afk: stopped — reason: cost cap hit
  iterations:    7 / 10
  elapsed:       2h41m / 4h00m
  spend:         $50.04 / $50.00
  issues done:   5
  issues stuck:  2
  logs:          .claude/valk/afk-logs/
  cost history:  .claude/valk/afk-cost-history.csv
```

The `reason:` field takes one of: `no more issues`, `iteration cap hit`, `time cap hit`, `cost cap hit`, `cost tracking failed`, `interrupted`.

### CSV cost history

Each completed iteration appends one row to `<repo>/.claude/valk/afk-cost-history.csv`:

```
timestamp,iter,model,input_tokens,output_tokens,cache_write_5m,cache_write_1h,cache_read,cost_usd,cumulative_usd,cost_source,pr_url,exit_reason_for_run
```

`cost_source` is `reported` (CLI's own `total_cost_usd` — accurate) or `estimated` (recomputed from placeholder `rates.json`). When analyzing spend across runs, filter on this: only `reported` rows are real-dollar figures, and only under API-key billing (see the subscription caveat above).

The file accumulates across runs (header on first creation, append thereafter). Only the **last row of each run** has `exit_reason_for_run` populated; earlier rows from the same run leave it empty. After a few sprints of use, this is the data you tune your defaults on — rather than guessing whether `--max-cost-usd 50` is too tight or too generous.

### What each iteration does

1. **Pick the next unblocked issue** — scans `issues/*.md` for the first one with `status: open` whose `blocked_by:` deps are all `status: done`.
2. **Set the stage** — `python3 stage.py set afk`. Statusline now shows ▶ AFK.
3. **Spawn the CLI** with a generated prompt that says: invoke `/valk`, go to the `tdd` skill, implement this slice red-green-refactor, mark `status: done` when acceptance criteria pass, then exit.
4. **Stream output** to the terminal AND to `<repo>/.claude/valk/afk-logs/iter-N-TIMESTAMP.log`.
5. **Sanity-check** the issue after the CLI exits.
   - If `status: done` → great, next iteration picks the next issue.
   - If still `status: open` → the loop marks it `status: stuck` and moves on. Stuck issues are skipped on subsequent iterations; you'll review them by hand.
6. **Repeat** until: max iterations hit, no unblocked issues left, or you Ctrl-C.

When the loop ends (any reason), the stage is cleared back to idle.

### The AFK audit log (telemetry)

Because no human watches an AFK run, it leaves a trail you can review afterward. While a
Valkyrie stage is active, a `PostToolUse` hook (`valk-telemetry.sh`) records every file
Read/Edit (path + line count) to `<repo>/.claude/valk/telemetry/<session>.jsonl`. After each
iteration — and in the final banner — `afk` summarizes it:

```
telemetry: 14 files / 2,341 lines crawled | 2 edited without reading
```

- **"edited without reading"** is a proxy for inference: the agent changed a file it never
  opened that session. It's a signal to eyeball in review, not proof of a bug.
- It records the **tool-call trail, not the model's reasoning** — chain-of-thought isn't
  observable to hooks. Don't read more into it than "what files did it touch, and did it look
  before it leapt."
- It only logs during **active stages**, so idle/ad-hoc sessions don't generate noise.
- This is a **post-hoc audit** layer by design — there are deliberately no real-time drift
  alarms (they'd be fuzzy and noisy). Review the JSONL or the run summary; for deeper auditing
  the integration suite's `trace.jsonl` still captures full tool traces.

### Watching it run / interrupting

- Output streams live to your terminal — you can follow along.
- Per-iteration logs accumulate in `.claude/valk/afk-logs/`. Tail the latest with `tail -f .claude/valk/afk-logs/iter-*.log | head` (or just `ls -lt` to find the newest).
- Ctrl-C is safe: a trap clears the stage marker so your statusline doesn't lie. The in-progress log file is preserved.

### Recommended cadence

- **Day 1 (HITL):** human-in-the-loop through DESIGN → PRD → ISSUES. The AI cannot do this part — it doesn't know what you actually want.
- **Day 1 evening:** kick off `afk N` where N ≥ the number of issues you expect to land overnight. Walk away.
- **Day 2 morning:** read the per-iteration logs, review the diff, reject anything off-spec. Remaining open or stuck issues are HITL — pair with the AI through them.

### Hard rules

- **Don't run `afk` against issues you haven't backed with a PRD you read.** That's how you ship surprises.
- **Don't run it on shared infrastructure code unattended.** The loop uses `--dangerously-skip-permissions` (claude) / `--full-auto` (codex), so the agent runs any tool without asking. Use it on contained features — not auth, payments, migrations, or production config.
- **Don't use `--prompt-file` to bypass TDD.** The default prompt enforces red-green-refactor. If you override it, you're explicitly opting out of the safety net.
- **Don't loop overnight in a repo with uncommitted changes you care about.** Commit or stash first; the agent may modify them.

### Common stuck states

| Symptom | Cause | Fix |
|---|---|---|
| `error: no issues/ directory` | Skipped `/to-issues` | Run the workflow through ISSUES first. |
| Same issue keeps getting marked `stuck` | Acceptance criteria too vague, or it's actually HITL | Tighten the criteria. Or change the issue's `type:` to `HITL` and pair through it. Set `status: open` to re-include. |
| Loop runs but no commits land | Permission walls or no git in the repo | Check the iter log. Confirm `--dangerously-skip-permissions` is honored. Confirm `git` works in the repo. |
| Agent burns iterations on the wrong issue | `blocked_by:` is wrong or missing | Edit the issue frontmatter. Use issue IDs (e.g., `blocked_by: [0001, 0003]`). |
| Stage marker stuck on `afk` after Ctrl-C | Trap didn't fire (process killed -9) | `python3 ~/.claude/valkyrie/stage.py clear`. |
| Run aborts with `cost tracking failed` | CLI crashed without emitting `usage` events, or unknown model | Open the named log file. If it's a real crash, fix the underlying issue and re-run. If it's a new model, add it to `scripts/rates.json` and re-run `./install.sh`. |
| Cost numbers feel wrong | Placeholder rates still in place (issue 0006 unmerged), or rates outdated | Update `scripts/rates.json` against the official pricing pages, commit, `./install.sh`. |
| `afk: cannot start — fix the following:` | Pre-flight gate(s) failed | Read the punch list. Each line names the gate and its override flag. Either fix the underlying issue or pass the named override. |
| You keep having to pass `--allow-dirty` | Working tree always dirty when you launch | Commit your work. The gate exists because the agent will modify uncommitted changes. If you legitimately need to keep changes, stash first. |
| You keep having to pass `--i-know-this-is-dangerous` | Repo path matches a hardcoded keyword (e.g. `payment-svc`) | Verify the match makes sense (it's a real production-adjacent repo) and pass the flag deliberately. If it's a false positive on a safe repo, edit `DANGEROUS_KEYWORDS` in `scripts/afk` and re-install. |
| Confirmation prompt aborts immediately when piping | Stdin is empty / non-TTY | Pass `--no-confirm` for non-interactive runs. The queue summary still prints to stdout for CI logs. |

### Resuming after stuck issues

```bash
# 1. Find them
grep -l 'status: stuck' issues/*.md

# 2. For each: review the iter log, fix the issue file, set status back to open
# 3. Re-run the loop
afk 5
```

---

## 8. Failure modes & how to recover

| Smell | Likely cause | Fix |
|---|---|---|
| AI keeps suggesting code while statusline shows ▶ DESIGN | You skipped grilling, jumped to "build it" | Quit the chat. Restart with "let's design X" — make yourself sit through the grill. |
| PRD is bland, doesn't reflect your decisions | The grilling session was too short | Re-run `/grill-with-docs` with deeper questions. Aim for 15+ exchanges. |
| AI writes 5 tests before any implementation | Horizontal slicing — anti-pattern | Stop. Tell it: "one test, one impl. Tracer bullet." |
| Tests break every time you refactor internals | Tests are coupled to implementation | Read `/tdd` SKILL.md. Tests should use public interfaces only. |
| `afk` keeps marking issues "stuck" | Acceptance criteria too vague, or HITL slice was mismarked AFK | Re-read the issue. Either tighten criteria or change `type: HITL`. |
| Hook fires on prompts that aren't real builds | Trigger regex too aggressive | Edit `~/.claude/hooks/valk-guard.sh`, tighten `TRIGGER_RE`. |
| Hook never fires when it should | Stage stuck non-idle, or settings.json malformed | `python3 ~/.claude/valkyrie/stage.py clear`; `jq . ~/.claude/settings.json`. |

---

## 9. What success looks like

- A senior engineer ships 3 features in the time they used to ship 1, because the AI does the implementation while they sleep.
- A junior engineer ships a feature without architectural drift, because the PRD enforces the senior engineer's pattern.
- Code review focuses on **the PRD**, not the diff — the diff is just an honest implementation of the spec.
- "I don't trust AI-written code" stops being a thing said in PR review.

---

## Running multiple flows in parallel (worktree-per-flow)

Want three terminals chewing through issues at once on the same project?
**Supported — but give each flow its own git worktree, never share one
checkout.**

A shared checkout cannot be made safe by Valkyrie code: two flows share one
index, one `HEAD`, one set of files, so commits get cross-swept, half-written
files redden the other's test run, and the stage marker is clobbered. That
residue is irreducible without isolation. So isolate:

```bash
valk-worktree feature-a        # creates ../<repo>-feature-a on valk/feature-a
cd ../<repo>-feature-a         # this terminal is now isolated — run /valk here
# … flow runs to done on its own valk/feature-a branch …
valk-land feature-a                           # integrate-back (supported) — or merge/PR by hand
valk-worktree --remove feature-a              # cleanup (drops the merged branch)
```

## Loop-back on mid-stream requirement change

When a requirement actually changes after DESIGN — a constraint surfaces at PRD, a new in-scope item appears at ISSUES, a real-world fact invalidates a slice at TDD — the flow rewinds without throwing prior work away.

**The orchestrator drives this**, not the user. `/valk` watches every downstream stage for change signals (explicit re-casts like *"scrap that"* / *"actually instead of X"*, statements that contradict a recorded PRD decision, new in-scope items not in the PRD) and on detection asks a single yes/no:

> "That sounds like a change to [decision]. Loop back to [stage] to amend, or is this clarification of existing scope?"

On confirm, the agent invokes the mechanical action itself:

```bash
valk-revisit <design|prd|issues> "<one-line summary>"
```

This validates the target is upstream of the current stage, writes a brief to `docs/changes/<ts>-<slug>.md`, and rewinds the stage marker. The re-entered skill (`grill-with-docs` / `to-prd` / `to-issues`) detects the new note and **amends its artifact in place** — `docs/prd/<slug>.md` gets an updated section plus a `Δ <date>: …` change-log entry; obsoleted issues get `status: obsolete` (never deleted); new issues from the change cite `from_change: <note-path>`. No artifact is regenerated from scratch.

**Hard rule:** TDD loop-back amends scope and re-routes only the affected slice — it never `rm`s or `git checkout`s a test file. Past tests are historical record.

You can also run `valk-revisit` directly in your shell as an escape hatch — useful when you want to record a change proactively before the agent notices.

- **One `valk-worktree <name>` per terminal.** Each flow works on its own
  `valk/<name>` branch in its own checkout. Concurrency stops being a hazard.
- **Integrate-back: `valk-land <name>` (supported) or manual.** `valk-land`
  lands the branch the way the repo already handles PRs: if
  `.claude/valk-config.md` sets a `pr_skill`, it steps aside and that skill
  owns the PR (no double-push); otherwise it rebases `valk/<name>` onto fresh
  `origin/main`, runs the repo's `test_skill` gate (red → abort, nothing
  pushed; no signal → `--force` required), fast-forwards `main`, and
  sync-safe pushes — **never** force-pushing, aborting cleanly on conflict
  with the branch + worktree untouched. `--clean` also tears down the
  worktree (refuses from inside it). The manual `git merge`/PR path stays
  fully valid; `valk-land` is the ergonomic default, not a replacement.
  *(ADR-0001 honest limit: it makes the merge work ergonomic and race-free,
  it does not eliminate conflicts.)*
- **Cleanup:** `valk-worktree --remove <name>` removes the worktree and drops
  the branch *only if merged* (unmerged branches are kept — no lost work).
- The prompt guard nudges you toward `valk-worktree` if you're still in the
  shared checkout, and **goes silent on its own** once you're in a worktree —
  it never nags the isolated workflow.

`valk-worktree` is pure git and works with no setup hook. Repos that want a
freshly-created worktree to come up build-ready (deps installed, free port
chosen) can drop an optional `.valk-worktree-setup` — see the workflow doc.

---

## 10. FAQ

**Q: Do I have to use this for every prompt?**
A: For anything that produces production code, yes. For chat, debugging, ad-hoc exploration — no.

**Q: What if my codebase doesn't have GitHub Issues?**
A: Valkyrie's `/to-issues` saves to local `issues/*.md` files by default. GitHub integration is optional.

**Q: What if I'm working in a repo I don't own and can't add `docs/prd/`?**
A: PRDs save to `~/.claude/valkyrie/prd-cache/<repo>/` as a fallback.

**Q: Can I customize the workflow?**
A: Yes. The skills are just markdown — edit them in `~/.claude/skills/<name>/SKILL.md`.

**Q: What if Claude Code isn't loading the skill?**
A: Run `ls ~/.claude/skills/` to confirm the symlinks exist. Restart Claude Code. If still broken, re-run `./install.sh`.

**Q: The hook is annoying me — can I turn it off without losing the workflow?**
A: Yes. Remove the `hooks` block from `~/.claude/settings.json` and restart. The skill still works via `/valk` or its soft auto-trigger.

---

## 11. Rolling this out to your org

The workflow only delivers 5x if more than one person uses it. The friction is also social — engineers who are halfway in, half out, will undermine the discipline. Treat the rollout as a change-management exercise, not a tool install.

### Phase 0 — Pre-rollout gate (run before pilot)

Before letting anyone outside the maintainer team install Valkyrie, the maintainer runs the full test pyramid and the manual smoke. If any layer fails, fix it before continuing.

```bash
# Layer 1 — stub-based unit suite. Free, deterministic. Must pass 6/6.
bash test/run-tests.sh

# Layer 2 — real-Claude integration suite. ~$1 per full run.
# Captures hook traces to test/integration/last-run/<scenario>/reports/trace.jsonl
# for offline audit.
bash test/run-integration-tests.sh

# Layer 3 — manual interactive smoke. ~15 min, ~$2–5.
# Run both variants in test/integration/MANUAL-SMOKE.md (no config + missing-PR-skill).
```

After Layer 2, review the trace files for unexpected tool calls (e.g. file modifications outside the issue's named files, or subagent spawns the slice didn't require). Anything surprising → file an issue and block the pilot until resolved. Anything expected but unfamiliar → note it for the lunch-and-learn.

### Phase 1 — Pilot (week 1)

- **Pick 3–5 engineers** who already write good PRDs and complain about AI-generated slop. They'll be your evangelists.
- They run the install + hook on their own machines.
- They commit to using Valkyrie for **every non-trivial prompt for one full sprint** and log overrides in a shared note.
- Goal: produce 5–10 PRDs and a public diff showing the workflow's value (e.g. "this PR shipped in 2 hours; without the PRD, the same task took me 6 hours last sprint").

### Phase 2 — Lunch-and-learn (week 2)

- 30-minute live demo: pilot engineer takes a real ticket from idle → DESIGN → PRD → ISSUES → TDD in front of the team.
- Show the statusline. Show the hook firing. Show the AI refusing to skip stages.
- Hand out the **one-page cheat sheet** (section 12). Pin it in #engineering.
- Open the floor: "what would break this for your workflow?" — collect objections, fold them into the FAQ.

### Phase 3 — Default-on (weeks 3–4)

- Add the install step to your **onboarding checklist**: new hire's day-1 setup includes `./install.sh` plus the hook in `~/.claude/settings.json`.
- Add a CI check: PRs that touch >50 lines of code without a corresponding `docs/prd/<slug>.md` get auto-labeled `needs-prd`. (Soft enforcement — reviewers decide.)
- Make PRD existence part of code review: "where's the PRD?" becomes a default question on any non-trivial PR.

### Phase 4 — Measure & iterate (week 5+)

Track three numbers in a shared dashboard:

1. **PRDs/week** — leading indicator of adoption
2. **Override rate** — % of build prompts that bypass the workflow. >20% means the rules are wrong, not the engineers.
3. **Cycle time, idea → prod** — the headline number. Valkyrie should compress this. If it doesn't after a month, the workflow is failing your team's actual constraints — fix the workflow, don't blame people.

### Killer objections to expect, with answers

| Objection | Answer |
|---|---|
| "This adds friction to fast tasks" | The friction is the product. For genuinely fast tasks, use the skip-to override. The hook lets `trivial change` and one-line fixes through. |
| "I already write good PRDs in Notion" | Great — `/valk --skip-to issues` and paste your PRD. The workflow flexes. |
| "It's slower for me personally" | Maybe at first. Measure cycle time over a sprint, not a prompt. |
| "AI-written PRDs feel low-effort" | The PRD is a *transcript* of the grilling session — your decisions, written up. If it feels low-effort, the grilling was too short. |
| "Senior engineers won't use it" | Then it dies. Get senior buy-in first; juniors will follow. Don't roll it out to juniors first. |

### Anti-patterns to watch for

- **PRD theater** — engineers run the workflow but skim the PRD. Defeats the purpose. Code review gates on PRD-diff alignment fix this.
- **Override sprawl** — every prompt becomes "skip valk for this trivial change." Audit overrides weekly. If one engineer overrides >50%, pair with them and find out why.
- **AFK without review** — running `afk` overnight and merging without reading the diff. This is how you ship bugs at 5x. The SOP is explicit: review the diff.
- **One-person rollout** — if only the champion uses it, it's a hobby, not a SOP. Either get the team in or shelve the project.

### Success criteria for org adoption

After one quarter:

- 80%+ of non-trivial PRs have a linked PRD.
- Override rate < 15%.
- New hires report onboarding to the codebase faster (because PRDs explain *why* code exists).
- At least one engineer has shipped an AFK feature unattended and you trust the diff.

If you hit those, scale up. If you don't, the workflow needs surgery — not the people.

---

## 12. One-page cheat sheet for your monitor

```
╭─────────────────────────────────────────────╮
│  Valkyrie — every coding prompt        │
├─────────────────────────────────────────────┤
│  1. "Let's build X" → ▶ DESIGN              │
│     answer questions one at a time          │
│  2. read the PRD → ▶ PRD                    │
│     edit anything wrong                     │
│  3. approve issues → ▶ ISSUES               │
│     vertical slices only                    │
│  4. afk 10  → ▶ AFK                   │
│     review the diff in the morning          │
├─────────────────────────────────────────────┤
│  Lost?      /zoom-out                       │
│  Tangled?   /refactor-spaghetti             │
│  Override?  /valk --skip-to <stage>   │
│  Hook on?   ~/.claude/hooks/valk-*.sh │
│  AFK gate?  --allow-no-prd / --allow-dirty  │
│             --i-know-this-is-dangerous      │
│             --no-confirm                    │
╰─────────────────────────────────────────────╯
```
