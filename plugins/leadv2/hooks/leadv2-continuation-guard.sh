#!/usr/bin/env bash
# Stop hook — CONTINUATION-GUARD-01: silence in chat must never mean "done".
#
# During an active leadv2 task the lead answers a founder question, then goes
# silent — no continuation, no notification.  The founder reads silence as
# "everything finished".  Nothing prevented this (audit defect 3).
#
# This hook fires on Stop: if an active task exists (active.yaml sessions
# non-empty, or LEADV2_TASK_ID env with no phase8-passed.flag) AND the ending
# turn made zero state-changing tool calls, it BLOCKS once with a message
# naming the active task + its phase and demanding either:
#   (a) a state-changing call / dispatched worker / armed watcher this turn, or
#   (b) an explicit final line "работа продолжается: <что ждём>" /
#       "задача закрыта: <артефакт>".
#
# Kill switch: LEADV2_CONTINUATION_GUARD=0.
# Loop safety: never blocks twice in a row for the same turn — uses
#   stop_hook_active (canonical anti-loop field) plus a per-session sentinel
#   file so a hook fight cannot deadlock the session.
# Fail-open: a guard that crashes must never wedge a session, so the ERR trap
#   exits 0.
#
# Pattern modelled on leadv2-promise-guard.sh (Stop hook, same sentinel/loop
# approach) but plugin-generic: no PE paths, no persona-engine assumptions.

set -euo pipefail
trap 'echo "[$(basename "$0")] error at line $LINENO" >&2; exit 0' ERR

# --- kill switch -------------------------------------------------------------
[[ "${LEADV2_CONTINUATION_GUARD:-1}" == "1" ]] || exit 0

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

# --- anti-loop: canonical field ----------------------------------------------
[[ "$STOP_ACTIVE" == "yes" ]] && exit 0

# --- per-session sentinel (second line of defence) ---------------------------
# If we already blocked this session-turn once, pass through. The sentinel
# is written AFTER the block decision and cleared on the next invocation,
# so a re-Stop (model retry) is allowed but a tight hook fight is not.
[[ -z "$SESSION_ID" ]] && SESSION_ID="unknown"
SENTINEL="${LEADV2_CONTINUATION_GUARD_SENTINEL_DIR:-/tmp}/.leadv2-continuation-guard.${SESSION_ID}"
if [[ -f "$SENTINEL" ]]; then
  rm -f "$SENTINEL" 2>/dev/null || true
  exit 0
fi

[[ -z "$CWD" ]] && CWD="$PWD"

# --- transcript resolution (env override > stdin > glob by session_id) --------
TRANSCRIPT="${LEADV2_CONTINUATION_GUARD_TRANSCRIPT:-}"
if [[ -z "$TRANSCRIPT" ]]; then
  TRANSCRIPT="$STDIN_TRANSCRIPT"
fi
if [[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]]; then
  if [[ -n "$SESSION_ID" && "$SESSION_ID" != "unknown" ]]; then
    TRANSCRIPT="$(python3 -c "
import os, glob, sys
for p in glob.glob(os.path.expanduser('~/.claude/projects/*/' + sys.argv[1] + '.jsonl')):
    print(p); break
" "$SESSION_ID" 2>/dev/null || true)"
  fi
fi
# No transcript → cannot check tool calls → fail-open.
[[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]] && exit 0

# --- evaluate in one Python heredoc (stdlib only, fail-open) -----------------
# Returns a JSON verdict with:
#   active_task: bool    — an active, non-closed leadv2 task exists
#   task_id: str         — the task id (for the block message)
#   phase: str           — the task's current phase
#   has_action: bool     — the ending turn made ≥1 state-changing tool call
#   has_continuation: bool — final text contains an explicit continuation/close line
VERDICT="$(python3 - "$CWD" "$TRANSCRIPT" <<'PYEOF' 2>/dev/null || true
import sys, os, json, re

cwd       = sys.argv[1]
jsonl_path = sys.argv[2]

# ── 1. Active-task detection ──────────────────────────────────────────────
task_id  = ""
phase    = ""
active   = False

# Path 1: LEADV2_TASK_ID env without phase8-passed.flag
env_tid = os.environ.get("LEADV2_TASK_ID", "").strip()
if env_tid:
    handoff = os.path.join(cwd, "docs", "handoff", env_tid)
    tasks_d = os.path.join(cwd, "docs", "leadv2", "tasks", env_tid)
    # Check all known flag locations for phase8/phase11 close
    closed = False
    for d in (handoff, tasks_d):
        for flag in ("phase8-passed.flag", "phase11-passed.flag"):
            if os.path.isfile(os.path.join(d, flag)):
                closed = True
                break
        if closed:
            break
    if not closed:
        active   = True
        task_id  = env_tid
        phase    = os.environ.get("LEADV2_TASK_PHASE", "")

# Path 2: active.yaml sessions non-empty (only if env path didn't fire)
if not active:
    for yaml_path in (
        os.path.join(cwd, "docs", "leadv2", "active.yaml"),
        os.path.join(cwd, ".claude", "leadv2-tasks", "active.yaml"),
    ):
        if not os.path.isfile(yaml_path):
            continue
        try:
            import yaml as _y
            with open(yaml_path, encoding="utf-8") as fh:
                data = _y.safe_load(fh) or {}
        except Exception:
            break  # can't parse → don't try the fallback either
        sessions = data.get("sessions") or []
        if not sessions:
            break
        for sess in sessions:
            sid  = (sess.get("task_id") or "").strip()
            sph  = (sess.get("phase") or "").strip()
            if not sid:
                continue
            # Check if this session's task is closed
            h_dir = os.path.join(cwd, "docs", "handoff", sid)
            t_dir = os.path.join(cwd, "docs", "leadv2", "tasks", sid)
            sess_closed = False
            for d in (h_dir, t_dir):
                for flag in ("phase8-passed.flag", "phase11-passed.flag"):
                    if os.path.isfile(os.path.join(d, flag)):
                        sess_closed = True
                        break
                if sess_closed:
                    break
            if not sess_closed:
                active  = True
                task_id = sid
                phase   = sph
                break
        break

