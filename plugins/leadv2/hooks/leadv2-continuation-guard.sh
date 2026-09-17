#!/usr/bin/env bash
# Stop hook — CONTINUATION-GUARD-01: silence in chat must never mean "done".
#
# During an active leadv2 task the lead answers a founder question, then goes
# silent — no continuation, no notification.  The founder reads silence as
# "everything finished".  Nothing prevented this (audit defect 3).
#
# This hook fires on Stop: if an active task exists (active.yaml sessions
# non-empty, or LEADV2_TASK_ID env with no phase8-passed.flag) AND nothing
# will wake this session while it sleeps, it BLOCKS once with a message
# naming the active task + its phase and demanding either:
#   (a) a WAKER — something that fires without the lead:
#         w1  a live lane/worker/dispatcher process attributable to this
#             session (registry row not stale/dead/terminal, pid alive with
#             pid_birth matching `ps -o lstart=`, pid outside this hook's
#             ancestry, process cwd under the row's worktree);
#         w2  a live harness-tracked background command (a tasks/*.output
#             under this session's tasks dir still open for WRITE — its
#             completion will notify);
#         w3  a fresh armed-watcher sentinel file (the lead's attestation
#             that a Monitor is armed; JSON with armed_at/expires_at whose
#             horizon is capped so a forgotten sentinel self-destructs); or
#   (b) only the missing continuation/close line — never a restatement of
#       already-rendered text.
#
# A tool call is NOT a waker (CONTINUATION-GUARD-PASSES-ANY-TURN-THAT-
# TOUCHED-A-TOOL-01, 2026-09-17): work proves the turn acted, not that
# anything will wake the session again. Measured that day: the lead ran a
# full turn of tool calls, passed this guard, and three finished lanes sat
# dead for six hours — every Monitor had expired and no background job was
# live.
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
#   has_tool_call: bool  — the ending turn made ≥1 tool call (context only —
#                          no longer a pass by itself, see header)
#   has_continuation: bool — final text contains an explicit continuation/close line
#   waker_any: bool      — w1|w2|w3: something will wake this session
VERDICT="$(python3 - "$CWD" "$TRANSCRIPT" "$SESSION_ID" <<'PYEOF' 2>/dev/null || true
import sys, os, json, re, subprocess, time, glob

cwd       = sys.argv[1]
jsonl_path = sys.argv[2]
session_id = sys.argv[3] if len(sys.argv) > 3 else ""

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
            # TERMINAL-LANES-STILL-READ-AS-LIVE-01: a lane that recorded a
            # terminal outcome is finished, whatever its `phase` still says.
            # Only 2 of 106 readers of active.yaml knew this field existed, so a
            # closed lane kept being named as the active task. The closed-flag
            # test below is the same idea via the filesystem; this is the same
            # idea via the registry's own record. Both must clear the lane.
            # LANE-REGISTRY-GHOSTS-20260907: this is the third reader caught by
            # the same blindness -- terminal_status is written only by
            # active-registry.sh/lane-heartbeat.sh; lib/leadv2-lane-state.sh
            # marks death via dead_at instead and never sets terminal_status.
            # Check both; dead_at resets to None on re-registration/recovery so
            # a revived lane still blocks a silent end-of-turn.
            if (sess.get("terminal_status") or "").strip() or sess.get("dead_at"):
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
                      "has_tool_call": False, "has_continuation": False}))
    sys.exit(0)

# ── 2. Turn reconstruction (same logic as promise-guard) ──────────────────
# Read transcript. T16 §6 (LEAD-FINAL-FIXES-01) fast path: the verdict only
# ever evaluates records AFTER the last real user turn, but this used to
# parse the ENTIRE transcript — every Stop of every session in a repo with
# an active task (workers included: multi-MB streams) paid a full JSON
# re-parse to answer a question about the last turn. Load a bounded TAIL
# window first; only when the file was truncated AND the window contains no
# real user turn (one turn larger than the window) fall back to the full
# parse. The evaluated records are identical either way.
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

TAIL_WINDOW_BYTES = 262144

def _load_records(path):
    """Tail-bounded transcript load with full-file fallback (T16 §6)."""
    out = []
    truncated = False
    try:
        size = os.path.getsize(path)
        truncated = size > TAIL_WINDOW_BYTES
        with open(path, encoding="utf-8") as f:
            if truncated:
                f.seek(size - TAIL_WINDOW_BYTES)
                f.readline()  # drop the partial line the seek landed in
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    out.append(json.loads(line))
                except Exception:
                    continue
    except Exception:
        return None, False
    return out, truncated

