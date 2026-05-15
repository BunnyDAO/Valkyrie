#!/usr/bin/env bash
#
# run-integration-tests.sh — top-level entry for the real-Claude suite.
#
# This is the paid sibling of test/run-tests.sh. It costs API credits per run
# (~$1 total for v1's 2 scenarios). Not invoked by the stub suite. Run
# manually before a rollout, or on a nightly schedule scoped to whatever
# budget the team accepts.
#
# Forwards all args to test/integration/run-integration.sh. Examples:
#   bash test/run-integration-tests.sh                  # all scenarios
#   bash test/run-integration-tests.sh trivial-slice    # one by name
#   bash test/run-integration-tests.sh --dry-run        # stage fixtures only

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$REPO/test/integration/run-integration.sh" "$@"
