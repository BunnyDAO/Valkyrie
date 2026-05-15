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
| UserPromptSubmit hook | `~/.claude/hooks/valk-guard.sh` | Global, runs every prompt | Hard enforcement — see §2. |
| Settings glue | `~/.claude/settings.json` | Global | Wires the statusline + hook. Patched in place. |
| Stage marker | `<repo>/.claude/valk/stage` | Per-project | Current workflow stage. Each repo tracks its own. |
| AFK logs | `<repo>/.claude/valk/afk-logs/` | Per-project | One log file per `afk` iteration. |
| PRDs | `<repo>/docs/prd/<slug>.md` | Per-project | Output of `/to-prd`. |
| Issues | `<repo>/issues/0001-*.md` | Per-project | Output of `/to-issues`. Vertical slices with frontmatter. |
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

---

## 3. The four stages — what they're for

| Stage | Skill | What you do | What you DON'T do |
|---|---|---|---|
| **DESIGN** | `/grill-with-docs` | Answer the AI's questions about the plan. One question at a time. | Skip ahead. Outsource thinking. |
| **PRD** | `/to-prd` | Read the PRD it generates. ~5 minutes. Edit anything wrong. | Treat the PRD as a formality. |
| **ISSUES** | `/to-issues` | Confirm the vertical-slice breakdown. Adjust dependencies. | Accept thick slices that touch one layer only. |
| **TDD** | `/tdd` | Watch the red-green-refactor loop. Catch test smells. | Let it write all tests upfront — that's horizontal slicing. |

**The DESIGN stage is where the value compounds.** If you spend 20 minutes there, you'll save 2 hours in TDD because the AI isn't guessing what you want.

---

## 4. The standard workflow

### Step 1 — Start a feature

In Claude Code, just say what you want:

> Let's add a billing dashboard that shows MRR and churn.

The statusline switches to **▶ DESIGN**. The AI starts grilling you.

### Step 2 — Get grilled

The AI asks questions one at a time, with its recommended answer. Read each one. Either accept its recommendation or push back. Don't say "I don't care" — that's a smell. If you really don't care, say "you decide" and move on; after two of those in a row, it'll stop and write up.

### Step 3 — Read the PRD

Stage flips to **▶ PRD**. The AI saves a PRD to `docs/prd/<slug>.md`. **Open it. Read it once.** Edit anything wrong. This is your last chance to catch architectural drift cheaply.

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
```

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
  [--cli claude|codex] \
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
afk 5  --prompt-file pm.md                   # custom per-iteration prompt
```

### Budget caps — what stops the loop

Three independent caps run concurrently. Whichever crosses first wins; the final summary banner names the reason.

| Cap | Default | Flag | What "hit" means |
|---|---|---|---|
| Iterations | required positional `N` | — | `N` iterations completed |
| Wall-clock time | **4 hours** | `--max-hours <h>` (decimals OK) | `now - start >= h × 3600` checked at iter boundary |
| Estimated USD spend | **$50.00** | `--max-cost-usd <usd>` | cumulative parsed-token cost ≥ cap, checked at iter boundary |

**Caps are checked at iteration boundaries**, never mid-iter. The current iteration always finishes cleanly, so a cap can be overshot by one iter's worth of work. That's the right trade-off — killing mid-iter would leave issues in a half-modified state.

**Estimated, not billed.** Cost is computed by parsing `usage` events from claude `stream-json` output and multiplying by per-million-token rates from `~/.claude/valkyrie/rates.json`. If Anthropic gives you tier discounts or volume pricing, the real bill diverges from our estimate. Treat the cap as a safety rail, not a precise meter.

**Hard refusals** (loop exits non-zero) when budget tracking can't be trusted:
- `rates.json` missing or malformed → fix and re-run `./install.sh`.
- An iteration emits a model name not in `rates.json` (after stripping the `-YYYYMMDD` suffix) → add the model to `rates.json`, commit, `./install.sh`.
- An iteration's CLI exits non-zero with no `usage` events → loop exits with `reason: cost tracking failed` and names the offending log file.

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
timestamp,iter,model,input_tokens,output_tokens,cache_write_5m,cache_write_1h,cache_read,cost_usd,cumulative_usd,exit_reason_for_run
```

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
