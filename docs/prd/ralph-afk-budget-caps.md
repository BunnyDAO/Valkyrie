# ralph-afk budget caps

## Problem Statement

`ralph-afk` runs autonomously, spawning fresh-context CLI sessions to work through issues while the user is away. Today its only safety knob is `<max_iterations>` — a count of how many issues to attempt. That's the wrong dimension for cost: one runaway iteration (long generation, cache misses, expensive model) can spend more than ten short ones. An overnight `ralph-afk 50` against opus could quietly burn hundreds of dollars before anyone notices.

The user has no upper bound on dollars or hours. The default position of "trust the loop" doesn't survive contact with billing.

## Solution

Add two new flags to `ralph-afk` that bound the run by **wall-clock hours** and by **estimated API spend in USD**. Caps are checked at iteration boundaries (so the current iter completes cleanly, no half-finished commits). Sane defaults are on by default — running `ralph-afk N` alone is now safe; you opt *out* of safety by passing higher values, not in.

Headline guarantee after this lands: *"ralph-afk will spend at most $X or N hours, whichever comes first, and stop cleanly at a stage boundary."*

## User Stories

1. As an engineer kicking off an overnight run, I want the loop to stop after 4 hours by default, so that a runaway loop doesn't churn through my morning standup.
2. As an engineer kicking off an overnight run, I want the loop to stop at $50 of estimated API spend by default, so that a single bad iteration can't quietly torch a quarter of my monthly budget.
3. As an engineer with a known-cheap workload, I want to override the cost cap with `--max-cost-usd 200`, so that I can run longer batches when I've explicitly accepted the spend.
4. As an engineer with a known-expensive workload, I want to lower the cap with `--max-cost-usd 10`, so that exploratory or risky runs get a tighter leash.
5. As an engineer starting a run, I want to see the active caps printed at startup, so that I know what's enforced before I walk away.
6. As an engineer reviewing a finished run, I want a structured summary at exit (iterations done, time elapsed, dollars spent, exit reason), so that I can tell at a glance how the run ended.
7. As an engineer reviewing a finished run, I want one line per iteration in the terminal showing cumulative time and spend, so that the run's progression is visible without parsing logs.
8. As an engineer tuning my future caps, I want a CSV file of every iteration's cost data appended across runs, so that I can base future caps on real history instead of guesses.
9. As an engineer interrupting a run with Ctrl-C, I want the same summary banner printed before exit (with `reason: interrupted`), so that I can see what I spent before bailing.
10. As a teammate updating Anthropic prices when they change, I want `rates.json` checked into the repo, so that the change is a reviewable PR and `git pull && ./install.sh` is the only thing teammates have to do.
11. As an engineer running on a model that isn't yet in `rates.json`, I want the loop to refuse to start with a clear error, so that I don't get a false sense of cost-cap protection on an unpriced model.
12. As an engineer with a malformed or missing `rates.json`, I want the loop to refuse to start with a clear error pointing at the fix, so that I don't silently lose cost tracking.
13. As an engineer running through an iteration that produces no usage events, I want the loop to differentiate a clean exit (treat as $0, continue) from a dirty exit (hard fail, broken tracking), so that benign no-ops don't stop the loop but real tracking gaps do.

## Implementation Decisions

### Modules

The implementation is one bash script edit (`scripts/ralph-afk`) plus one new data file. Conceptually it splits into six small, single-purpose modules — even though they live as bash functions in one file:

