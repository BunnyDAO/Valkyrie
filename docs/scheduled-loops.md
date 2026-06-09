# Scheduled loops — running `afk` on a clock (outside HiveOp)

The "loop engineering" idea everyone's talking about — *design a loop that prompts
the agent, schedule it, let it run while you sleep* — already works today with
`afk` + your OS scheduler. **No hosted service required.**

> **Where this runs:** entirely on **your** machine or **your** CI, in **your**
> repo. HiveOp (crew.hiveop.io) is only where you *author and forge* the crew;
> once forged, the `.claude/` bundle + `valk-config.md` live in your repo and `afk`
> runs them on your schedule. HiveOp is **not** in the loop at runtime — nothing
> calls back to it. (A hosted "run it in our cloud" scheduler is a separate, not‑
> yet‑built product direction; this guide is the local/CI path, which covers the
> real use cases for free.)

## The on-ramp

1. **Author + forge** a crew in HiveOp (or hand-write `issues/` + an optional
   `.claude/valk-config.md`). Forge drops the bundle into your repo.
2. **Break the work into `issues/`** (via `/valk` → `to-issues`, or by hand). `afk`
   chews through unblocked issues one at a time.
3. **Run `afk` on a schedule.** That's the loop.

`afk` already embodies the discipline the articles preach: a **fresh, single-issue
session per slice** (context reset every iteration, ralph-style), an **escalation
ladder** (sonnet → opus by default), and **git as durable memory** — it commits per
issue, so a crash or timeout just leaves the issue `open` and the next run picks it
up. Crash-durable at issue granularity, no extra state store.

## The one rule: make it halt

Scheduled autonomous loops are where the billing-surprise stories come from. `afk`
gives you the three hard stops — **use them, especially the cost ceiling:**

| Stop | Flag | Notes |
|---|---|---|
| Max iterations | `afk <N>` (the count arg) | Process at most N issues this run. |
| Wall-clock | `--max-hours <h>` | Stop starting new issues past the deadline. |
| **Dollar ceiling** | `--max-cost-usd <$>` | **The load-bearing guard.** Hard-stop on spend. |

Defaults can also live in `valk-config.md`'s `loop:` run-caps block
(`max_iters` / `max_hours` / `max_cost_usd`); **CLI flags override them.** Per-pair
inner-loop budgets (`budget_mode: valkyrie-usd`) are advisory soft ceilings — the
crew-level `--max-cost-usd` is the real backstop. (Mechanical *no-progress*
detection is enforced in the arena reference runtime; in `afk` the cost/iter/hours
caps plus the critic's `stop` verdict are your guards.)

> **`--no-confirm` is mandatory for unattended runs.** With no TTY (cron, CI),
> `afk` deliberately aborts at the `Proceed? [y/N]` gate unless you pass
> `--no-confirm`. That guard exists precisely so a stray cron line can't silently
> launch a multi-hour spend.

## cron (your machine)

```cron
# Every night at 02:00 — up to 10 unblocked issues, hard cost + time caps.
0 2 * * *  cd /path/to/your/repo && /path/to/valkyrie/scripts/afk 10 \
             --no-confirm --max-cost-usd 25 --max-hours 4 >> .afk/nightly.log 2>&1
```

Notes:
- `cd` into the repo first — `afk` operates on the current repo's `issues/`.
- Make sure the agent CLI (`claude`, or `--cli codex`) and `ANTHROPIC_API_KEY` are
  on cron's environment (cron has a minimal env; source your profile or set them in
  the crontab).
- Tee to a log — unattended runs you'll want to read in the morning.

## GitHub Actions (laptop closed)

```yaml
name: nightly-afk
on:
  schedule:
    - cron: '0 2 * * *'      # 02:00 UTC
  workflow_dispatch: {}       # let you trigger it by hand too
permissions:
  contents: write             # afk commits per issue
jobs:
  afk:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install agent CLI + Valkyrie
        run: |
          # npm i -g @anthropic-ai/claude-code   (or your CLI of choice)
          # install Valkyrie scripts on PATH (see install.sh)
          echo "install step depends on your setup"
      - name: Run afk
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: afk 10 --no-confirm --max-cost-usd 25 --max-hours 4
```

The runner is ephemeral, so git is the only state that survives — which is exactly
how `afk` already works. Push happens per issue (or via your `pr_skill` if
configured), so progress accrues on the branch even if a later issue fails.

## Parallel chains (optional)

Independent issue chains can run concurrently without colliding — give each its own
checkout with **`valk-worktree <name>`** and integrate with **`valk-land <name>`**.
Schedule one `afk` per worktree if you want overnight parallelism. (See
`valk-worktree-setup-format.md`.)

## What this is *not*

- It's **not** a hosted service — you own the runner, the keys, and the bill.
- It's **not** continuous orchestration (loops supervising loops). `afk` is a
  single sequential worklist runner. That's a feature: it's predictable and easy to
  cap.
- For **interactive** planning stages (DESIGN/PRD), don't schedule — those are
  human-gated by design. `afk` is for the autonomous TDD lane.