records, _truncated = _load_records(jsonl_path)
if records is None:
    # fail-open: cannot read transcript -> never block
    print(json.dumps({"active_task": True, "task_id": task_id, "phase": phase,
                      "has_tool_call": False, "has_continuation": False}))
    sys.exit(0)
if _truncated and not any(is_real_user_turn(r) for r in records):
    # the whole current turn sits above the window — re-read the full file
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
        records = []

# Find index of last real user turn
boundary = -1
for i in range(len(records) - 1, -1, -1):
    if is_real_user_turn(records[i]):
        boundary = i
        break

turn_records = [r for r in records[boundary + 1:] if r.get('type') == 'assistant']

def ending_turn_has_tool_call(records):
    has_tool_call = False
    for rec in records:
        content = (rec.get('message', {}) or {}).get('content', [])
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict):
                continue
            btype = block.get('type')
            if btype == 'tool_use':
                # A completed probe is work: the guard detects a quiet stop, not
                # merely a lack of mutations (CONTINUATION-GUARD-DOUBLES-01).
                has_tool_call = True
    return has_tool_call

has_tool_call = ending_turn_has_tool_call(turn_records)
final_text_parts = []

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

# ── 4. Waker probe (CONTINUATION-GUARD-PASSES-ANY-TURN-THAT-TOUCHED-A-TOOL-01)
# A tool call proves the ending turn did work; it does not prove the session
# will ever wake again. Waking requires something that FIRES while the
# session sleeps: a background command completing, a Monitor event, a
# Monitor expiry. Three wakers are recognisable from a Stop hook:
#   w1  live lane/worker/dispatcher process attributable to this session —
#       registry row not stale/dead/terminal, pid alive, pid_birth matching
#       `ps -o lstart=` (a reused pid cannot ghost a lane alive), pid not in
#       this hook's ancestry, process cwd under the row's worktree;
#   w2  live harness-tracked background command — a *.output under this
#       session's tasks dir still held open for WRITE by a live process
#       (its completion will notify). Read-mode holders (monitor tails) and
#       producer heartbeats attest nothing: an expired Monitor leaves no
#       relay, and a live producer nobody relays IS the 2026-09-17
#       six-hour silence;
#   w3  fresh armed-watcher sentinel — the lead's attestation that a Monitor
#       is armed: JSON {kind, watching, armed_at, expires_at} at
#       $LEADV2_GUARD_WATCH_DIR (default ~/.claude/leadv2-state/leadv2/
#       watchers — control plane, never the repo) / <session_id>.watch.json.
#       Fresh = expires_at in the future AND expires_at <= armed_at +
#       LEADV2_GUARD_SENTINEL_MAX_HORIZON_S (default 3600), so a forgotten
#       sentinel self-destructs instead of re-creating this bug elsewhere.
# Every probe step fails toward "no waker" — never toward pass: the escapes
# (sentinel/continuation line, one-block-max anti-loop sentinel) keep a
# false block recoverable, while a false pass is the six-hour silence.

w1 = False
w2 = False
w3 = False
waker_detail = ""

_probe_deadline = time.monotonic() + 2.0

def _probe_left():
    return time.monotonic() < _probe_deadline

def _probe_run(cmd, timeout=1.0):
    try:
        return subprocess.run(cmd, capture_output=True, text=True,
                              timeout=timeout).stdout or ""
    except Exception:
        return ""

def _norm_ws(s):
    return " ".join((s or "").split())

# This hook's ancestry: registry rows naming our own harness process are the
# session itself, not a lane working on its behalf.
_ancestry = set()
_ap = os.getpid()
for _ in range(32):
    if _ap <= 1:
        break
    _ancestry.add(_ap)
    _ppid_out = _probe_run(["ps", "-o", "ppid=", "-p", str(_ap)])
    try:
        _ap = int(_ppid_out.split()[0])
    except Exception:
        break

# ── w1: live lane/worker/dispatcher process ───────────────────────────────
_env_regs = os.environ.get("LEADV2_GUARD_REGISTRIES", "").strip()
if _env_regs:
    _reg_paths = [p for p in _env_regs.split(":") if p]
else:
    _reg_paths = [
        os.path.join(os.path.expanduser("~"), ".claude", "leadv2-state",
                     "leadv2", "active.yaml"),
        os.path.join(cwd, "docs", "leadv2", "active.yaml"),
        os.path.join(cwd, ".claude", "leadv2-tasks", "active.yaml"),
    ]
try:
    import yaml as _wy
except Exception:
    _wy = None
