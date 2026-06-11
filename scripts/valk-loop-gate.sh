#!/usr/bin/env bash
# Valkyrie Stop-hook loop gate — mechanical inner-loop route-back (#0030).
#
# The inner Looper was honor-based: the valk skill's prose says "on a fail
# verdict, re-run the range from <from>", and the model chooses to obey. This
# hook turns the route-back into a MECHANICAL block: when the session tries to
# stop while the LAST loop-verdict in the transcript is `fail` and the pair has
# iterations left, the stop is DENIED with the route-back instruction as the
# reason — the orchestrator must re-run the range. Iterations are counted in a
# per-session ledger so `max_iter` is a hard stop, not a suggestion.
#
# Verdict semantics (the forged loop_verdict_contract primitive):
#   pass → allow stop; the pair's ledger entry resets.
#   fail → BLOCK (route back to <from>) until the ledger hits max_iter.
#   stop → allow stop (escalate to the human — that is the point of `stop`).
#
# Honest limits: per-pair USD budget stays advisory (hooks see no cost data —
# afk's global --max-cost-usd is the hard money stop). Ambiguity is permissive:
# no valk-config, no pairs, no verdict, or an unattributable verdict → allow.
# Threat model is model drift, not a determined human (it's the user's machine).
#
# Wired in settings.json under hooks.Stop (install.sh does this).

set -u

INPUT=$(cat)

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""')
[[ -z "$CWD" ]] && CWD="$PWD"
CONFIG="$CWD/.claude/valk-config.md"
[[ -f "$CONFIG" ]] || exit 0   # not a crew repo → nothing to enforce

TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""')
[[ -f "$TRANSCRIPT" ]] || exit 0
SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // "session"')

LEDGER_DIR="$CWD/.claude/valk"
LEDGER="$LEDGER_DIR/loop-ledger.json"
mkdir -p "$LEDGER_DIR" 2>/dev/null || exit 0

python3 - "$CONFIG" "$TRANSCRIPT" "$LEDGER" "$SESSION" <<'PY' 2>/dev/null
import json, re, sys

config_path, transcript_path, ledger_path, session = sys.argv[1:5]

# ---- pairs from valk-config.md frontmatter (mirrors read-valk-config --pairs) ----
text = open(config_path, encoding='utf-8').read()
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
        in_loop = s.startswith('loop:'); in_pairs = False; cur = None
        continue
    if not in_loop:
        continue
    if indent == 2:
        in_pairs = (s == 'pairs:'); cur = None
        continue
    if in_pairs:
        if s.startswith('- '):
            cur = {}; pairs.append(cur); s = s[2:].strip()
        if cur is not None and ':' in s:
            k, _, v = s.partition(':')
            cur[k.strip()] = v.strip().strip('"').strip("'")
pairs = [p for p in pairs if p.get('loop_back_to') and p.get('critic')]
if not pairs:
    sys.exit(0)

# ---- last loop-verdict anywhere in the transcript (assistant text or tool results) ----
def strings(node):
    if isinstance(node, str):
        yield node
    elif isinstance(node, dict):
        for v in node.values():
            yield from strings(v)
    elif isinstance(node, list):
        for v in node:
            yield from strings(v)

last = None  # (status, critic)
fence = re.compile(r'```loop-verdict\s*(.*?)```', re.DOTALL)
try:
    with open(transcript_path, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or 'loop-verdict' not in line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            for s in strings(obj):
                for body in fence.findall(s):
                    status = critic = None
                    try:
                        v = json.loads(body.strip())
                        if isinstance(v, dict):
                            status = v.get('status'); critic = v.get('critic')
                    except Exception:
                        pass
                    if status not in ('pass', 'fail', 'stop'):
                        sm = re.search(r'"?status"?\s*[:=]\s*"?(pass|fail|stop)"?', body, re.I)
                        status = sm.group(1).lower() if sm else None
                    if critic is None:
                        cm = re.search(r'"?critic"?\s*[:=]\s*"([^"]+)"', body)
                        critic = cm.group(1) if cm else None
                    if status:
                        last = (status, critic)
except OSError:
    sys.exit(0)
if last is None:
    sys.exit(0)
status, critic = last

# ---- attribute the verdict to a pair (permissive on ambiguity) ----
pair = None
if critic:
    matches = [p for p in pairs if p['critic'] == critic]
    pair = matches[-1] if matches else None
if pair is None and len(pairs) == 1:
    pair = pairs[0]
if pair is None:
    sys.exit(0)

key = f"{pair['loop_back_to']}→{pair['critic']}"
try:
    max_iter = int(pair.get('max_iter', '0') or 0)
except ValueError:
    max_iter = 0

# ---- per-session iteration ledger ----
ledger = {}
try:
    ledger = json.loads(open(ledger_path, encoding='utf-8').read())
    if not isinstance(ledger, dict):
        ledger = {}
except Exception:
    ledger = {}
if ledger.get('session') != session:
    ledger = {'session': session, 'iters': {}}   # fresh session → fresh counts
iters = ledger.setdefault('iters', {})

def save():
    try:
        open(ledger_path, 'w', encoding='utf-8').write(json.dumps(ledger) + '\n')
    except OSError:
        pass

if status == 'pass':
    if key in iters:
        del iters[key]; save()
    sys.exit(0)
if status == 'stop':
    sys.exit(0)   # escalation to the human IS the stop — allow it

# status == fail
done = int(iters.get(key, 0))
if max_iter > 0 and done >= max_iter:
    sys.exit(0)   # exhausted — allow the stop (surface to the human)
iters[key] = done + 1
save()
reason = (
    f"Valkyrie loop gate: {pair['critic']} returned a `fail` loop-verdict "
    f"(iteration {done + 1}/{max_iter or '?'}). Route back: re-run the range from "
    f"{pair['loop_back_to']} through {pair['critic']}, applying the critic's message as the brief, "
    f"then have {pair['critic']} re-evaluate and end with a fenced loop-verdict block. "
    f"Do not stop until the verdict is pass/stop or max_iter is exhausted."
)
print(json.dumps({'decision': 'block', 'reason': reason}))
sys.exit(0)
PY
exit 0
