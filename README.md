# Valkyrie

A hard-enforced, design-first AI coding workflow for Claude Code (and Codex CLI). Forces every coding request through the same four stages — DESIGN → PRD → ISSUES → TDD — and shows you which one you're in via a statusline that lives at the bottom of your terminal.

The goal: **5x your engineers without overcomplicating things** by making them think before they prompt and review a real PRD before they merge.

## What you get

- **A stage-aware statusline** — adapted from [moonbox3/ccstatusbar](https://github.com/moonbox3/ccstatusbar). Shows context %, model, git branch, and a colored ▶ STAGE pill.
- **An orchestrator skill — `/valk`** — refuses to write code unless you've been through DESIGN, PRD, and ISSUES first.
- **The four core workflow skills**, adapted from [mattpocock/skills](https://github.com/mattpocock/skills):
  - `/grill-me` — interview you relentlessly about your design
  - `/to-prd` — synthesize the grilling into a PRD
  - `/to-issues` — break the PRD into independently-grabbable vertical slices
  - `/tdd` — implement each slice red-green-refactor
- **Two escape-hatch skills**: `/zoom-out` (re-orient on unfamiliar code) and `/refactor-spaghetti` (find deepening opportunities in tangled code).
- **A `ralph-afk` loop runner** — chew through issues autonomously while you sleep, with `--cli claude` or `--cli codex`. Inspired by the Ralph pattern from Geoffrey Huntley and Matt Pocock.

## Install

```bash
git clone https://github.com/BunnyDAO/Valkyrie.git ~/valkyrie
cd ~/valkyrie
./install.sh
```

That's it. It will:
- Symlink the skills into `~/.claude/skills/`
- Copy the statusline + stage helper into `~/.claude/valkyrie/`
- Patch `~/.claude/settings.json` to use the statusline
- Symlink `ralph-afk` into `~/.local/bin/`

Restart Claude Code to pick up the new statusline.

### Optional: full ccstatusbar usage segments

If you want the OAuth-backed `5h:13%` and `wk:25%` segments from ccstatusbar, install it alongside:

```bash
curl -fsSL https://raw.githubusercontent.com/moonbox3/ccstatusbar/v1.0.1/install.sh | bash
```

Valkyrie's statusline auto-detects `~/.claude/ccstatusbar.py` and delegates to it for those segments, then appends the STAGE pill.

## How to use

### Standard flow

Just describe what you want to build:

> "Let's add a billing dashboard."

`/valk` activates automatically. The statusline switches to **▶ DESIGN** and Claude starts grilling you. When you've resolved the decision tree, it moves to **▶ PRD**, then **▶ ISSUES**, then **▶ TDD**.

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
ralph-afk 10                  # 10 iterations using claude (default)
ralph-afk 10 --cli codex      # same but using codex
```

The loop picks the next unblocked issue, spawns the CLI with a fresh context, and lets it implement the slice. The statusline shows **▶ AFK**. Logs land in `.claude/valk/afk-logs/`.

### Escape hatches

- `/zoom-out` — when you're lost in unfamiliar code
- `/refactor-spaghetti` — when the architecture needs deepening

Both update the stage and restore it when done.

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
│   ├── grill-me/              # design interrogation
│   ├── to-prd/                # PRD synthesis
│   ├── to-issues/             # vertical-slice issue breakdown
│   ├── tdd/                   # red-green-refactor
│   ├── zoom-out/              # re-orient on unfamiliar code
│   └── refactor-spaghetti/    # find deepening opportunities
└── scripts/
    └── ralph-afk              # autonomous loop, claude or codex
```

## Credits

- Statusline: [moonbox3/ccstatusbar](https://github.com/moonbox3/ccstatusbar)
- Skills: [mattpocock/skills](https://github.com/mattpocock/skills)
- Ralph pattern: Geoffrey Huntley, popularized by Matt Pocock at [aihero.dev](https://www.aihero.dev/)