if not active:
    print(json.dumps({"active_task": False, "task_id": "", "phase": "",
                      "has_action": False, "has_continuation": False}))
    sys.exit(0)

# ── 2. Turn reconstruction (same logic as promise-guard) ──────────────────
ACTION_TOOL_NAMES = {'Edit', 'MultiEdit', 'Write', 'NotebookEdit',
                     'Agent', 'Workflow', 'SendMessage', 'Monitor',
                     'TaskCreate', 'TaskUpdate'}
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

# Read transcript
records = []
try:
    with open(jsonl_path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except Exception:
                continue
except Exception:
    print(json.dumps({"active_task": True, "task_id": task_id, "phase": phase,
                      "has_action": False, "has_continuation": False}))
    sys.exit(0)

def is_real_user_turn(rec):
    if rec.get('type') != 'user':
        return False
    msg = rec.get('message', {}) or {}
    content = msg.get('content')
    if isinstance(content, str):
        return bool(content.strip())
    if isinstance(content, list):
        return any((not isinstance(b, dict)) or b.get('type') != 'tool_result'
                   for b in content)
    return False

# Find index of last real user turn
boundary = -1
for i in range(len(records) - 1, -1, -1):
    if is_real_user_turn(records[i]):
        boundary = i
        break

turn_records = [r for r in records[boundary + 1:] if r.get('type') == 'assistant']

has_action = False
final_text_parts = []

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
            inp  = block.get('input', {}) or {}
            cmd  = inp.get('command', '') if isinstance(inp, dict) else ''
            if is_action_tool(name, cmd if isinstance(cmd, str) else None):
                has_action = True

# Final text = text blocks of the LAST assistant record
if turn_records:
    last_content = (turn_records[-1].get('message', {}) or {}).get('content', [])
    if isinstance(last_content, list):
        final_text_parts = [b.get('text', '') for b in last_content
                            if isinstance(b, dict) and b.get('type') == 'text']

final_text = '\n'.join(final_text_parts).strip()

# ── 3. Continuation/close phrase detection ────────────────────────────────
# The model can exempt itself by ending with an explicit status line.
CONTINUATION_RE = re.compile(
    r'(?:работа\s+продолжается|задача\s+закрыта|continuing|task\s+closed'
    r'|pending|waiting\s+on|DELIVERABLE_COMPLETE|NOT-COMMITTED)',
    re.I | re.UNICODE)

has_continuation = bool(final_text and CONTINUATION_RE.search(final_text))

print(json.dumps({
    "active_task": True,
    "task_id": task_id,
    "phase": phase,
    "has_action": has_action,
    "has_continuation": has_continuation,
}, ensure_ascii=False))
PYEOF
)"

[[ -z "$VERDICT" ]] && exit 0

# Pull fields from verdict JSON.
VF="$(printf '%s' "$VERDICT" | python3 -c '
import sys, json
try:
    d = json.loads(sys.stdin.read())
except Exception:
    d = {}
print("yes" if d.get("active_task") else "no")
print(d.get("task_id", "") or "")
print(d.get("phase", "") or "")
print("yes" if d.get("has_action") else "no")
print("yes" if d.get("has_continuation") else "no")
' 2>/dev/null || true)"

ACTIVE_TASK="$(printf '%s' "$VF" | sed -n '1p')"
TASK_ID_OUT="$(printf '%s' "$VF" | sed -n '2p')"
PHASE_OUT="$(printf '%s' "$VF" | sed -n '3p')"
HAS_ACTION="$(printf '%s' "$VF" | sed -n '4p')"
HAS_CONTINUATION="$(printf '%s' "$VF" | sed -n '5p')"

# No active task → pass through.
[[ "$ACTIVE_TASK" == "yes" ]] || exit 0

# Had a state-changing tool call → pass through.
[[ "$HAS_ACTION" == "yes" ]] && exit 0

# Ended with an explicit continuation/close line → pass through.
[[ "$HAS_CONTINUATION" == "yes" ]] && exit 0

# --- BLOCK: write sentinel, emit decision ------------------------------------
printf '1\n' > "$SENTINEL" 2>/dev/null || true

python3 - "$TASK_ID_OUT" "$PHASE_OUT" <<'PYEOF'
import sys, json

task_id = sys.argv[1]
phase   = sys.argv[2]
phase_str = (" (фаза: %s)" % phase) if phase else ""

reason = (
    "CONTINUATION-GUARD: активная задача %s%s ещё не закрыта, "
    "но этот ход не сделал ни одного state-changing вызова "
    "(Edit / Write / Bash-commit / Agent / Monitor).\n\n"
    " Silence ≠ done. Сделайте одно из двух:\n"
    "  (a) сделайте вызов сейчас (dispatch / edit / watcher), или\n"
    "  (b) напишите финальной строкой:\n"
    '      "работа продолжается: <что ждём>" или\n'
    '      "задача закрыта: <артефакт>"\n'
    % (task_id, phase_str)
)
print(json.dumps({"decision": "block", "reason": reason}, ensure_ascii=False))
PYEOF
