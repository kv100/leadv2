#!/usr/bin/env bash
# Stop hook — PROMISE-GUARD-01: a promise in chat must not count as work.
#
# Reads the turn's final assistant text; if it ends on a forward-tense
# commitment («сейчас поднимаю наблюдателя», "I'll dispatch…") AND that same
# turn made ZERO state-changing tool calls, blocks once with a correction that
# quotes the unkept sentence, and appends a durable JSONL row so the rate is
# measurable. Past-tense reports carrying artifacts (sha / path / probe) are
# the DESIRED output and are never fired on.
#
# Unlike lead-prose-guard, this fires regardless of LEADV2_LEAD_GUARD,
# LEADV2_SUPERVISOR_MODE, or live-session count — the defect happens in plain
# chat turns too. Gating is: kill switch, stop_hook_active, once-per-turn
# sentinel. Nothing else. A guard that crashes must never wedge a session, so
# the ERR trap exits 0 (fail-open).

set -euo pipefail
trap 'echo "[$(basename "$0")] error at line $LINENO" >&2; exit 0' ERR

# --- kill switch -------------------------------------------------------------
[[ "${LEADV2_PROMISE_GUARD:-1}" == "1" ]] || exit 0

# --- read stdin --------------------------------------------------------------
INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0

# Parse the bits of the Stop-hook stdin JSON we need (python, fail-open).
META="$(printf '%s' "$INPUT" | python3 -c '
import sys, json
try:
    r = json.loads(sys.stdin.read())
except Exception:
    r = {}
print(r.get("session_id", "") or "")
print("yes" if r.get("stop_hook_active") else "no")
print(r.get("cwd", "") or "")
print(r.get("transcript_path", "") or "")
' 2>/dev/null || true)"

SESSION_ID="$(printf '%s' "$META" | sed -n '1p')"
STOP_ACTIVE="$(printf '%s' "$META" | sed -n '2p')"
CWD="$(printf '%s' "$META" | sed -n '3p')"
STDIN_TRANSCRIPT="$(printf '%s' "$META" | sed -n '4p')"

# --- anti-loop: canonical field ---------------------------------------------
[[ "$STOP_ACTIVE" == "yes" ]] && exit 0

# --- transcript resolution (env override > stdin > glob by session_id) ------
TRANSCRIPT="${LEADV2_PROMISE_GUARD_TRANSCRIPT:-}"
if [[ -z "$TRANSCRIPT" ]]; then
  TRANSCRIPT="$STDIN_TRANSCRIPT"
fi
if [[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]]; then
  if [[ -n "$SESSION_ID" ]]; then
    TRANSCRIPT="$(python3 -c "
import os, glob, sys
for p in glob.glob(os.path.expanduser('~/.claude/projects/*/' + sys.argv[1] + '.jsonl')):
    print(p); break
" "$SESSION_ID" 2>/dev/null || true)"
  fi
fi
[[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]] && exit 0

[[ -z "$SESSION_ID" ]] && SESSION_ID="unknown"
[[ -z "$CWD" ]] && CWD="$PWD"

# --- parse + detect (one python heredoc, stdlib only) -----------------------
# Reconciliation note: design §4b says split on [.!?\n;], but §4d note + test
# case 10 require «закоммитил 4eb4c304, сейчас поднимаю наблюдателя» to FIRE
# with quote = only the promise clause. A pure sentence split treats that as one
# sentence and the past-tense clause vetoes the whole thing (miss). We therefore
# evaluate at CLAUSE level (split sentences on [.!?\n;], then clauses on comma),
# so the past+artifact clause and the forward-promise clause are judged
# independently. The test assertion (case 10 fires) is ground truth.
VERDICT="$(python3 - "$TRANSCRIPT" <<'PYEOF' 2>/dev/null || true
import sys, json, re

jsonl_path = sys.argv[1]

# --- commitment shapes (one named block, editable) -------------------------
COMMIT_RU = r'приземляю|запускаю|поднимаю|диспатчу|начинаю|иду|сделаю|проверю|подниму|запущу|отправлю|дам|пойду|беру'
COMMIT_RU_NOW = r'сейчас\s+(?:же\s+)?(?:' + COMMIT_RU + r')'
COMMIT_EN = r"\bI'?ll\b|\bI will\b|\blet me\b|\bgoing to\b|\bnext I\b|\bnow I'?m\b|\bI'?m about to\b|\bwill now\b"

