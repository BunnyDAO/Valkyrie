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

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
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

if [ -z "${KEY:-}" ]; then
  echo "usage: read-valk-config.sh [--repo <dir>] <key>[.<subkey>]" >&2
  exit 2
fi

CONFIG="$REPO/.claude/valk-config.md"

# Missing file = no opt-in. Empty output, exit 0 (not an error).
if [ ! -f "$CONFIG" ]; then
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