if _wy is not None:
    for _rp in _reg_paths:
        if w1 or not _probe_left():
            break
        try:
            with open(_rp, encoding="utf-8") as _fh:
                _rows = (_wy.safe_load(_fh) or {}).get("sessions") or []
        except Exception:
            continue
        for _row in _rows[:200]:
            if w1 or not _probe_left():
                break
            try:
                if (_row.get("terminal_status") or "").strip() \
                        or _row.get("dead_at") or _row.get("stale"):
                    continue
                _pid = int(_row.get("pid") or 0)
                if _pid <= 1 or _pid in _ancestry:
                    continue
                _lstart = _norm_ws(_probe_run(
                    ["ps", "-o", "lstart=", "-p", str(_pid)]))
                if not _lstart:
                    continue  # pid not alive
                _birth = _norm_ws(_row.get("pid_birth") or "")
                if _birth and _birth != _lstart:  # cg-mut-M3: reused-pid ghost gate
                    continue
                _wt = (_row.get("worktree") or "").strip()
                if not _wt:
                    continue
                _pcwd = ""
                for _ln in _probe_run(["lsof", "-a", "-p", str(_pid),
                                       "-d", "cwd", "-Fn"]).splitlines():
                    if _ln.startswith("n"):
                        _pcwd = _ln[1:].strip()
                # lsof reports the RESOLVED cwd (/private/var/... on macOS);
                # registry rows often carry the symlinked form (/var/...).
                # Compare both sides resolved.
                _wt = os.path.realpath(_wt)
                _pcwd = os.path.realpath(_pcwd) if _pcwd else ""
                if not (_pcwd == _wt or _pcwd.startswith(_wt.rstrip("/") + "/")):
                    continue
                w1 = True
                waker_detail = "w1: live lane/worker %s (pid %s)" % (
                    (_row.get("task_id") or "?"), _pid)
            except Exception:
                continue

# ── w2: live harness-tracked background command ───────────────────────────
_tasks_dir = os.environ.get("LEADV2_GUARD_TASKS_DIR", "").strip()
if not _tasks_dir and session_id and session_id != "unknown":
    _slug = os.path.basename(os.path.dirname(jsonl_path))
    _uid = os.getuid()
    for _base in ("/private/tmp", "/tmp", os.environ.get("TMPDIR", "")):
        _base = _base.rstrip("/")
        if not _base:
            continue
        _cand = os.path.join(_base, "claude-%d" % _uid, _slug,
                             session_id, "tasks")
        if os.path.isdir(_cand):
            _tasks_dir = _cand
            break
if _tasks_dir and os.path.isdir(_tasks_dir) and _probe_left():
    for _of in sorted(glob.glob(os.path.join(_tasks_dir, "*.output")))[:20]:
        if w2 or not _probe_left():
            break
        for _ln in _probe_run(["lsof", "-w", _of],
                              timeout=1.5).splitlines()[1:]:
            _parts = _ln.split()
            if len(_parts) < 4:
                continue
            # fd column like 1w / 2w / 3u — WRITE-holders only; a plain
            # reader (a monitor tail) is not a completion notification.
            _fd = _parts[3]
            _is_write = len(_fd) >= 2 and _fd[0].isdigit() and _fd[1] in ("w", "u")  # cg-mut-M4: write-holder gate
            if _is_write:
                w2 = True
                waker_detail = ("w2: live background task output %s"
                                % os.path.basename(_of))
                break

# ── w3: fresh armed-watcher sentinel ──────────────────────────────────────
_watch_dir = os.environ.get("LEADV2_GUARD_WATCH_DIR", "").strip() or os.path.join(
    os.path.expanduser("~"), ".claude", "leadv2-state", "leadv2", "watchers")
_sent_path = os.path.join(_watch_dir, "%s.watch.json" % (session_id or "unknown"))
try:
    from datetime import datetime, timedelta, timezone
    with open(_sent_path, encoding="utf-8") as _fh:
        _sent = json.loads(_fh.read())
    _now_dt = datetime.now(timezone.utc)

    def _parse_iso(s):
        return datetime.fromisoformat(str(s).replace("Z", "+00:00"))

    _armed = _parse_iso(_sent.get("armed_at", ""))
    _exp = _parse_iso(_sent.get("expires_at", ""))
    _horizon = float(os.environ.get("LEADV2_GUARD_SENTINEL_MAX_HORIZON_S",
                                    "3600"))
    _fresh = (_exp > _now_dt) and (_exp.timestamp() <= _armed.timestamp() + _horizon) and (_armed <= _now_dt + timedelta(seconds=300))  # cg-mut-M2: sentinel freshness gate
    if _fresh:
        w3 = True
        waker_detail = "w3: armed-watcher sentinel %s (expires %s)" % (
            os.path.basename(_sent_path), _sent.get("expires_at"))
except Exception:
    w3 = False

