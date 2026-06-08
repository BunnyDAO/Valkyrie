#!/usr/bin/env bash
#
# parse-loop-verdict.sh <file>   (or stdin) — read a loop critic's output and
# print its verdict: pass | fail | stop (#0009). Scans for fenced
# ```loop-verdict``` blocks and uses the LAST one (the model's final word),
# parsing the JSON `status`; falls back to a loose `"status": "<v>"` match.
# Exit 0 + the verdict when found; non-zero + empty output otherwise (the caller
# treats "no verdict" as a non-decision). Mirrors the arena parseLoopVerdict.
set -u

SRC="${1:--}"
[ "$SRC" = "-" ] && SRC="/dev/stdin"

python3 - "$SRC" <<'PY' 2>/dev/null
import sys, re, json
data = open(sys.argv[1], encoding='utf-8').read()
blocks = re.findall(r'```loop-verdict\s*(.*?)```', data, re.DOTALL)
if not blocks:
    sys.exit(1)
body = blocks[-1].strip()
status = None
try:
    obj = json.loads(body)
    if isinstance(obj, dict):
        status = obj.get('status')
except Exception:
    pass
if status not in ('pass', 'fail', 'stop'):
    m = re.search(r'"?status"?\s*[:=]\s*"?(pass|fail|stop)"?', body, re.I)
    status = m.group(1).lower() if m else None
if status in ('pass', 'fail', 'stop'):
    print(status)
    sys.exit(0)
sys.exit(1)
PY
