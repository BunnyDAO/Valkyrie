# Valkyrie — TODO

Loose ends and follow-ups not blocking shipping. Group by theme; check off as they land.

---

## AFK budget caps (spend control)

**Status: shipped via issues 0001–0005.** `afk` now caps by iterations, hours, and dollars. CSV history accumulates per-iter data for tuning defaults later. Real published rates are blocked on issue 0006 (HITL).

- [x] **Wall-clock cap** — shipped as `--max-hours <N>` (decimal-friendly), default 4h. Issue 0002.
- [x] **`--max-cost-usd X`** — shipped, default $50. Parses claude `stream-json` usage events, applies rate table per-model, sums across iters, breaks at boundary. Issue 0004.
- [x] **Rate table location** — shipped at `scripts/rates.json`, copied by `install.sh` to `~/.claude/valkyrie/rates.json`. Issue 0003.
- [x] **Per-iteration cost in the log** — shipped as a structured CSV at `<repo>/.claude/valk/afk-cost-history.csv` (one row per iter). Issue 0005.
- [x] **Document defaults** — covered in SOP §7 (this update).
- [ ] **`--max-tokens N`** — deferred. Useful when prices are in flux or you don't trust the rate table to be current. Either-or with `--max-cost-usd`, not both.
- [ ] **Soft warnings before hard caps.** At 50% / 75% / 90% of the configured cap, print a one-line warning to the terminal so a watching human can intervene. Doesn't block — just narrates.
- [ ] **Real published rates** — issue 0006 (HITL). Pull current Anthropic + OpenAI prices and replace the placeholder values in `rates.json`.
- [ ] **Per-iteration sub-cap** — bound runaway single-iter spend (the boundary-only design lets one bad iter overshoot the cumulative cap). Add if real usage shows iter cost variance is a problem.

Headline guarantee live now (with placeholder rates): *"afk will spend at most $X or N hours, whichever comes first, and stop cleanly at a stage boundary."* The dollar number becomes real once 0006 lands.

---

## AFK enforcement (the unenforced gap)

`afk` runs from a parent shell and spawns Claude Code subprocesses. The `UserPromptSubmit` hook can't reach it. Today its only defense is written discipline in SOP §7.

Cheap technical guardrails to turn the SOP rules into actual gates:

- [ ] **Refuse to run without a PRD.** Pre-flight check: `docs/prd/` must exist and contain at least one non-empty `.md`. Exit with a clear message pointing the user back to `/to-prd`.
- [ ] **Refuse to run with a dirty working tree.** `git diff --quiet && git diff --cached --quiet` must pass. Override with `--allow-dirty`. Reason: the agent will modify uncommitted work and you can't tell what it changed.
- [ ] **Confirm before launch.** Print the list of issues that will be picked (in dependency order, with their acceptance criteria summaries) and require `yes` to proceed. Skippable with `--no-confirm` for CI / cron.
- [ ] **Warn on dangerous paths.** If `pwd` contains `auth`, `payment`, `billing`, `migration`, `infra`, `prod`, print a loud warning and require `--i-know-this-is-dangerous`. Heuristic, not exhaustive — but catches the common ones.
- [ ] **Refuse `--prompt-file` unless paired with `--bypass-tdd`.** Force the user to be explicit when overriding the default red-green-refactor prompt.
- [ ] **Snapshot the PRD hash at launch.** Write `<pwd>/.claude/valk/afk-prd-hash` so we can later detect drift between "what you read" and "what the agent saw." Foundation for a future "you didn't read the PRD" gate.

When all of these land, AFK has the same level of technical enforcement as the in-session hook.

---

## Hook polish

- [ ] **Tune the regex over time** based on actual false positives / false negatives in `~/.claude/hooks/valk-guard.log` (when temporarily enabled). Track which build phrasings slip through; add categories.
- [ ] **Make the bypass phrase explicit in error message.** When the hook fires and the user thinks it shouldn't have, the injected context should mention `skip valk` as the override.
- [ ] **Consider blocking instead of injecting** for high-confidence build prompts. Right now the hook always uses `additionalContext` (soft); for prompts like "implement a new feature for X", an exit-2 hard block might be the right call.

---

## Statusline

- [ ] **Confirm whether `statusLine` config reloads per-prompt** the same way hooks do. We proved hooks reload; haven't tested statusline. If it doesn't reload, document the restart requirement in §1; if it does, remove the "restart Claude Code" line from §1.

---

## install.sh

- [ ] **Add a `--uninstall` flag.** Symmetric with install: remove symlinks, restore `settings.json` from backup if present, drop the hook. Org members will want this for cleanup.
- [ ] **Add a smoke test at the end of install** that pipes a known build prompt through the freshly-installed hook and confirms enforcement context comes back. Catches broken installs at install time, not at first use.

---

## Skills

- [ ] **Add a `/status` skill** that prints the current stage, recent PRDs in `docs/prd/`, count of open vs done issues, and the last AFK iteration result. One command to know "where am I in this workflow." Reduces the cognitive overhead of multi-day projects.
- [ ] **Decide whether `/grill-with-docs` should record the transcript.** Right now the PRD is the artifact; the grilling itself is ephemeral. Saving `docs/prd/<slug>.grill.md` would help diffs ("which decision changed?").

---

## SOP / rollout

- [ ] **Replace `<internal-repo-url>` placeholder in §1 install command** once the repo has a real home.
- [ ] **Add a recorded ~5-min demo video** to drop into §10 FAQ. Pilot engineers report the demo is the single highest-leverage onboarding asset.
- [ ] **Build the override-rate dashboard** referenced in §11. Source: parse the `~/.claude/hooks/valk-guard.log` (when enabled) for prompts the hook *would* have fired on but were bypassed via override phrases. Aggregate per engineer, share weekly.
- [ ] **Pick a champion and a pilot team.** Section 11 phase 1 doesn't start without 3–5 named volunteers.

---

## Known unknowns

- [ ] **What happens if two `afk` processes run in the same repo?** Race on the stage marker, race on issue status writes. Probably need a lockfile in `.claude/valk/`.
- [ ] **What's the correct behavior when an issue's `blocked_by:` references an issue that doesn't exist?** Today it'd silently treat it as unblocked (no file found). Should probably error.
- [ ] **Does the hook's `jq` dependency need vendoring?** macOS doesn't ship `jq` by default on every version. Document the dep, or rewrite the hook in pure bash + python.
