#!/usr/bin/env bash
#
# Tests for issue 0003: rates.json + cost computation core.
#
# Each case sets up a fake $HOME so `afk` reads a test-controlled
# rates.json instead of the user's real one. That lets us test missing/
# malformed/unknown-model paths without touching the user's filesystem.

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO_ROOT:-$(dirname "$TEST_DIR")}"
RALPH_AFK="$REPO/scripts/afk"
COST_FIX="$TEST_DIR/fixtures/cost"

fail() { echo "FAIL: $*"; [ -n "${OUT:-}" ] && [ -f "$OUT" ] && { echo "--- stdout ---"; cat "$OUT"; }; exit 1; }

# Build a fake $HOME with a copy of the repo's rates.json. The repo file is
# the source of truth — if it doesn't exist yet, the test is broken.
make_fake_home() {
  local home="$1"
  mkdir -p "$home/.claude/valkyrie"
  cp "$REPO/scripts/rates.json" "$home/.claude/valkyrie/rates.json"
  # cost-helper.py is what afk shells out to; install.sh would copy it.
  cp "$REPO/scripts/cost-helper.py" "$home/.claude/valkyrie/cost-helper.py"
}

# ---------------------------------------------------------------------------
# 1. Known fixture: opus-simple → 1000 input + 500 output @ placeholder rates
#    input_per_mtok=15, output_per_mtok=75
#    cost = 1000/1e6*15 + 500/1e6*75 = 0.015 + 0.0375 = 0.0525
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; OUT="$H/run.out"
make_fake_home "$H"
HOME="$H" "$RALPH_AFK" --debug-cost "$COST_FIX/opus-simple.log" >"$OUT" 2>&1
[ $? -eq 0 ] || fail "case 1: nonzero exit"
grep -q "model=claude-opus-4-7" "$OUT" || fail "case 1: model"
grep -q "input=1000"             "$OUT" || fail "case 1: input"
grep -q "output=500"              "$OUT" || fail "case 1: output"
grep -q "cost_usd=0.0525"         "$OUT" || { fail "case 1: cost — got $(cat "$OUT")"; }
rm -rf "$H"

# ---------------------------------------------------------------------------
# 2. Cache fields broken into 5m/1h are summed correctly.
#    With cache: cw5m=2000, cw1h=1000, cread=4000
#    cost = 0.0525 + 2000/1e6*18.75 + 1000/1e6*30 + 4000/1e6*1.5
#         = 0.0525 + 0.0375 + 0.03 + 0.006 = 0.126
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; OUT="$H/run.out"
make_fake_home "$H"
HOME="$H" "$RALPH_AFK" --debug-cost "$COST_FIX/opus-with-cache.log" >"$OUT" 2>&1
[ $? -eq 0 ] || fail "case 2: nonzero exit"
grep -q "cw5m=2000"  "$OUT" || fail "case 2: cw5m"
grep -q "cw1h=1000"  "$OUT" || fail "case 2: cw1h"
grep -q "cread=4000" "$OUT" || fail "case 2: cread"
grep -q "cost_usd=0.126" "$OUT" || fail "case 2: cost — got $(cat "$OUT")"
rm -rf "$H"

# ---------------------------------------------------------------------------
# 3. Flat cache_creation_input_tokens is attributed entirely to cw5m.
#    cache_creation = 3000, cread = 4000
#    cost = 0.0525 + 3000/1e6*18.75 + 4000/1e6*1.5
#         = 0.0525 + 0.05625 + 0.006 = 0.11475
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; OUT="$H/run.out"
make_fake_home "$H"
HOME="$H" "$RALPH_AFK" --debug-cost "$COST_FIX/opus-flat-cache.log" >"$OUT" 2>&1
[ $? -eq 0 ] || fail "case 3: nonzero exit"
grep -q "cw5m=3000" "$OUT" || fail "case 3: flat → cw5m"
grep -q "cw1h=0"    "$OUT" || fail "case 3: flat → cw1h zero"
grep -q "cost_usd=0.11475" "$OUT" || fail "case 3: cost — got $(cat "$OUT")"
rm -rf "$H"

# ---------------------------------------------------------------------------
# 4. Date-suffixed model (claude-opus-4-7-20251115) normalizes to claude-opus-4-7.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; OUT="$H/run.out"
make_fake_home "$H"
HOME="$H" "$RALPH_AFK" --debug-cost "$COST_FIX/opus-date-suffix.log" >"$OUT" 2>&1
[ $? -eq 0 ] || fail "case 4: nonzero exit"
grep -q "model=claude-opus-4-7" "$OUT" || fail "case 4: model not normalized — got $(cat "$OUT")"
grep -q "cost_usd=0.0525"        "$OUT" || fail "case 4: cost"
rm -rf "$H"

# ---------------------------------------------------------------------------
# 5. Unknown model hard-refuses with a clear error naming the model.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; OUT="$H/run.out"
make_fake_home "$H"
HOME="$H" "$RALPH_AFK" --debug-cost "$COST_FIX/unknown-model.log" >"$OUT" 2>&1
RC=$?
[ "$RC" -ne 0 ] || fail "case 5: should have exited non-zero"
grep -q "claude-foo-bar" "$OUT" || fail "case 5: error should name the model"
rm -rf "$H"

