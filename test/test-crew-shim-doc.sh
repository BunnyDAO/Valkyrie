#!/usr/bin/env bash
#
# test-crew-shim-doc.sh — the valk orchestrator SKILL.md carries the optional
# crew shim contract (Agent-Builder cycle-2 #0020 / ADR 0001 §2-6, 0002 V4).
#
# Doc-contract guard only: asserts the shim's invariants are documented so they
# can't silently rot. The BEHAVIORAL no-op proof (absent valk-config ⇒ vanilla
# byte-identical) is issue 0021 (next slice).

set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO_ROOT:-$(dirname "$TEST_DIR")}"
SKILL="$REPO/skills/valk/SKILL.md"

[ -f "$SKILL" ] || { echo "FAIL: orchestrator SKILL.md missing at $SKILL"; exit 1; }

# regex (case-insensitive) match
have() { grep -qiE -e "$1" "$SKILL" || { echo "FAIL: SKILL.md missing: $2"; exit 1; }; }
# literal fixed-string match
lit()  { grep -qF  -e "$1" "$SKILL" || { echo "FAIL: SKILL.md missing: $2"; exit 1; }; }

have 'crew shim'                              'a Crew shim section'
lit  '.claude/valk-config.md'                 'reference to <repo>/.claude/valk-config.md'
lit  'version: 1'                             'the version:1 contract check'
have 'absent|empty'                           'the absent/empty guard'
have 'vanilla|verbatim|unchanged'             'the vanilla fall-through (no-op)'
have 'dispatch the bound crew|bound crew'     'dispatch the bound crew on non-empty'
have 'gat(e|ing)|prd-review'                  'gating/stage-order preserved'
have 'per issue|tdd-<'                        'per-issue dispatch at TDD'
have 'single, central|do not edit the stage sub-skills|sub-skills.*untouched' \
                                              'central shim / sub-skills untouched'

# #0114 / ADR-0026 — augment mode + advisory-must-acknowledge gate.
have 'augment'                                'augment mode named'
have 'replace'                                'replace mode named'
lit  'crew-shim mode'                         'the mode helper is documented'
lit  'design-input.md'                        'augment writes design-input.md'
lit  'challenges.md'                          'augment writes challenges.md'
have 'advisory-must-acknowledge|acknowledge or override' \
                                              'augment gate is advisory-must-acknowledge'
have 'hard.?halt'                             'replace keeps the hard-halt'
have 'author|holds the pen'                   'human stays author/arbiter in augment'

# #0116 / ADR-0026 amendment — augment authorship is privilege-derived
# (lead read-write class drafts; human authors when no read-write class bound).
have 'privilege-derived|posture'              'augment authorship is privilege-derived'
have 'read-write'                             'read-write posture names the author'
have 'lead'                                   'the single lead author / lead: marker'
have 'human authors'                          'human authors when no read-write class bound'

echo "ok: crew shim contract documented in valk/SKILL.md"
exit 0
