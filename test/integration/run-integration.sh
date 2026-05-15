#!/usr/bin/env bash
#
# run-integration.sh — drive one or more integration scenarios.
#
# For each <scenario> directory under fixtures/:
#   1. mktemp a fresh HOME and a fresh work-repo dir
#   2. copy the fixture into the work-repo dir
#   3. substitute the log-hook.py absolute path into .claude/settings.json
#   4. git init + commit the fixture (afk's preflight requires clean tree)
#   5. set HOME, VALK_TRACE_FILE, CLAUDE_CLI_PATH, ANTHROPIC_API_KEY (passthrough)
#   6. run `afk 1 --max-cost-usd <budget> --no-confirm` against the work repo
#   7. preserve trace + run output at test/integration/last-run/<scenario>/
#   8. invoke assertions/<scenario>.sh against the preserved artifacts
#
# Usage:
#   bash run-integration.sh                     # all fixtures
#   bash run-integration.sh trivial-slice       # one scenario by name
#   bash run-integration.sh --dry-run trivial-slice   # set up fixture but don't invoke claude
#
# Env (caller-provided):
#   ANTHROPIC_API_KEY     required for real-Claude runs (or auth via `claude` itself)
#   VALK_BUDGET_USD       per-scenario cost cap. Default 1.0
#   AFK_CLI               which CLI afk drives. Default claude

set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
INT_DIR="$REPO/test/integration"
FIXTURES_DIR="$INT_DIR/fixtures"
LAST_RUN_DIR="$INT_DIR/last-run"
LOG_HOOK="$INT_DIR/log-hook.py"
AFK="$REPO/scripts/afk"

DRY_RUN=0
ONLY=""
VALK_BUDGET_USD="${VALK_BUDGET_USD:-1.0}"
AFK_CLI="${AFK_CLI:-claude}"

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) ONLY="$1"; shift ;;
  esac
done

if [ ! -x "$AFK" ]; then
  echo "ERROR: afk not executable at $AFK" >&2; exit 2
fi
if [ ! -f "$LOG_HOOK" ]; then
  echo "ERROR: log-hook.py not found at $LOG_HOOK" >&2; exit 2
fi
if [ "$DRY_RUN" != "1" ] && ! command -v "$AFK_CLI" >/dev/null 2>&1; then
  echo "ERROR: '$AFK_CLI' not on PATH (set AFK_CLI or use --dry-run)" >&2; exit 2
fi

mkdir -p "$LAST_RUN_DIR"

PASS=0
FAIL=0
TOTAL=0

run_one() {
  local name="$1"
  local fixture="$FIXTURES_DIR/$name"
  [ -d "$fixture" ] || { echo "skip: $name (no such fixture)"; return; }
  TOTAL=$((TOTAL + 1))

  echo "==== $name ===="

  local tmp_home tmp_repo trace_file
  tmp_home="$(mktemp -d)"
  tmp_repo="$(mktemp -d)"
  trace_file="$tmp_repo/reports/trace.jsonl"
  mkdir -p "$(dirname "$trace_file")"

  cp -R "$fixture/." "$tmp_repo/"

  # Settings template → resolved path
  if [ -f "$tmp_repo/.claude/settings.json.tmpl" ]; then
    sed "s|__VALK_LOG_HOOK__|$LOG_HOOK|g" "$tmp_repo/.claude/settings.json.tmpl" > "$tmp_repo/.claude/settings.json"
    rm "$tmp_repo/.claude/settings.json.tmpl"
  fi

  # afk's preflight requires a clean git tree.
  ( cd "$tmp_repo" \
    && git init -q -b master \
    && git -c user.email=valk@test -c user.name=valk add . \
    && git -c user.email=valk@test -c user.name=valk commit -q -m "fixture: $name" )

  # Preserve artifacts for review at test/integration/last-run/<name>/
  local preserve="$LAST_RUN_DIR/$name"
  rm -rf "$preserve"
  mkdir -p "$preserve"

  if [ "$DRY_RUN" = "1" ]; then
    echo "  dry-run: fixture staged at $tmp_repo"
    cp -R "$tmp_repo/." "$preserve/"
    echo "  preserved at $preserve"
    return
  fi

  # Drive afk against the temp repo. We deliberately do NOT override HOME:
  # the spawned Claude needs the user's installed valk skills, and afk itself
  # depends on $HOME/.claude/valkyrie/{cost-helper,rates}. Isolation comes
  # from the temp work-repo + the project-scope .claude/settings.json which
  # layers our log-hook.py on top of whatever the user has. The unused
  # tmp_home is kept here so a future tighter-isolation mode can re-enable
  # it after staging required globals.
  local run_out="$preserve/run.out"
  (
    cd "$tmp_repo" \
      && VALK_TRACE_FILE="$trace_file" \
         AFK_CLI="$AFK_CLI" \
         "$AFK" 1 --cli "$AFK_CLI" --max-cost-usd "$VALK_BUDGET_USD" --max-hours 0.5 --no-confirm
  ) > "$run_out" 2>&1
  local afk_rc=$?
  echo "afk_exit=$afk_rc" > "$preserve/afk_exit"

  # Preserve everything (trace, work tree, run output, exit code)
  cp -R "$tmp_repo/." "$preserve/"

  # Assertions
  local assertion="$INT_DIR/assertions/${name}.sh"
  if [ ! -f "$assertion" ]; then
    echo "  no assertion script at $assertion — counting as FAIL"
    FAIL=$((FAIL + 1))
    return
  fi

  if PRESERVE_DIR="$preserve" AFK_EXIT="$afk_rc" bash "$assertion"; then
    echo "  PASS"
    PASS=$((PASS + 1))
  else
    echo "  FAIL (artifacts in $preserve)"
    FAIL=$((FAIL + 1))
  fi
}

if [ -n "$ONLY" ]; then
  run_one "$ONLY"
else
  for fx in "$FIXTURES_DIR"/*/; do
    run_one "$(basename "$fx")"
  done
fi

echo
echo "------------------------------------------------------------"
echo "Results: $PASS passed, $FAIL failed (of $TOTAL)"
[ "$FAIL" -eq 0 ] || exit 1