# ---------------------------------------------------------------------------
# 6. Missing rates.json hard-refuses.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; OUT="$H/run.out"
mkdir -p "$H/.claude/valkyrie"
cp "$REPO/scripts/cost-helper.py" "$H/.claude/valkyrie/cost-helper.py"
# Note: NOT copying rates.json
HOME="$H" "$RALPH_AFK" --debug-cost "$COST_FIX/opus-simple.log" >"$OUT" 2>&1
RC=$?
[ "$RC" -ne 0 ] || fail "case 6: should have exited non-zero on missing rates.json"
grep -qi "rates" "$OUT" || fail "case 6: error should mention rates"
rm -rf "$H"

# ---------------------------------------------------------------------------
# 7. Malformed rates.json hard-refuses.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; OUT="$H/run.out"
make_fake_home "$H"
echo "{ this is not valid json" > "$H/.claude/valkyrie/rates.json"
HOME="$H" "$RALPH_AFK" --debug-cost "$COST_FIX/opus-simple.log" >"$OUT" 2>&1
RC=$?
[ "$RC" -ne 0 ] || fail "case 7: should have exited non-zero on malformed rates.json"
rm -rf "$H"

# ---------------------------------------------------------------------------
# 8. Reported path: a result event with total_cost_usd > 0 wins over rates.
#    Fixture uses an UNKNOWN model on purpose — the reported path must NOT
#    consult rates.json, so an unknown model is not an error here.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; OUT="$H/run.out"
make_fake_home "$H"
HOME="$H" "$RALPH_AFK" --debug-cost "$COST_FIX/reported-cost.log" >"$OUT" 2>&1
[ $? -eq 0 ] || fail "case 8: nonzero exit — got $(cat "$OUT")"
grep -q "cost_usd=0.4242"     "$OUT" || fail "case 8: should use reported 0.4242 — got $(cat "$OUT")"
grep -q "cost_source=reported" "$OUT" || fail "case 8: cost_source should be reported — got $(cat "$OUT")"
rm -rf "$H"

# ---------------------------------------------------------------------------
# 9. Reported path needs no rates.json at all. Same fixture, but rates.json
#    is absent — must still succeed (unlike case 6's computed path).
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; OUT="$H/run.out"
mkdir -p "$H/.claude/valkyrie"
cp "$REPO/scripts/cost-helper.py" "$H/.claude/valkyrie/cost-helper.py"
# Note: NOT copying rates.json — the reported path must not need it.
HOME="$H" "$RALPH_AFK" --debug-cost "$COST_FIX/reported-cost.log" >"$OUT" 2>&1
[ $? -eq 0 ] || fail "case 9: reported path must not require rates.json — got $(cat "$OUT")"
grep -q "cost_usd=0.4242" "$OUT" || fail "case 9: cost — got $(cat "$OUT")"
rm -rf "$H"

# ---------------------------------------------------------------------------
# 10. cost_mode auto-detect: apiKeySource "none" → tokens.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; OUT="$H/run.out"
make_fake_home "$H"
HOME="$H" "$RALPH_AFK" --debug-cost "$COST_FIX/subscription.log" >"$OUT" 2>&1
[ $? -eq 0 ] || fail "case 10: nonzero exit — got $(cat "$OUT")"
grep -q "cost_mode=tokens" "$OUT" || fail "case 10: apiKeySource none should auto → tokens — got $(cat "$OUT")"
grep -q "total_tokens=1500" "$OUT" || fail "case 10: total_tokens — got $(cat "$OUT")"
rm -rf "$H"

# ---------------------------------------------------------------------------
# 11. cost_mode auto-detect: apiKeySource an API key → dollars.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; OUT="$H/run.out"
make_fake_home "$H"
HOME="$H" "$RALPH_AFK" --debug-cost "$COST_FIX/api-billed.log" >"$OUT" 2>&1
[ $? -eq 0 ] || fail "case 11: nonzero exit — got $(cat "$OUT")"
grep -q "cost_mode=dollars" "$OUT" || fail "case 11: API key should auto → dollars — got $(cat "$OUT")"
rm -rf "$H"

# ---------------------------------------------------------------------------
# 12. cost_mode auto-detect: missing apiKeySource (synthetic) → dollars (safe).
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; OUT="$H/run.out"
make_fake_home "$H"
HOME="$H" "$RALPH_AFK" --debug-cost "$COST_FIX/opus-simple.log" >"$OUT" 2>&1
[ $? -eq 0 ] || fail "case 12: nonzero exit — got $(cat "$OUT")"
grep -q "cost_mode=dollars" "$OUT" || fail "case 12: missing apiKeySource should default → dollars — got $(cat "$OUT")"
rm -rf "$H"

# ---------------------------------------------------------------------------
# 13. VALK_COST_MODE env overrides auto-detect, both directions.
# ---------------------------------------------------------------------------
H="$(mktemp -d)"; OUT="$H/run.out"
make_fake_home "$H"
# Force tokens on an API-key fixture (auto would say dollars).
HOME="$H" VALK_COST_MODE=tokens "$RALPH_AFK" --debug-cost "$COST_FIX/api-billed.log" >"$OUT" 2>&1
[ $? -eq 0 ] || fail "case 13a: nonzero exit — got $(cat "$OUT")"
grep -q "cost_mode=tokens" "$OUT" || fail "case 13a: env tokens must override auto-dollars — got $(cat "$OUT")"
# Force dollars on a subscription fixture (auto would say tokens).
HOME="$H" VALK_COST_MODE=dollars "$RALPH_AFK" --debug-cost "$COST_FIX/subscription.log" >"$OUT" 2>&1
[ $? -eq 0 ] || fail "case 13b: nonzero exit — got $(cat "$OUT")"
grep -q "cost_mode=dollars" "$OUT" || fail "case 13b: env dollars must override auto-tokens — got $(cat "$OUT")"
rm -rf "$H"

echo "cost tests ok"