waker_any = w1 or w2 or w3  # cg-mut-M1: waker aggregation

print(json.dumps({
    "active_task": True,
    "task_id": task_id,
    "phase": phase,
    "has_tool_call": has_tool_call,
    "has_continuation": has_continuation,
    "w1": w1,
    "w2": w2,
    "w3": w3,
    "waker_any": waker_any,
    "waker_detail": waker_detail,
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
print("yes" if d.get("has_tool_call") else "no")
print("yes" if d.get("has_continuation") else "no")
print("yes" if d.get("waker_any") else "no")
print(d.get("waker_detail", "") or "")
' 2>/dev/null || true)"

ACTIVE_TASK="$(printf '%s' "$VF" | sed -n '1p')"
TASK_ID_OUT="$(printf '%s' "$VF" | sed -n '2p')"
PHASE_OUT="$(printf '%s' "$VF" | sed -n '3p')"
HAS_TOOL_CALL="$(printf '%s' "$VF" | sed -n '4p')"
HAS_CONTINUATION="$(printf '%s' "$VF" | sed -n '5p')"
WAKER_ANY="$(printf '%s' "$VF" | sed -n '6p')"
WAKER_DETAIL="$(printf '%s' "$VF" | sed -n '7p')"

# No active task → pass through.
[[ "$ACTIVE_TASK" == "yes" ]] || exit 0

# A waker exists → pass through. Something will fire while the session
# sleeps: a live lane/worker process (w1), a live background command whose
# completion will notify (w2), or a fresh armed-watcher sentinel (w3).
# CONTINUATION-GUARD-PASSES-ANY-TURN-THAT-TOUCHED-A-TOOL-01: a tool call is
# deliberately NOT on this list any more — work proves the turn acted, not
# that anything will wake the session again.
[[ "$WAKER_ANY" == "yes" ]] && exit 0

# Ended with an explicit continuation/close line → pass through.
[[ "$HAS_CONTINUATION" == "yes" ]] && exit 0

# --- BLOCK: write sentinel, emit decision ------------------------------------
printf '1\n' > "$SENTINEL" 2>/dev/null || true

WATCH_DIR="${LEADV2_GUARD_WATCH_DIR:-$HOME/.claude/leadv2-state/leadv2/watchers}"
if [[ "$HAS_TOOL_CALL" == "yes" ]]; then
  TOOL_NOTE=" Этот ход делал вызовы инструментов — но работа не будит: будит только завершение фоновой задачи или событие/истечение Monitor."
else
  TOOL_NOTE=""
fi

python3 - "$TASK_ID_OUT" "$PHASE_OUT" "$TOOL_NOTE" "$WATCH_DIR" "$SESSION_ID" "$WAKER_DETAIL" <<'PYEOF'
import sys, json

task_id     = sys.argv[1]
phase       = sys.argv[2]
tool_note   = sys.argv[3]
watch_dir   = sys.argv[4]
session_id  = sys.argv[5] or "unknown"
waker_note  = (" — сильнейший сигнал был: %s" % sys.argv[6]) if len(sys.argv) > 6 and sys.argv[6] else ""
phase_str   = (" (фаза: %s)" % phase) if phase else ""

arm_cmd = ("mkdir -p '" + watch_dir + "' && python3 -c 'import json,datetime as dt;"
           "n=dt.datetime.now(dt.timezone.utc);"
           "print(json.dumps({\"kind\":\"monitor\",\"watching\":\"<what the Monitor watches>\","
           "\"armed_at\":n.isoformat(),"
           "\"expires_at\":(n+dt.timedelta(minutes=10)).isoformat()}))'"
           " > '" + watch_dir + "/" + session_id + ".watch.json'")

reason = (
    "CONTINUATION-GUARD: активная задача %s%s ещё не закрыта, но когда сессия "
    "заснёт — никто её не разбудит.%s\n\n"
    " Не armed ни один пробудитель: w1 (живой процесс лейна/воркера), "
    "w2 (живая фоновая задача), w3 (свежий sentinel вотчера)%s.\n"
    " Silence ≠ done. Сделайте одно из:\n"
    "  (a) вооружите waker: фоновую задачу (run_in_background) или Monitor на "
    "событие лейна — и запишите sentinel под этот session id:\n"
    "      %s\n"
    "  (b) emit only the missing line; do not restate anything already said:\n"
    '      "работа продолжается: <что ждём>" или\n'
    '      "задача закрыта: <артефакт>"\n'
    % (task_id, phase_str, tool_note, waker_note, arm_cmd)
)
print(json.dumps({"decision": "block", "reason": reason}, ensure_ascii=False))
PYEOF
