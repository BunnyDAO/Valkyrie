#!/usr/bin/env bash
#
# read-valk-config.sh — read one key from <repo>/.claude/valk-config.md
#
# Parses the YAML frontmatter (the block between the first pair of `---`
# lines) and prints the value for the requested key. Empty output means
# "key not set" (caller treats as default).
#
# Usage:
#   read-valk-config.sh <key>
#   read-valk-config.sh <parent>.<key>   # for nested keys (azure_devops.org)
#   read-valk-config.sh --repo <dir> <key>   # explicit repo dir
#
# Examples:
#   read-valk-config.sh pr_skill                  # → to-azure-pr (or empty)
#   read-valk-config.sh azure_devops.repository   # → RadiantAPI.Core
#
# Output: the value with trailing whitespace trimmed. No quotes added/removed.
#         Empty string + exit 0 if the file or key is absent. Exit non-zero
#         only on argv misuse or unreadable file.

set -u

REPO="$(pwd)"

PAIRS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --pairs) PAIRS=1; shift ;;   # #0009 — emit the loop: pairs list as records
    -h|--help)
      sed -n '2,20p' "$0"; exit 0 ;;
    *)
      if [ -z "${KEY:-}" ]; then
        KEY="$1"
      else
        echo "unexpected arg: $1" >&2; exit 2
      fi
      shift ;;
  esac
done

if [ -z "$PAIRS" ] && [ -z "${KEY:-}" ]; then
  echo "usage: read-valk-config.sh [--repo <dir>] (<key>[.<subkey>] | --pairs)" >&2
  exit 2
fi

CONFIG="$REPO/.claude/valk-config.md"

# Missing file = no opt-in. Empty output, exit 0 (not an error).
if [ ! -f "$CONFIG" ]; then
  exit 0
fi

# --pairs (#0009): extract the nested `loop: pairs:` list as one bash-parseable
# record per pair — `from=… critic=… max_iter=… [budget=… budget_mode=…]` (in
# that field order; budget fields omitted when absent). Empty output when there
# is no loop block / no pairs. The inner-loop orchestration (skill prose) reads
# these to re-run each pair's range until its critic passes.
if [ -n "$PAIRS" ]; then
  python3 - "$CONFIG" <<'PY' 2>/dev/null
import sys, re
text = open(sys.argv[1], encoding='utf-8').read()
m = re.match(r'\A---\s*\n(.*?)\n---\s*(?:\n|$)', text, re.DOTALL)
if not m:
    sys.exit(0)
pairs, cur = [], None
in_loop = in_pairs = False
for raw in m.group(1).splitlines():
    if not raw.strip() or raw.lstrip().startswith('#'):
        continue
    indent = len(raw) - len(raw.lstrip())
    s = raw.strip()
    if indent == 0:
        in_loop = s.startswith('loop:')
        in_pairs = False
        cur = None
        continue
    if not in_loop:
        continue
    if indent == 2:
        in_pairs = (s == 'pairs:')
        cur = None
        continue
    if in_pairs:
        if s.startswith('- '):
            cur = {}
            pairs.append(cur)
            s = s[2:].strip()
        if cur is not None and ':' in s:
            k, _, v = s.partition(':')
            cur[k.strip()] = v.strip().strip('"').strip("'")
ORDER = [('loop_back_to', 'from'), ('critic', 'critic'), ('max_iter', 'max_iter'),
         ('budget', 'budget'), ('budget_mode', 'budget_mode')]
for p in pairs:
    if not p.get('loop_back_to') or not p.get('critic'):
        continue
    print(' '.join(f'{out}={p[src]}' for src, out in ORDER if p.get(src, '') != ''))
PY
  exit 0
fi

# Use python3 to parse YAML frontmatter. Avoids depending on external yq.
# If python3 isn't available, fall back to awk for simple top-level keys
# (nested keys will return empty in that case).
python3 - "$CONFIG" "$KEY" <<'PY' 2>/dev/null
import sys, re

path, key = sys.argv[1], sys.argv[2]
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

# Extract frontmatter between first two --- lines.
m = re.match(r'\A---\s*\n(.*?)\n---\s*(?:\n|$)', text, re.DOTALL)
if not m:
    sys.exit(0)
front = m.group(1)

# Tiny YAML reader: top-level "key: value" and one level of nesting under
# "parent:" indented blocks. No flow style, no quoted strings beyond strip.
data = {}
current_parent = None
for raw in front.splitlines():
    line = raw.rstrip()
    if not line or line.lstrip().startswith('#'):
        continue
    if line.startswith(' ') or line.startswith('\t'):
        # Indented = belongs to current_parent
        if current_parent is None:
            continue
        stripped = line.strip()
        if ':' in stripped:
            k, _, v = stripped.partition(':')
            data.setdefault(current_parent, {})[k.strip()] = v.strip().strip('"').strip("'")
    else:
        # Top-level
        if ':' in line:
            k, _, v = line.partition(':')
            k, v = k.strip(), v.strip()
            if v == '':
                # parent of a nested block
                current_parent = k
                data.setdefault(k, {})
            else:
                data[k] = v.strip('"').strip("'")
                current_parent = None

# Lookup
if '.' in key:
    parent, _, child = key.partition('.')
    val = data.get(parent, {})
    if isinstance(val, dict):
        print(val.get(child, ''))
    else:
        print('')
else:
    val = data.get(key, '')
    if isinstance(val, dict):
        # Asked for a parent key — return empty (callers should use nested form).
        print('')
    else:
        print(val)
PY

# If python3 isn't on PATH, the heredoc above exits silently — caller gets
# empty output. That's the same as "key absent," which is the safe default
# (Valkyrie falls back to pre-config behavior).