# PROMISE-GUARD-MORPHOLOGY-01: match the GRAMMATICAL SHAPE, not a verb dictionary.
#
# The hand-kept list above cannot work, and 2026-08-21 proved it on a real escape in
# ~/Projects/getmany-followup-bot: the lead ended a turn with "Чиню постраничную
# выборку Calendly" and "Ссылку на перебронирование добавлю тем же заходом", started
# neither, and the guard stayed silent — «чиню» and «добавлю» are simply not on the
# list. Russian verb morphology has no finite enumeration; every future escape will
# use a verb nobody thought to add. The founder reported the same shape in m3-market.
#
# The shape that actually carries a commitment is a FIRST-PERSON SINGULAR NON-PAST
# verb: in Russian that is a -ю/-у ending (present and future are identical in form
# — «чиню» and «добавлю» are both caught by one rule). Bare -ю/-у over-matches nouns
# in the accusative («выборку», «ссылку»), so the verb candidate must ALSO sit in a
# clause carrying a commitment marker — an intention adverbial («сейчас», «дальше»,
# «тем же заходом», «отдельно») — or be one of the known verbs above. That pairing is
# what keeps «Ссылку на перебронирование добавлю тем же заходом» a hit while
# «правлю выборку и вот результат 12/12» is not (the artifact vetoes it downstream).
RU_1SG_NONPAST = r'\b[а-яё]{3,}[юу]\b'
RU_INTENT_MARKER = (
    r'тем\s+же\s+заходом|следующим\s+заходом|этим\s+же\s+заходом'
    r'|сейчас|сразу|дальше|затем|потом|позже|после\s+этого|в\s+конце'
    r'|отдельно|заодно|попутно|по\s+ходу|ещё\s+раз|напоследок'
)
COMMIT_RU_SHAPE = r'(?=.*(?:' + RU_INTENT_MARKER + r'))(?=.*' + RU_1SG_NONPAST + r')'

COMMIT_RE = re.compile(
    '(?:' + COMMIT_RU_NOW + r'|' + COMMIT_RU + r'|' + COMMIT_EN + r'|' + COMMIT_RU_SHAPE + r')',
    re.I | re.UNICODE)

# A clause that is a bare first-person non-past verb with no marker at all is still a
# commitment when it OPENS the clause — «Чиню выборку…», «Довожу list-form…». Checked
# separately so the marker rule above stays strict.
COMMIT_RU_LEADING = re.compile(r'^\s*[«"\-—*]*\s*[а-яё]{3,}[юу]\b', re.I | re.UNICODE)

# --- past-tense / artifact veto --------------------------------------------
PAST_RU = r'\b\w+(?:л|ла|ло|ли)\b'
PAST_EN = r'\b(?:committed|shipped|pushed|landed|ran|wrote|fixed|added|done|merged|deployed|\w+ed)\b'
ARTIFACT = r'\b[0-9a-f]{7,40}\b|\b\d+/\d+\s+pass\b|^\s*(?:PASS|FAIL):|https?://|DELIVERABLE_COMPLETE|\S+\.(?:sh|py|ts|tsx|json|md|yaml):\d+'
VETO_RE = re.compile('(?:' + PAST_RU + r'|' + PAST_EN + r'|' + ARTIFACT + r')', re.I | re.UNICODE)

# --- action detection ------------------------------------------------------
ACTION_TOOL_NAMES = {'Edit', 'MultiEdit', 'Write', 'NotebookEdit',
                     'Agent', 'Workflow', 'SendMessage'}
ACTION_BASH_RE = re.compile(
    r'git\s+(?:commit|push|add|tag)'
    r'|leadv2-dispatch-code'
    r'|leadv2-fanout'
    r'|[A-Za-z0-9_-]*-task\.sh'
    r'|glm-coder\.sh'
    r'|leadv2-.*\.sh'
    r'|systemctl\s+(?:restart|start|enable)'
    r'|sed\s+-i'
    r'|\b(?:mv|cp|tee|touch|mkdir|install)\b'
    r'|>>?\s*\S',
    re.UNICODE)

def is_action_tool(name, bash_cmd=None):
    if name.startswith('Task'):
        return True
    if name in ACTION_TOOL_NAMES:
        return True
    if name == 'Bash' and bash_cmd:
        return bool(ACTION_BASH_RE.search(bash_cmd))
    return False

# --- turn reconstruction ---------------------------------------------------
# The turn = every assistant record since the last REAL user record.
turn_tools = []          # list of labels, e.g. "Bash:grep", "Edit", "Read"
has_action = False

