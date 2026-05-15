# `MANUAL-SMOKE.md` — interactive flow smoke test

The integration suite (`test/run-integration-tests.sh`) only exercises **AFK** mode — autonomous, non-interactive. To verify the **full Valkyrie pipeline** (DESIGN → PRD → ISSUES → TDD with a human in the loop), run this procedure manually.

**Cost**: ~$2–5 in API credits per full run (the grilling phase is the expensive part).
**Time**: ~15 minutes.
**When to run**: once before merging any change to a skill in `skills/`, and again before a team rollout.

## Procedure

### Variant A — no config (default behavior path)

1. Create a scratch repo somewhere outside the Valkyrie tree:
   ```bash
   mkdir /tmp/valk-smoke-a && cd /tmp/valk-smoke-a
   git init -b master
   echo "# Scratch" > README.md && git add . && git commit -m "init"
   ```
2. Confirm there is **no** `.claude/valk-config.md` (default behavior should apply).
3. Open a fresh Claude Code session in this directory.
4. Type: `let's build a tiny CSV-to-JSON converter`
5. **Expect**: statusline flips to `▶ DESIGN`. The VALK ENFORCEMENT message fires. The agent invokes `/valk` and starts grilling you with one question at a time.
6. Answer a few questions (be terse), then say "ok that's enough, write it up."
7. **Expect**: stage transitions to `▶ PRD`; agent synthesizes a PRD at `docs/prd/<slug>.md`.
8. Approve the PRD ("looks good, break into issues").
9. **Expect**: stage transitions to `▶ ISSUES`; agent creates `issues/0001-*.md` (and maybe more).
10. Approve the issue breakdown ("ok, start TDD on issue 1").
11. **Expect**: stage transitions to `▶ TDD`; agent runs RED → GREEN → REFACTOR on the first slice.
12. After all AC checked: **expect** `status: done` in the issue frontmatter, **no** `pr_url:` field, no PR opened anywhere.

### Variant B — config opts into a missing PR skill (fail-loud path)

1. Create a second scratch repo:
   ```bash
   mkdir /tmp/valk-smoke-b && cd /tmp/valk-smoke-b
   git init -b master
   echo "# Scratch" > README.md && git add . && git commit -m "init"
   ```
2. Create `.claude/valk-config.md`:
   ```markdown
   ---
   pr_skill: to-azure-pr
   test_skill: none
   ---
   ```
3. **Do NOT install `/to-azure-pr`** in your Claude environment. We want the missing-skill path.
4. Open a fresh Claude Code session and run through DESIGN → PRD → ISSUES → TDD as in Variant A.
5. At the end of TDD, when `/tdd` reads `pr_skill: to-azure-pr` and tries to invoke it:
6. **Expect**: agent STOPS with an error along the lines of "Config requires /to-azure-pr but it's not available. Install it or set pr_skill: none in .claude/valk-config.md."
7. **Expect**: issue is NOT marked done; no PR opened.

## Pass/fail

The smoke passes if both variants produce their expected outcomes. Document any deviation here (append a "Known deviations" section) before the next rollout.

## Known deviations

(none yet)
