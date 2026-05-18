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

Full format spec: [`docs/valk-config-format.md`](docs/valk-config-format.md).

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
│   ├── zoom-out/              # re-orient on unfamiliar code
│   └── refactor-spaghetti/    # find deepening opportunities
└── scripts/
    └── afk              # autonomous loop, claude or codex
```

## Credits

- Statusline: [moonbox3/ccstatusbar](https://github.com/moonbox3/ccstatusbar)
- Skills: [mattpocock/skills](https://github.com/mattpocock/skills)
- Ralph pattern: Geoffrey Huntley, popularized by Matt Pocock at [aihero.dev](https://www.aihero.dev/)
