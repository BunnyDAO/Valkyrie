#!/usr/bin/env bash
#
# to-azure-pr/helper.sh — open an Azure DevOps PR and wait for the build.
#
# Designed to be invoked by the /to-azure-pr SKILL.md or directly from the
# afk script. Inputs come from environment variables (so callers don't have
# to thread a long arg list). Output is one JSON object on stdout.
#
# Required env:
#   AZURE_PR_BRANCH         source branch (must already exist locally)
#   AZURE_PR_TITLE          PR title (1 line)
#   AZURE_PR_DESCRIPTION    PR description (markdown, can be multi-line)
#   AZURE_PR_REPOSITORY     repo name or ID in the AzDO project
#
# Optional env:
#   AZURE_PR_TARGET_BRANCH  defaults to "master"
#   AZURE_PR_ORG            defaults to "https://dev.azure.com/RadiantDev"
#   AZURE_PR_PROJECT        defaults to "RadiantAdvanced"
#   AZURE_PR_WORK_ITEM_ID   numeric work item id; omitted = no link
#   AZURE_PR_POLL_INTERVAL  seconds between CI polls (default 30)
#   AZURE_PR_POLL_TIMEOUT   max seconds to wait for CI (default 1800 = 30 min)
#   AZURE_PR_NO_WAIT        if set to "1", skip CI wait and return immediately
#                            with ci_status="not_waited"
#
# Auth:
#   Interactive  → `az login` first (one-time per machine)
#   AFK runs     → export AZURE_DEVOPS_EXT_PAT before invoking
#
# Output (one JSON object on stdout, even on failure):
#   {
#     "pr_id": <int or null>,
#     "pr_url": "<string or null>",
#     "ci_status": "succeeded|failed|canceled|partiallySucceeded|none|inProgress|not_waited|error",
#     "ready_for_review": <bool>,
#     "error": "<string or null — set when something stopped the flow>"
#   }
#
# Exit code: 0 on success (PR opened and ready_for_review=true), 1 on any
# failure including "PR opened but CI failed". The caller reads exit code
# AND the JSON to decide what to do.

set -u

# --- defaults ---------------------------------------------------------------

: "${AZURE_PR_TARGET_BRANCH:=master}"
: "${AZURE_PR_ORG:=https://dev.azure.com/RadiantDev}"
: "${AZURE_PR_PROJECT:=RadiantAdvanced}"
: "${AZURE_PR_POLL_INTERVAL:=30}"
: "${AZURE_PR_POLL_TIMEOUT:=1800}"
: "${AZURE_PR_NO_WAIT:=0}"

# --- helpers ----------------------------------------------------------------

# Emit a JSON result and exit. Args: ci_status, ready_for_review, error, exit_code
# Uses the most recent values of PR_ID and PR_URL (may be empty).
emit_and_exit() {
  local ci_status="$1" ready="$2" error="$3" code="$4"
  local pr_id_json pr_url_json error_json
  pr_id_json="$([ -n "${PR_ID:-}" ] && printf '%s' "$PR_ID" || printf 'null')"
  pr_url_json="$([ -n "${PR_URL:-}" ] && printf '"%s"' "$PR_URL" || printf 'null')"
  error_json="$([ -n "$error" ] && printf '"%s"' "$error" || printf 'null')"
  cat <<EOF
{"pr_id": $pr_id_json, "pr_url": $pr_url_json, "ci_status": "$ci_status", "ready_for_review": $ready, "error": $error_json}
EOF
  exit "$code"
}

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    emit_and_exit "error" "false" "missing required env: $name" 1
  fi
}

# --- validate prereqs -------------------------------------------------------

if ! command -v az >/dev/null 2>&1; then
  emit_and_exit "error" "false" "az CLI not installed" 1
fi

if ! az extension show --name azure-devops >/dev/null 2>&1; then
  # Try to install on the fly. If that fails, bail.
  if ! az extension add --name azure-devops >/dev/null 2>&1; then
    emit_and_exit "error" "false" "azure-devops extension not installed and auto-install failed" 1
  fi