# PROMISE-ACTION-BINDING-01 (2026-08-21): an action is only evidence that a promise
# was kept if it happened AFTER the promise was made.
#
# `has_action` scans the whole turn since the last user message, so a turn that does
# work A and then promises work B was silently suppressed: the guard saw an action
# and stayed quiet. That is exactly how a promise escaped today — the turn committed
# REVIEW-UNION-VERDICT-01 (a real action) and closed with "берусь за третье", which
# was never started. The founder caught it, not the guard.
#
# The binding rule is positional: count only actions that occur after the last
# non-empty assistant text block. A promise lives in that final text, and in this
# harness nothing follows it, so an unfulfilled promise has zero actions after it no
# matter how much work the turn did earlier.
action_positions = []
last_text_pos = -1
block_pos = 0
final_text_parts = []    # text blocks of the LAST assistant record

records = []
try:
    with open(jsonl_path, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except Exception:
                continue
except Exception:
    # fail-open: cannot read transcript -> never block
    print(json.dumps({'final_text_found': False, 'commitments': [],
                      'has_action': False, 'tools': []}))
    sys.exit(0)

def is_real_user_turn(rec):
    if rec.get('type') != 'user':
        return False
    msg = rec.get('message', {}) or {}
    content = msg.get('content')
    if isinstance(content, str):
        return bool(content.strip())
    if isinstance(content, list):
        # real only if at least one block is not a tool_result
        return any((not isinstance(b, dict)) or b.get('type') != 'tool_result'
                   for b in content)
    return False

# find index of last real user turn
boundary = -1
for i in range(len(records) - 1, -1, -1):
    if is_real_user_turn(records[i]):
        boundary = i
        break

turn_records = [r for r in records[boundary + 1:] if r.get('type') == 'assistant']

for rec in turn_records:
    content = (rec.get('message', {}) or {}).get('content', [])
    if not isinstance(content, list):
        continue
    for block in content:
        if not isinstance(block, dict):
            continue
        btype = block.get('type')
        if btype == 'tool_use':
            name = block.get('name', '') or ''
            inp = block.get('input', {}) or {}
            cmd = inp.get('command', '') if isinstance(inp, dict) else ''
            if name == 'Bash' and isinstance(cmd, str) and cmd:
                first = cmd.strip().split()[0] if cmd.strip() else 'bash'
                turn_tools.append('Bash:' + first)
            else:
                turn_tools.append(name)
            if is_action_tool(name, cmd if isinstance(cmd, str) else None):
                has_action = True
                # PROMISE-ACTION-BINDING-01: remember WHERE the action happened.
                action_positions.append(block_pos)
        if btype == 'text' and (block.get('text') or '').strip():
            last_text_pos = block_pos
        block_pos += 1

# final_text = text blocks of the LAST assistant record
if turn_records:
    last_content = (turn_records[-1].get('message', {}) or {}).get('content', [])
    if isinstance(last_content, list):
        final_text_parts = [b.get('text', '') for b in last_content
                            if isinstance(b, dict) and b.get('type') == 'text']

final_text = '\n'.join(final_text_parts).strip()

commitments = []
if final_text:
    # sentence split, then comma-clause split (see reconciliation note above)
    raw_clauses = []
    for sent in re.split(r'[.!?\n;]', final_text):
        sent = sent.strip()
        if not sent:
            continue
        for clause in sent.split(','):
            clause = clause.strip()
            if clause:
                raw_clauses.append(clause)
    for clause in raw_clauses:
        if (COMMIT_RE.search(clause) or COMMIT_RU_LEADING.match(clause)) \
                and not VETO_RE.search(clause):
            commitments.append(clause)

# Only actions AFTER the promise count as keeping it. Fail-open: if we could not
# locate a text block at all (unexpected transcript shape), fall back to the old
# turn-wide answer rather than firing on everyone.
if last_text_pos < 0:
    action_after_promise = has_action
else:
    action_after_promise = any(p > last_text_pos for p in action_positions)

print(json.dumps({
    'final_text_found': bool(final_text),
    'commitments': commitments,
    'has_action': action_after_promise,
    'has_action_anywhere_in_turn': has_action,
    'tools': turn_tools,
}, ensure_ascii=False))
PYEOF
)"

[[ -z "$VERDICT" ]] && exit 0

# Pull fields out of the verdict JSON (fail-open on any parse error).
VF="$(printf '%s' "$VERDICT" | python3 -c '
import sys, json
try:
    d = json.loads(sys.stdin.read())
except Exception:
    d = {}
print("yes" if d.get("final_text_found") else "no")
print("yes" if d.get("has_action") else "no")
print("|".join(d.get("tools", []) or []))
import json as _j
print(_j.dumps(d.get("commitments", []) or [], ensure_ascii=False))
' 2>/dev/null || true)"

