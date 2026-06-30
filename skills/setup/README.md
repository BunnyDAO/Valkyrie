# valkyrie:setup

One-time post-install wiring for Valkyrie. Run this after installing Valkyrie from the Claude Code marketplace.

## What it does

Copies stage helpers, statusline, and hook scripts into your Claude home directory (project-scoped or global), then patches `settings.json` to register the statusline and 4 hooks. Safe to re-run — all operations are idempotent.

## When to use

Run once immediately after a marketplace install:

> "set up valkyrie"

or `/valkyrie:setup`

## Output

- `$CLAUDE_HOME/valkyrie/` — stage.py, statusline.py, cost-helper.py, telemetry-helper.py, rates.json, crew-shim
- `$CLAUDE_HOME/hooks/` — valk-guard.sh, valk-tdd-gate.sh, valk-telemetry.sh, valk-loop-gate.sh
- `$CLAUDE_HOME/settings.json` — patched with statusline command and 4 hook entries

The statusline appears on next session start. Hooks are active immediately.
