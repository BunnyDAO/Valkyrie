#!/usr/bin/env bash
#
# test-noop.sh — V5 behavioral no-op proof (Agent-Builder #0021 / ADR 0002).
#
# The crew shim is only safe if its decision is DETERMINISTIC. scripts/crew-shim
# `decide <repo> <STAGE>` is that decision. This proves:
#   - no valk-config.md            => vanilla (every stage)
#   - version:1 + all empty lists  => vanilla
#   - missing/!=1 version          => vanilla (even with a non-empty list)
#   - version:1 + non-empty stage  => crew <ids...> (only that stage)
# i.e. an absent/empty/unversioned config is a complete no-op.
# Re-run verbatim after 0022 (the rename) — it must still pass.

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO_ROOT:-$(dirname "$TEST_DIR")}"
SHIM="$REPO/scripts/crew-shim"

[ -x "$SHIM" ] || { echo "FAIL: crew-shim helper missing/not exec at $SHIM"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

mkrepo() { local d="$WORK/$1"; mkdir -p "$d/.claude"; echo "$d"; }
expect() { # expect <repo> <STAGE> <expected-output>
  local got; got="$("$SHIM" decide "$1" "$2" 2>/dev/null)"
  [ "$got" = "$3" ] || { echo "FAIL: decide $2 -> '$got' (want '$3')"; exit 1; }
}

# A — no valk-config.md at all
A="$(mkrepo a)"
expect "$A" DESIGN vanilla
expect "$A" TDD    vanilla

# B — version:1, all stages empty
B="$(mkrepo b)"
cat > "$B/.claude/valk-config.md" <<'EOF'
---
version: 1
stages:
  DESIGN: []
  PRD: []
  ISSUES: []
  TDD: []
support: []
---
EOF
for s in DESIGN PRD ISSUES TDD; do expect "$B" "$s" vanilla; done

# C — missing/wrong version but TDD non-empty => still vanilla (version gate)
C="$(mkrepo c)"
cat > "$C/.claude/valk-config.md" <<'EOF'
---
version: 2
stages:
  TDD: [implementer, reviewer]
---
EOF
expect "$C" TDD vanilla

# D — version:1, TDD bound, others empty
D="$(mkrepo d)"
cat > "$D/.claude/valk-config.md" <<'EOF'
---
version: 1
stages:
  DESIGN: []
  PRD: []
  ISSUES: []
  TDD: [implementer, tester-qa, reviewer]
support: [cto-architect]
---
EOF
expect "$D" DESIGN vanilla
expect "$D" TDD    "crew implementer tester-qa reviewer"

echo "ok: absent/empty/unversioned valk-config is a complete no-op"
exit 0