FINAL_FOUND="$(printf '%s' "$VF" | sed -n '1p')"
HAS_ACTION="$(printf '%s' "$VF" | sed -n '2p')"
TOOLSJoined="$(printf '%s' "$VF" | sed -n '3p')"
COMMITMENTS_JSON="$(printf '%s' "$VF" | sed -n '4p')"

[[ "$FINAL_FOUND" == "yes" ]] || exit 0

# commitments present? (python list -> count)
N_COMMIT="$(printf '%s' "$COMMITMENTS_JSON" | python3 -c '
import sys, json
try:
    print(len(json.loads(sys.stdin.read())))
except Exception:
    print(0)
' 2>/dev/null || true)"
[[ "${N_COMMIT:-0}" -gt 0 ]] || exit 0   # no commitment shape -> silent, no log row

# --- determine verdict ------------------------------------------------------
if [[ "$HAS_ACTION" == "yes" ]]; then
  VERDICT_KIND="suppressed_action"
else
  VERDICT_KIND="fired"
fi

# first commitment clause = the quote
QUOTE="$(printf '%s' "$COMMITMENTS_JSON" | python3 -c '
import sys, json
try:
    arr = json.loads(sys.stdin.read())
    print((arr[0] if arr else "")[:280])
except Exception:
    print("")
' 2>/dev/null || true)"

# detect which pattern family matched the quote (for telemetry)
PATTERN="$(printf '%s' "$QUOTE" | python3 -c '
import sys, re
q = sys.stdin.read()
if re.search(r"сейчас\s+(?:же\s+)?(?:приземляю|запускаю|поднимаю|диспатчу|начинаю|иду|сделаю|проверю|подниму|запущу|отправлю|дам|пойду|беру)", q, re.I):
    print("COMMIT_RU_NOW")
elif re.search(r"(приземляю|запускаю|поднимаю|диспатчу|начинаю|иду|сделаю|проверю|подниму|запущу|отправлю|дам|пойду|беру)", q, re.I):
    print("COMMIT_RU")
else:
    print("COMMIT_EN")
' 2>/dev/null || true)"

# --- durable log (one row per evaluated turn with a commitment shape) -------
LOG="$HOME/.claude/leadv2-promise-guard.jsonl"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
TOOLS_LIST="$TOOLSJoined"
python3 -c '
import json, sys, os
row = {
    "ts": sys.argv[1],
    "session_id": sys.argv[2],
    "cwd": sys.argv[3],
    "verdict": sys.argv[4],
    "quote": sys.argv[5],
    "pattern": sys.argv[6],
    "tools": (sys.argv[7].split("|") if sys.argv[7] else []),
    "n_commitments": int(sys.argv[8] or 0),
}
path = os.path.expanduser("~/.claude/leadv2-promise-guard.jsonl")
with open(path, "a", encoding="utf-8") as f:
    f.write(json.dumps(row, ensure_ascii=False) + "\n")
' "$TS" "$SESSION_ID" "$CWD" "$VERDICT_KIND" "$QUOTE" "$PATTERN" "$TOOLS_LIST" "${N_COMMIT:-0}" 2>/dev/null || true

# suppressed by an action tool -> silent
[[ "$VERDICT_KIND" == "suppressed_action" ]] && exit 0

# --- block AT MOST ONCE per turn (sentinel, identical to prose-guard) -------
SENTINEL="$HOME/.claude/leadv2-promise-retry-${SESSION_ID}.txt"
if [[ -f "$SENTINEL" ]]; then
  # second Stop in the same turn -> pass through, no deadlock
  rm -f "$SENTINEL" 2>/dev/null || true
  exit 0
fi
printf '1\n' > "$SENTINEL" 2>/dev/null || true

# --- emit the correction (decision:block so the model gets one more turn) ---
python3 - "$QUOTE" "$TOOLS_LIST" <<'PYEOF'
import sys, json
quote = sys.argv[1]
tools_raw = sys.argv[2]
tools = ([t for t in tools_raw.split("|")] if tools_raw else [])
tools_str = ", ".join(tools) if tools else "(none)"
reason = (
    "PROMISE-GUARD: you ended the turn on a commitment with zero "
    "state-changing calls.\n"
    "Unkept: \"" + quote + "\"\n"
    "This turn's tools: " + tools_str + ".\n"
    "Either make the call now, or restate in past tense with the artifact "
    "(sha / path / probe output). A promise in chat is not work."
)
print(json.dumps({"decision": "block", "reason": reason}, ensure_ascii=False))
PYEOF
exit 0