- **Rate table loader** — read `~/.claude/valkyrie/rates.json` once at startup; validate schema; load into memory. Hard refuse on missing/malformed/unknown-schema.
- **Cap config** — parse `--max-hours`, `--max-cost-usd` from argv; merge with hardcoded defaults (4h / $50). Compute absolute deadline = `start_time + max_hours * 3600`. Print active caps banner.
- **Usage parser** — given a per-iteration log file, extract `usage` events from claude stream-json (`input_tokens`, `output_tokens`, `cache_creation_input_tokens` broken into 5m/1h sub-tiers, `cache_read_input_tokens`) or from codex's equivalent. Sum per token type. Detect model name from the stream's `message.model` field.
- **Cost computer** — given parsed token counts and the model name, look up rates and compute USD cost for the iteration.
- **Cap checker** — at each iteration boundary, check: iteration count, elapsed time, cumulative cost. Returns `(should_stop, reason)`.
- **Reporter** — three responsibilities: print per-iteration cumulative line; append CSV row to `<repo>/.claude/valk/afk-cost-history.csv`; print final summary banner with reason on any exit (clean / cap-hit / interrupted).

### Interfaces (bash function signatures)

```bash
load_rates           # () -> sets RATES_JSON in memory or exits 1
parse_caps           # (argv) -> sets MAX_ITERS, MAX_HOURS, MAX_COST_USD, DEADLINE_TS
parse_iter_usage     # (logfile) -> echoes "model input output cw5m cw1h cread exit_code"
compute_iter_cost    # (model input output cw5m cw1h cread) -> echoes USD as decimal
check_caps           # () -> echoes "stop|continue REASON"
report_iter          # (iter, model, cost) -> stdout line + CSV append
report_final         # (reason) -> banner to stdout
```

### `rates.json` schema

```json
{
  "anthropic": {
    "claude-opus-4-7": {
      "input_per_mtok":          15.00,
      "output_per_mtok":         75.00,
      "cache_write_5m_per_mtok": 18.75,
      "cache_write_1h_per_mtok": 30.00,
      "cache_read_per_mtok":      1.50
    }
  },
  "openai": {
    "gpt-5-codex": {
      "input_per_mtok":   1.25,
      "output_per_mtok": 10.00
    }
  }
}
```

Provider keys (`anthropic`, `openai`) match the `--cli` flag mapping (`claude` → anthropic, `codex` → openai). Unknown provider OR unknown model under a known provider both trigger the hard-refuse path.

### Key behaviors

- **Cap-hit semantics:** caps are checked at iteration boundaries only. A cap that crosses mid-iteration completes the current iter and exits next. Bounded overshoot = one iteration's cost.
- **Defaults:** `--max-hours 4`, `--max-cost-usd 50`, hardcoded in the script. Iteration count `N` remains a required positional argument. Active caps banner prints at startup.
- **Unknown model / broken `rates.json`:** hard refuse at startup or first iteration parse. No embedded fallback rates, no silent degradation.
- **No usage events in an iteration:** clean exit → treat as $0 and continue; dirty exit → hard fail with a clear error. The CLI exit code disambiguates.
- **Per-iteration line:** after each iteration, print one line:
  ```
  iter 3/10 done | elapsed 1h12m / 4h00m | spend $4.50 / $50.00 (~9%)
  ```
- **CSV file:** appended each iteration, never overwritten across runs. Path: `<repo>/.claude/valk/afk-cost-history.csv`. Columns: `timestamp, iter, model, input_tokens, output_tokens, cache_write_5m, cache_write_1h, cache_read, cost_usd, cumulative_usd, exit_reason_for_run`.
- **Final summary banner** (printed on any exit, including Ctrl-C):
  ```
  ralph-afk: stopped — reason: cost cap hit
    iterations:    7 / 10
    elapsed:       2h41m / 4h00m
    spend:         $50.04 / $50.00 (overshoot: $0.04)
    issues done:   5
    issues stuck:  2
    logs:          .claude/valk/afk-logs/
    cost history:  .claude/valk/afk-cost-history.csv
  ```

### `install.sh` changes

- Copy `scripts/rates.json` → `~/.claude/valkyrie/rates.json` (idempotent).
- No new flags or config options.
- Existing hook + statusline wiring unchanged.

### Out-of-band (deferred — not in this PRD)