fi

require_env "AZURE_PR_BRANCH"
require_env "AZURE_PR_TITLE"
require_env "AZURE_PR_DESCRIPTION"
require_env "AZURE_PR_REPOSITORY"

# --- push branch ------------------------------------------------------------

if ! git push -u origin "$AZURE_PR_BRANCH" >/dev/null 2>&1; then
  emit_and_exit "error" "false" "git push failed for branch $AZURE_PR_BRANCH" 1
fi

# --- open PR ----------------------------------------------------------------

PR_CREATE_ARGS=(
  --org "$AZURE_PR_ORG"
  --project "$AZURE_PR_PROJECT"
  --repository "$AZURE_PR_REPOSITORY"
  --source-branch "$AZURE_PR_BRANCH"
  --target-branch "$AZURE_PR_TARGET_BRANCH"
  --title "$AZURE_PR_TITLE"
  --description "$AZURE_PR_DESCRIPTION"
  --output json
)

if [ -n "${AZURE_PR_WORK_ITEM_ID:-}" ]; then
  PR_CREATE_ARGS+=(--work-items "$AZURE_PR_WORK_ITEM_ID" --transition-work-items true)
fi

PR_CREATE_OUT="$(az repos pr create "${PR_CREATE_ARGS[@]}" 2>&1)"
PR_CREATE_RC=$?

if [ "$PR_CREATE_RC" -ne 0 ]; then
  # Trim error to one line for JSON safety.
  local_err="$(printf '%s' "$PR_CREATE_OUT" | head -c 300 | tr '\n' ' ' | sed 's/"/\\"/g')"
  emit_and_exit "error" "false" "az repos pr create failed: $local_err" 1
fi

PR_ID="$(printf '%s' "$PR_CREATE_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('pullRequestId',''))" 2>/dev/null || true)"
PR_URL="$(printf '%s' "$PR_CREATE_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('_links',{}).get('web',{}).get('href',''))" 2>/dev/null || true)"

if [ -z "$PR_ID" ]; then
  emit_and_exit "error" "false" "PR created but pullRequestId not found in response" 1
fi

# --- wait for CI (or skip) --------------------------------------------------

if [ "$AZURE_PR_NO_WAIT" = "1" ]; then
  emit_and_exit "not_waited" "false" "" 0
fi

START_TS="$(date +%s)"
DEADLINE_TS=$((START_TS + AZURE_PR_POLL_TIMEOUT))

CI_RESULT=""
CI_STATUS=""

while [ "$(date +%s)" -lt "$DEADLINE_TS" ]; do
  RUNS_OUT="$(az pipelines runs list \
    --org "$AZURE_PR_ORG" \
    --project "$AZURE_PR_PROJECT" \
    --branch "$AZURE_PR_BRANCH" \
    --top 1 \
    --query-order QueueTimeDesc \
    --output json 2>/dev/null)" || true

  if [ -n "$RUNS_OUT" ] && [ "$RUNS_OUT" != "[]" ]; then
    CI_STATUS="$(printf '%s' "$RUNS_OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0].get('status','') if d else '')" 2>/dev/null || true)"
    CI_RESULT="$(printf '%s' "$RUNS_OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0].get('result','') if d else '')" 2>/dev/null || true)"
    if [ "$CI_STATUS" = "completed" ]; then
      break
    fi
  fi

  sleep "$AZURE_PR_POLL_INTERVAL"
done

if [ "$CI_STATUS" != "completed" ]; then
  emit_and_exit "inProgress" "false" "CI did not complete within ${AZURE_PR_POLL_TIMEOUT}s" 1
fi

case "$CI_RESULT" in
  succeeded)
    emit_and_exit "succeeded" "true" "" 0
    ;;
  failed|canceled|partiallySucceeded|none|"")
    emit_and_exit "${CI_RESULT:-none}" "false" "" 1
    ;;
  *)
    emit_and_exit "$CI_RESULT" "false" "unexpected CI result value" 1
    ;;
esac
