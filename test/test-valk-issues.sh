#!/usr/bin/env bash
#
# test-valk-issues.sh — valk-issues ready/lint over issues/*.md.
#
# Proves the git-native ready-work query and dependency-graph linter:
#   - a clean graph lints OK and reports the right ready set
#   - lint catches duplicate ids, dangling + ambiguous deps, self-deps, cycles
#   - ready mirrors afk: open + all blocked_by done
# Pure over the markdown — no database, no deps beyond python3.

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO_ROOT:-$(dirname "$TEST_DIR")}"
VI="$REPO/scripts/valk-issues.py"

[ -f "$VI" ] || { echo "FAIL: valk-issues.py missing at $VI"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkissues() { rm -rf "$WORK/issues"; mkdir -p "$WORK/issues"; }
issue() { # issue <filename> <id> <status> <blocked_by-inline>
  cat > "$WORK/issues/$1" <<EOF
---
id: $2
title: "$1"
type: AFK
status: $3
blocked_by: $4
---
body
EOF
}
run() { python3 "$VI" "$1" --dir "$WORK/issues" "${@:2}"; }
ready_ids() { # space-delimited list of ids in the ready array
  python3 -c "import json,sys; print(' '.join(r['id'] for r in json.load(sys.stdin)['ready']))"
}
has() { case " $1 " in *" $2 "*) return 0;; *) return 1;; esac; }

# --- clean graph -----------------------------------------------------------
mkissues
issue "pvp-v1-01-a.md" pvp-v1-01 done "[]"
issue "pvp-v1-02-b.md" pvp-v1-02 open "[pvp-v1-01]"
issue "crew-exec-01-c.md" crew-exec-01 open "[]"

out="$(run lint)"; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: clean graph lint rc=$rc: $out"; exit 1; }

ids="$(run ready --json | ready_ids)"
has "$ids" "pvp-v1-02" || { echo "FAIL: pvp-v1-02 should be ready (dep done): [$ids]"; exit 1; }
has "$ids" "crew-exec-01" || { echo "FAIL: crew-exec-01 should be ready (no deps): [$ids]"; exit 1; }

# pvp-v1-02 must NOT be ready while its dep is still open
issue "pvp-v1-01-a.md" pvp-v1-01 open "[]"
ids="$(run ready --json | ready_ids)"
has "$ids" "pvp-v1-02" && { echo "FAIL: pvp-v1-02 ready while dep open: [$ids]"; exit 1; }
has "$ids" "pvp-v1-01" || { echo "FAIL: pvp-v1-01 should be ready (no deps, open): [$ids]"; exit 1; }

# --- duplicate id ----------------------------------------------------------
mkissues
issue "0039-crew.md" 0039 open "[]"
issue "0039-subscribe.md" 0039 open "[]"
out="$(run lint)"; rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: duplicate id should exit 2, got $rc"; exit 1; }
echo "$out" | grep -q "DUPLICATE_ID" || { echo "FAIL: expected DUPLICATE_ID: $out"; exit 1; }

# --- dangling dep ----------------------------------------------------------
mkissues
issue "b-01-x.md" b-01 open "[b-99]"
out="$(run lint)"; rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: dangling dep should exit 2, got $rc"; exit 1; }
echo "$out" | grep -q "DANGLING_DEP" || { echo "FAIL: expected DANGLING_DEP: $out"; exit 1; }

# --- self dep --------------------------------------------------------------
mkissues
issue "s-01-x.md" s-01 open "[s-01]"
out="$(run lint)"
echo "$out" | grep -q "SELF_DEP" || { echo "FAIL: expected SELF_DEP: $out"; exit 1; }

# --- cycle -----------------------------------------------------------------
mkissues
issue "c-01-x.md" c-01 open "[c-02]"
issue "c-02-y.md" c-02 open "[c-01]"
out="$(run lint)"; rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: cycle should exit 2, got $rc"; exit 1; }
echo "$out" | grep -q "CYCLE" || { echo "FAIL: expected CYCLE: $out"; exit 1; }

# --- id / filename mismatch ------------------------------------------------
mkissues
issue "wrong-name-01-x.md" totally-different-id open "[]"
out="$(run lint)"
echo "$out" | grep -q "ID_FILENAME_MISMATCH" || { echo "FAIL: expected ID_FILENAME_MISMATCH: $out"; exit 1; }

echo "PASS: valk-issues ready/lint"
exit 0
