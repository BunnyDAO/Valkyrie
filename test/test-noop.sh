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

# E — `decide` is byte-identical regardless of mode. The augment-mode arc
# (#0114) must NOT change the no-op guarantee: a repo with NO binding still
# decides `vanilla` at every stage, byte-for-byte (no mode leakage into decide).
E="$(mkrepo e)"
for s in DESIGN PRD ISSUES TDD; do expect "$E" "$s" vanilla; done

# F — the FIXED stage→mode rule (#0114 / ADR-0026): DESIGN/PRD augment,
# ISSUES/TDD replace. Independent of any binding (mode answers "IF a crew runs
# here, how?"), so it holds with no valk-config.md at all.
expect_mode() { # expect_mode <STAGE> <augment|replace>
  local got; got="$("$SHIM" mode "$1" 2>/dev/null)"
  [ "$got" = "$2" ] || { echo "FAIL: mode $1 -> '$got' (want '$2')"; exit 1; }
}
expect_mode DESIGN augment
expect_mode PRD    augment
expect_mode ISSUES replace
expect_mode TDD    replace
# case-insensitive stage arg, same as decide
expect_mode design augment
expect_mode tdd    replace
# unknown stage is a usage error (exit non-zero), not a silent default
"$SHIM" mode BOGUS >/dev/null 2>&1 && { echo "FAIL: mode BOGUS should exit non-zero"; exit 1; }

echo "ok: absent/empty/unversioned valk-config is a complete no-op; stage→mode rule fixed"
exit 0