- Per-iteration sub-cap to bound runaway single-iter spend.
- Config-file layer for per-machine default tuning.
- `--dry-run` mode that estimates cost from the issue queue before launching.

## Testing Decisions

External behavior is what we test — the public surface is the CLI flags and the side-effects on disk (CSV file, exit code, stdout summary). Internals (which bash function did what) are not tested.

**Modules to test (via shell-out to `ralph-afk`):**

1. **Rate table loader** — given a known-good `rates.json`, the loop accepts it. Given malformed JSON, missing file, or a known-unknown model in the rate table, the loop exits non-zero with the expected error message. (Black-box: just check exit code + stderr.)
2. **Cap config + banner** — given `--max-hours 2 --max-cost-usd 30`, startup banner reports those values. Defaults (no flags) report `4h / $50`.
3. **Cap checker (time)** — with a mocked CLI that takes 1s per iter and `--max-hours` set so the deadline crosses after iter 3, the loop exits with `reason: time cap hit` after exactly 3 completed iterations.
4. **Cap checker (cost)** — with a mocked CLI emitting a known fixed-cost usage event per iter, and `--max-cost-usd` set just above 3× that cost, the loop exits with `reason: cost cap hit` after 3 iterations and cumulative ≥ cap.
5. **Cap checker (iterations)** — the existing iteration cap behavior is unchanged when neither new flag is passed (regression).
6. **CSV emission** — after a successful run, `afk-cost-history.csv` exists with the expected header on first creation and one row per iteration. Subsequent runs append, never overwrite.
7. **Final summary on Ctrl-C** — sending SIGINT mid-iter prints the summary banner with `reason: interrupted`.
8. **No-usage handling** — mocked CLI exits 0 with no usage events → iter treated as $0, loop continues. Mocked CLI exits 1 with no usage events → loop exits with `reason: cost tracking failed`.

**Test scaffold:** a small fixture directory (`test/fixtures/`) with stubbed `claude` and `codex` binaries on PATH that emit canned stream-json with known token counts. Lets the loop run end-to-end in milliseconds, deterministically.

**Prior art:** none in this repo — `ralph-afk` has no existing tests. This PR adds the test harness alongside the feature.

## Out of Scope

- Real-time cost cap enforcement *within* a single iteration. We only check at boundaries; one iter can overshoot.
- Tracking actual billed cost (vs. estimated). The cap is based on token counts × posted rates; if Anthropic applies tier discounts or your account has volume pricing, our number diverges from the bill. We're estimating, and the headline says so.
- Pulling rates dynamically from any URL or API. `rates.json` is checked-in static data, updated by PR.
- Cross-run cumulative caps (e.g. "no more than $200 this week"). Each `ralph-afk` invocation has its own caps.
- Anything codex-specific beyond basic input/output token tracking. Codex's equivalent of cache tiers is not in the schema.
- A `--dry-run` flag, a per-iter sub-cap, and per-machine default config — all noted in the deferred list above.

## Further Notes

- The CSV file accumulates indefinitely. After several months of use, this becomes the data source for tuning the hardcoded defaults (item already in `TODO.md`). No rotation logic needed at v1; revisit if files exceed a few MB.
- `cache_creation_input_tokens` in claude's stream-json may or may not be split into 5m/1h sub-fields depending on API version. Implementation should defensively handle both shapes — sum into 5m by default if no sub-tier is specified, since that's the cheaper assumption (and we want to overestimate cost, not underestimate). Document the assumption in code.
- Model name normalization: claude's `message.model` field can include date suffixes (e.g. `claude-opus-4-7-20251115`). Strip trailing `-\d{8}` before rate lookup. If the stripped name still isn't in the rate table, the unknown-model hard-refuse path applies.
- `~/.claude/valkyrie/rates.json` is global; per-project rate overrides are not in scope. If two projects use different rates (unlikely), the workaround is one global truth + careful repo updates.
