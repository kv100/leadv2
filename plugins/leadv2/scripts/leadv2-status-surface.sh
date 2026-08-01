#!/usr/bin/env bash
# leadv2-status-surface.sh — SUPERVISOR-STATUS-SURFACE-02
#
# A cheap, always-fresh, terminal-INDEPENDENT status surface for the leadv2
# supervisor. Pure local file reads — ZERO LLM calls, zero network, zero
# Supabase. Designed target <150 ms wall (one python3 start ~35 ms).
#
# Why this exists (founder order 2026-07-31): the Claude statusline proved
# fragile for supervisor visibility — ghost lanes from a stale sentinel, memo-TTL
# lag, and it dies with the session that owned it. This renderer reads the same
# truth the supervisor loop does, marks every lane LIVE-with-a-cause or DEAD-with-
# a-cause, and never renders a bare "?" or silently omits a row.
#
# READ-ONLY. This script never writes active.yaml, the ledger, a run dir, or any
# state file. Freshness is the whole point; there is no cache/memo layer.
#
# Sources (all env-injected so tests never touch the real ~/.claude):
#   S1 active.yaml          <STATE_DIR>/active.yaml
#   S2 supervise sentinel   <STATE_DIR>/.supervise-active        (first int = pid)
#   S3 supervise heartbeat  <STATE_DIR>/.supervise-loop.heartbeat (mtime only)
#   S4 dispatch ledger      <LEDGER_DIR>/<repo>.jsonl             (tail -n 400 bound)
#   S5 provider runs        <RUNS_ROOT>/{glm,kimi}-runs/<handle>/{meta.yaml,journal.jsonl}
#
# Usage:
#   leadv2-status-surface.sh             # multi-line table (default)
#   leadv2-status-surface.sh --oneline   # single embedded line
#
# Env (every var read with ${X:-default}; unset IS the production path):
#   LEADV2_STATUS_STATE_DIR   default: leadv2-state-path.sh --no-link root
#   LEADV2_STATUS_LEDGER_DIR  default: ~/.claude/cache/dispatch-ledger
#   LEADV2_STATUS_RUNS_ROOT   default: ~/.claude/cache
#   LEADV2_STATUS_REPO        default: basename of git toplevel, else persona-engine
#   LEADV2_STATUS_NOW         default: date +%s   (frozen clock for tests)
#
# Naming follows the LEADV2_* convention; no LEAD_V2_* form is introduced.
# All bash comparisons use POSIX single-bracket tests [ x = y ] / [ "$a" -gt
# "$b" ]; double-bracket == is banned here (eval-adjacent glob-match hazard) —
# verified by the test suite.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_PATH_SH="${SCRIPT_DIR}/leadv2-state-path.sh"

# ── Resolve env ─────────────────────────────────────────────────────────────
# STATE_DIR default MUST go through leadv2-state-path.sh --no-link: rendering
# must never mutate a worktree's symlink set as a side effect of being read.
if [ -n "${LEADV2_STATUS_STATE_DIR:-}" ]; then
  STATE_DIR="${LEADV2_STATUS_STATE_DIR}"
elif [ -x "${STATE_PATH_SH}" ]; then
  STATE_DIR="$(bash "${STATE_PATH_SH}" --no-link root 2>/dev/null || true)"
else
  STATE_DIR=""
fi
LEDGER_DIR="${LEADV2_STATUS_LEDGER_DIR:-${HOME}/.claude/cache/dispatch-ledger}"
RUNS_ROOT="${LEADV2_STATUS_RUNS_ROOT:-${HOME}/.claude/cache}"
NOW="${LEADV2_STATUS_NOW:-$(date +%s)}"
# R1 (fix round 3): tasks.yaml title-lookup source. Default = <git toplevel>/
# docs/tasks.yaml if present, else empty (degrades to dispatch-<sig8> names).
TASKS_YAML="${LEADV2_STATUS_TASKS_YAML:-}"
if [ -z "$TASKS_YAML" ]; then
  _ty_top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$_ty_top" ] && [ -f "${_ty_top}/docs/tasks.yaml" ]; then
    TASKS_YAML="${_ty_top}/docs/tasks.yaml"
  fi
fi
unset _ty_top
if [ -n "${LEADV2_STATUS_REPO:-}" ]; then
  REPO="${LEADV2_STATUS_REPO}"
else
  _top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$_top" ]; then
    REPO="$(basename "$_top")"
  else
    REPO="persona-engine"
  fi
fi
unset _top

# Round 4: opt-in section flags. BARE invocation stays byte-identical to the
# pre-round-4 renderer (the regression contract for the 32 existing tests) —
# only an explicit flag changes the output. Unknown flag → usage, exit 2.
MODE="default"
_usage_r4() {
  printf -- 'Usage: leadv2-status-surface.sh [flag]\n' >&2
  printf -- '  (no flag)         lanes table (default; byte-identical to pre-round-4)\n' >&2
  printf -- '  --oneline         single embedded line\n' >&2
  printf -- '  --questions       pending founder questions section\n' >&2
  printf -- '  --limits          per-provider quota limits section (reads a snapshot)\n' >&2
  printf -- '  --due             scheduled-decisions due/overdue count\n' >&2
  printf -- '  --alarms          urgent alarm count (supervise events, 4h)\n' >&2
  printf -- '  --all             lanes table + --- + every section above\n' >&2
  printf -- '  --refresh-limits  run leadv2-quota-status.sh and write the limits snapshot\n' >&2
}
while [ $# -gt 0 ]; do
  case "$1" in
    --oneline)        MODE="oneline" ;;
    --questions)      MODE="questions" ;;
    --limits)         MODE="limits" ;;
    --due)            MODE="due" ;;
    --alarms)         MODE="alarms" ;;
    --all)            MODE="all" ;;
    --refresh-limits) MODE="refresh-limits" ;;
    -h|--help)        _usage_r4; exit 0 ;;
    --*)              _usage_r4; exit 2 ;;
    *)                _usage_r4; exit 2 ;;
  esac
  shift
done
unset -f _usage_r4 2>/dev/null || true

LEDGER_FILE="${LEDGER_DIR}/${REPO}.jsonl"

# ── Portable mtime (macOS stat -f %m, Linux stat -c %Y) ─────────────────────
_mtime() {
  # echo epoch seconds or empty; never fails the pipeline
  local f="$1"
  [ -z "$f" ] && { printf ''; return; }
  [ -e "$f" ] || { printf ''; return; }
  stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || printf ''
}

# ── R4: kill -0 with EPERM-as-alive ─────────────────────────────────────────
# A foreign-uid pid makes kill -0 return exit 1 with "Operation not permitted" —
# that is a LIVE process we just can't signal. Treat EPERM as alive so we never
# false-DEAD a lane whose worker runs under a different uid.
_pid_alive() {
  local pid="$1" err
  if [ -z "$pid" ]; then return 1; fi
  if err="$(kill -0 "$pid" 2>&1)"; then
    return 0
  fi
  case "$err" in
    *"Operation not permitted"*) return 0 ;;
    *) return 1 ;;
  esac
}

# ── Age label: <60s -> Ns, <90m -> Nm, else Nh ──────────────────────────────
_age_label() {
  local secs="$1"
  case "$secs" in
    ''|*[!0-9]*) secs=0 ;;
  esac
  if [ "$secs" -lt 60 ]; then
    printf '%ss' "$secs"
  elif [ "$secs" -lt 5400 ]; then
    printf '%sm' "$(( secs / 60 ))"
  else
    printf '%sh' "$(( secs / 3600 ))"
  fi
}

# ── Supervisor gate (S2 + S3), pure bash ────────────────────────────────────
# Emits globals: SUP_STATE (on|off|stale), SUP_PID, SUP_BEAT (e.g. "beat 12s"
# or empty), SUP_BEAT_AGE_SECS.
SUP_STATE="off"
SUP_PID=""
SUP_BEAT=""
SUP_BEAT_AGE_SECS=""
SENTINEL="${STATE_DIR}/.supervise-active"
BEAT="${STATE_DIR}/.supervise-loop.heartbeat"
if [ -f "$SENTINEL" ]; then
  SUP_PID="$(awk 'match($0,/[0-9]+/){print substr($0,RSTART,RLENGTH); exit}' "$SENTINEL" 2>/dev/null || true)"
  if [ -z "$SUP_PID" ]; then
    SUP_STATE="off"
  elif _pid_alive "$SUP_PID"; then
    SUP_STATE="on"
    _bm="$(_mtime "$BEAT")"
    if [ -n "$_bm" ]; then
      SUP_BEAT_AGE_SECS=$(( NOW - _bm ))
      [ "$SUP_BEAT_AGE_SECS" -lt 0 ] && SUP_BEAT_AGE_SECS=0
      SUP_BEAT="beat $(_age_label "$SUP_BEAT_AGE_SECS")"
    fi
  else
    SUP_STATE="stale"
  fi
  unset _bm
fi

# ── Lanes via one python3 start ─────────────────────────────────────────────
# Emits control lines then one TSV row per surviving lane:
#   #LIVE <n>
#   #DEAD <n>
#   <id>\t<display>\t<model>\t<age>\t<cause>\t<class>
# <class> in {live, done, dead}. If python3 is absent OR active.yaml is
# unreadable, a single warn row is emitted instead — never a blank screen (R6).
LANES=""
LIVE_N=0
DEAD_N=0
if ! command -v python3 >/dev/null 2>&1; then
  LANES="$(printf 'warn\tactive.yaml\tpython3\t-\tpython3 missing - active.yaml not parsed\tdead\n')"
  DEAD_N=1
else
  LANES="$(LEADV2_SS_STATE_DIR="$STATE_DIR" \
           LEADV2_SS_LEDGER_FILE="$LEDGER_FILE" \
           LEADV2_SS_RUNS_ROOT="$RUNS_ROOT" \
           LEADV2_SS_NOW="$NOW" \
           LEADV2_SS_TASKS_YAML="$TASKS_YAML" \
           python3 2>/dev/null <<'PYEOF'
import os, sys, subprocess

STATE_DIR   = os.environ.get("LEADV2_SS_STATE_DIR", "")
LEDGER_FILE = os.environ.get("LEADV2_SS_LEDGER_FILE", "")
RUNS_ROOT   = os.environ.get("LEADV2_SS_RUNS_ROOT", "")
NOW         = int(os.environ.get("LEADV2_SS_NOW", "0") or "0")
TASKS_YAML  = os.environ.get("LEADV2_SS_TASKS_YAML", "")

# ---- helpers -----------------------------------------------------------
def iso_to_epoch(s):
    if not s:
        return None
    try:
        if isinstance(s, (int, float)):
            return int(s)
        t = str(s).strip()
        if t.endswith("Z"):
            t = t[:-1] + "+00:00"
        from datetime import datetime
        return int(datetime.fromisoformat(t).timestamp())
    except Exception:
        return None

def age_label(secs):
    if secs is None or secs < 0:
        secs = 0
    if secs < 60:
        return "%ds" % int(secs)
    if secs < 5400:
        return "%dm" % (int(secs) // 60)
    return "%dh" % (int(secs) // 3600)

def flat_yaml(path):
    # meta.yaml is flat key:value; parse without the yaml dep for speed/robustness.
    d = {}
    try:
        with open(path, "r") as fh:
            for line in fh:
                line = line.rstrip("\n")
                if not line or line.lstrip().startswith("#") or ":" not in line:
                    continue
                k, _, v = line.partition(":")
                d[k.strip()] = v.strip().strip("'\"")
    except Exception:
        pass
    return d

def journal_mtime(handle, arm):
    if not handle or not arm or not RUNS_ROOT:
        return None
    p = os.path.join(RUNS_ROOT, "%s-runs" % arm, handle, "journal.jsonl")
    try:
        return int(os.path.getmtime(p))
    except Exception:
        return None

def provider_meta(handle, arm):
    # returns (status, exit_code, model, j_mtime)
    if not handle or not arm or not RUNS_ROOT:
        return (None, None, None, None)
    p = os.path.join(RUNS_ROOT, "%s-runs" % arm, handle, "meta.yaml")
    m = flat_yaml(p)
    status = m.get("status")
    ec = m.get("exit_code")
    model = m.get("model")
    j = journal_mtime(handle, arm)
    return (status, ec, model, j)

def lstart(pid):
    try:
        out = subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)],
                             capture_output=True, text=True)
        return " ".join(out.stdout.split())
    except Exception:
        return ""

def pid_alive(pid, birth):
    if pid in (None, "", 0):
        return False
    try:
        pid = int(pid)
    except Exception:
        return False
    if pid <= 0:
        return False
    # R3: pair pid with pid_birth; a recycled pid renders a dead lane as live.
    if birth:
        if lstart(pid) != str(birth).strip():
            return False
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True  # R4: EPERM -> alive
    except OSError:
        return False

def is_terminal(status, ledger_state):
    # ledger vocabulary is written ONLY by leadv2-dispatch-code.sh:860 ("pending")
    # and :913 ("pending"->"confirmed"). "confirmed" is the terminal write of a row --
    # nothing mutates it again, so a silent confirmed row is noise, not a stall.
    # "pending" is NON-terminal on purpose: a stale pending == crashed dispatch, keep visible.
    # closed/failed/cancelled: no writer attested in-tree; kept as forward-compat only.
    return status in ("complete", "failed", "cancelled") or \
           ledger_state in ("confirmed", "closed", "failed", "cancelled")

# ---- R1 (fix round 3): tasks.yaml title map -- ONE parse ----------------
# Source for rule 1 of name resolution. tasks.yaml is mapping-shaped
# {total_open, tasks:[...]} (NOT a top-level list). The human-readable name is
# `title` (forward-compat) or, against today's real data, `external_id` /
# `node_id` (the ALERTS-TO-LEAD-01 shape the founder asked for -- node_id carries
# a `leadv2:` prefix we strip). Index by id, external_id AND node_id so a lookup
# by whichever key the dispatch recorded still hits. A malformed/unreadable
# tasks.yaml degrades to an empty map -- never breaks the render.
titles = {}  # any-of{id, external_id, node_id} -> display name
if TASKS_YAML and os.path.exists(TASKS_YAML):
    try:
        import yaml as _ty
        _doc = _ty.safe_load(open(TASKS_YAML)) or {}
        for _t in (_doc.get("tasks") or []):
            _tid = str(_t.get("id") or "")
            _name = str(_t.get("title") or _t.get("external_id") or "")
            if not _name:
                _nid = str(_t.get("node_id") or "")
                _name = _nid[len("leadv2:"):] if _nid.startswith("leadv2:") else _nid
            _name = _name.strip()
            if _tid and _name:
                titles[_tid] = _name
                _eid = str(_t.get("external_id") or "")
                if _eid:
                    titles.setdefault(_eid, _name)
                _nid = str(_t.get("node_id") or "")
                if _nid:
                    titles.setdefault(_nid, _name)
    except Exception:
        pass

def _clip40(s):
    # first 40 chars; if a ':' occurs within those 40, cut at the FIRST colon
    # (handles "CODE: subtitle" titles). external_id/node_id values have no
    # colon after prefix-stripping, so this is a no-op there.
    s = (s or "").strip()
    head = s[:40]
    i = head.find(":")
    if i >= 0:
        head = head[:i]
    return head.strip()[:40]

def resolve_name(task_id, mission_path, sig8):
    # Rule 1: tasks.yaml name by id/external_id/node_id.
    if task_id:
        _nm = titles.get(str(task_id))
        if _nm:
            return _clip40(_nm)
    # Rule 2: mission-file first line (bounded: 200 bytes; skip if unreadable).
    if mission_path and os.path.exists(mission_path):
        try:
            with open(mission_path, "rb") as _fh:
                _first = _fh.read(200).split(b"\n", 1)[0]
            _first = _first.decode("utf-8", "replace").lstrip("#").strip()
            if _first:
                return _first[:40]
        except Exception:
            pass
    # Rule 3: last resort -- the dispatch id (embeds sig8, stays greppable, and
    # matches the docs/handoff/dispatch-<sig8>/ dir name).
    return "dispatch-" + sig8

# ---- S1: active.yaml ---------------------------------------------------
sessions = []
warn_msg = None
try:
    import yaml
    try:
        with open(os.path.join(STATE_DIR, "active.yaml"), "r") as fh:
            doc = yaml.safe_load(fh) or {}
        sessions = doc.get("sessions") or []
        if not isinstance(sessions, list):
            sessions = []
    except Exception as e:
        warn_msg = "active.yaml unreadable"
except ImportError:
    warn_msg = "active.yaml unreadable (yaml module missing)"

# ---- S4: dispatch ledger, tail -n 400, last row per task_sig wins -------
# R5: the ledger grows unbounded; tail -n 400 is a documented coverage cap
# (no silent caps). Most-recent row per sig8 wins.
ledger = {}  # sig8 -> {arm, handle, state, created_epoch}
if LEDGER_FILE and os.path.exists(LEDGER_FILE):
    try:
        with open(LEDGER_FILE, "r") as fh:
            lines = fh.readlines()[-400:]
        for line in lines:
            line = line.strip()
            if not line:
                continue
            # minimal JSON field extraction (avoid importing json per-row cost
            # is negligible, but stay dependency-light)
            import json
            try:
                row = json.loads(line)
            except Exception:
                continue
            sig = row.get("task_sig") or ""
            if len(sig) < 8:
                continue
            sig8 = sig[:8]
            ledger[sig8] = {
                "arm": row.get("arm") or "",
                "handle": row.get("handle") or "",
                "state": row.get("state") or "",
                "created_epoch": row.get("created_epoch"),
                "task_id": row.get("task_id") or "",
                "mission_path": row.get("mission_path") or row.get("mission") or "",
            }
    except Exception:
        pass

# ---- build rows --------------------------------------------------------
rows = []        # each: dict(name, kind, display, model, age, cause, cls, max_mtime)
seen_sig8 = set()

def add_row(sig8, kind, phase, model, pid, birth, log_path, last_pulse_epoch,
            created_epoch, ledger_state, handle, arm, task_id, mission_path):
    # gather mtimes
    status, ec, pmodel, j_mtime = provider_meta(handle, arm)
    mtimes = []
    for m in (j_mtime,):
        if m:
            mtimes.append(m)
    lm = None
    if log_path:
        try:
            lm = int(os.path.getmtime(log_path))
            mtimes.append(lm)
        except Exception:
            pass
    if last_pulse_epoch:
        mtimes.append(int(last_pulse_epoch))
    if created_epoch:
        try:
            mtimes.append(int(created_epoch))
        except Exception:
            pass
    max_mtime = max(mtimes) if mtimes else None

    alive = pid_alive(pid, birth)

    # liveness rule (STANDING) — cause never empty, never "?"
    if alive:
        cause, cls = "live", "live"
    elif max_mtime is not None and (NOW - max_mtime) < 120:
        cause, cls = "live", "live"
    elif ec not in (None, ""):
        try:
            eci = int(ec)
            if eci == 0:
                cause, cls = "done(exit=0)", "done"
            else:
                cause, cls = "dead(exit=%d)" % eci, "dead"
        except Exception:
            cause, cls = "dead(no-signal)", "dead"
    elif pid not in (None, "", 0):
        cause, cls = "dead(no-process)", "dead"
    elif max_mtime is not None:
        cause = "stale(%s silent)" % age_label(NOW - max_mtime)
        cls = "dead"
    else:
        cause, cls = "dead(no-signal)", "dead"

    terminal = is_terminal(status, ledger_state)
    # terminal last-resort-stale reinterpretation: a ledger-only terminal row
    # (no pid, no exit code, only an old timestamp) lands on the stale("...")
    # branch purely for lack of any signal. Reinterpret that one branch as
    # done — but ONLY there: dead(exit=N)/dead(no-process)/dead(no-signal)
    # are real failure evidence and must stay dead. Sits after `terminal` is
    # computed and before the age-out so old-terminal still drops.
    if terminal and cls == "dead" and cause.startswith("stale("):
        cause = "done(%s)" % (ledger_state or status or "terminal")
        cls = "done"
    # age-out: terminal + silent > 7200s -> drop. Non-terminal never dropped
    # (a 9h silent lane stays visible as stale).
    if terminal:
        ref = max_mtime if max_mtime is not None else 0
        if ref and (NOW - ref) > 7200:
            return None

    # R2 (fix round 3): display by kind. A lane shows its phase; a worker shows
    # its ledger state. The old `phase or ledger_state` fallback conflated the
    # two -- exactly the "single lane or full 9-phase?" confusion. A lane with
    # no phase honestly renders "-".
    if kind == "lane":
        display = phase or "-"
    else:
        display = ledger_state or "-"
    mdl = model or pmodel or arm or "-"
    age = age_label(NOW - max_mtime) if max_mtime is not None else "-"
    return {
        "name": resolve_name(task_id, mission_path, sig8),
        "kind": kind,
        "display": display,
        "model": mdl,
        "age": age,
        "cause": cause,
        "cls": cls,
        "max_mtime": max_mtime,
    }

for s in sessions:
    tid = str(s.get("task_id") or "")
    if not tid:
        continue
    sig8 = tid[:8]
    seen_sig8.add(sig8)
    le = ledger.get(sig8, {})
    handle = le.get("handle") or ""
    arm = le.get("arm") or ""
    ledger_state = le.get("state") or ""
    created_epoch = le.get("created_epoch")
    _tid = tid or le.get("task_id") or ""
    _mpath = le.get("mission_path") or ""
    log_path = s.get("log_path") or s.get("pulse_log") or ""
    r = add_row(sig8, "lane", s.get("phase"), s.get("lead_model"),
                s.get("pid"), s.get("pid_birth"), log_path,
                iso_to_epoch(s.get("last_pulse_at")) or iso_to_epoch(s.get("started_at")),
                created_epoch, ledger_state, handle, arm, _tid, _mpath)
    if r:
        rows.append(r)

# ledger-only rows: task_sig present in ledger, NOT in active.yaml, non-terminal
for sig8, le in ledger.items():
    if sig8 in seen_sig8:
        continue
    ledger_state = le.get("state") or ""
    handle = le.get("handle") or ""
    arm = le.get("arm") or ""
    if ledger_state in ("closed",):
        continue
    _tid = le.get("task_id") or ""
    _mpath = le.get("mission_path") or ""
    r = add_row(sig8, "worker", None, None, None, None, None, None,
                le.get("created_epoch"), ledger_state, handle, arm, _tid, _mpath)
    if r:
        rows.append(r)

if warn_msg and not rows:
    rows = [{
        "name": "warn", "kind": "-", "display": "active.yaml", "model": "-",
        "age": "-", "cause": warn_msg, "cls": "dead", "max_mtime": None,
    }]

# Counts BEFORE collapse: the #DEAD control line and any badge must report the
# real number of dead/finished dispatches, never the post-collapse visible count.
live_n = sum(1 for r in rows if r["cls"] == "live")
dead_n = sum(1 for r in rows if r["cls"] != "live")

# R3 (fix round 3): collapse terminal/done rows so a wall of 90 finished rows is
# structurally impossible. Keep the NEWEST 10 done rows, fold the rest into ONE
# summary line. Live rows and non-terminal stale/dead rows (real failure
# evidence) are NEVER collapsed.
_done_idx = [i for i, r in enumerate(rows) if r["cls"] == "done"]
if len(_done_idx) > 10:
    def _mk(r):
        m = r.get("max_mtime")
        try:
            return int(m) if m is not None else 0
        except Exception:
            return 0
    _kept = set(sorted(_done_idx, key=lambda i: _mk(rows[i]), reverse=True)[:10])
    _dropped = len(_done_idx) - 10
    _new = []
    for i, r in enumerate(rows):
        if r["cls"] == "done" and i not in _kept:
            continue
        _new.append(r)
    _new.append({
        "name": "+ %d done earlier today" % _dropped,
        "kind": "-", "display": "-", "model": "-", "age": "-",
        "cause": "collapsed", "cls": "done", "max_mtime": None,
    })
    rows = _new

out = ["#LIVE %d" % live_n, "#DEAD %d" % dead_n]
for r in rows:
    # TSV order: name kind display model age cause cls -- cls is the LAST tab
    # field (.10s.sh counts live rows via the rendered STATE column, and the
    # statusline oneline live-detection depends on `live` appearing in cause).
    out.append("\t".join([
        str(r["name"]), str(r["kind"]), str(r["display"]),
        str(r["model"]), str(r["age"]), str(r["cause"]), str(r["cls"]),
    ]))
sys.stdout.write("\n".join(out) + "\n")
PYEOF
  )"
fi

# parse the control lines + rows out of LANES
if [ -n "$LANES" ]; then
  LIVE_N="$(printf '%s\n' "$LANES" | sed -n 's/^#LIVE //p' | head -1)"
  DEAD_N="$(printf '%s\n' "$LANES" | sed -n 's/^#DEAD //p' | head -1)"
  case "$LIVE_N" in ''|*[!0-9]*) LIVE_N=0 ;; esac
  case "$DEAD_N" in ''|*[!0-9]*) DEAD_N=0 ;; esac
fi
LANE_ROWS="$(printf '%s\n' "$LANES" | grep -v '^#LIVE ' | grep -v '^#DEAD ' || true)"
LANE_COUNT=0
if [ -n "$LANE_ROWS" ]; then
  LANE_COUNT="$(printf '%s\n' "$LANE_ROWS" | grep -c . || true)"
fi

# ── Render ─────────────────────────────────────────────────────────────────
# emit_oneline / emit_lanes_table are factored out so --all can compose the
# lanes table with the round-4 sections. Their output is byte-identical to the
# pre-round-4 renderer (the regression contract: bare invocation must not drift).
emit_oneline() {
  local head lane_str
  case "$SUP_STATE" in
    on)     head="sup:ON pid=${SUP_PID}${SUP_BEAT:+ ${SUP_BEAT}}" ;;
    stale)  head="sup:OFF(stale pid ${SUP_PID})" ;;
    *)      head="sup:OFF" ;;
  esac
  lane_str=""
  if [ "$LANE_COUNT" -gt 0 ]; then
    lane_str="$(printf '%s\n' "$LANE_ROWS" | awk -F '\t' '
      { printf "%s%s %s %s %s %s", (NR>1?" | ":""), $1, $2, $3, $5, $6 }
      END { printf "\n" }')"
    lane_str="$(printf '%s' "$lane_str" | tr -d '\n')"
  fi
  if [ -n "$lane_str" ]; then
    printf '%s | lanes %d: %s\n' "$head" "$LANE_COUNT" "$lane_str"
  else
    printf '%s | lanes %d\n' "$head" "$LANE_COUNT"
  fi
}

emit_lanes_table() {
  case "$SUP_STATE" in
    on)     printf 'supervisor: ON  pid=%s  %s\n' "$SUP_PID" "$SUP_BEAT" ;;
    stale)  printf 'supervisor: OFF  (stale sentinel, pid %s gone)\n' "$SUP_PID" ;;
    *)      printf 'supervisor: OFF\n' ;;
  esac
  printf 'lanes (%d)\n' "$LANE_COUNT"
  if [ "$LANE_COUNT" -eq 0 ]; then
    printf '  (none)\n'
  else
    printf '  %-28s %-6s %-12s %-7s %-5s %s\n' "NAME" "TYPE" "PHASE/STATE" "MODEL" "AGE" "STATE"
    printf '%s\n' "$LANE_ROWS" | awk -F '\t' '{ printf "  %-28s %-6s %-12s %-7s %-5s %s\n", $1, $2, $3, $4, $5, $6 }'
  fi
}

# ── Round 4 sections ───────────────────────────────────────────────────────
# Each section is independently renderable and machine-readable: the header's
# first token carries the count the widget parses (questions (N) / due: n /
# urgent: n), so the widget never re-parses the human lanes table for these.
# ZERO network, ZERO LLM, ZERO calls to leadv2-quota-status.sh (the only path
# that may run it is --refresh-limits; see render_refresh_limits).

# Pending founder questions. Sources (LEAD-ANCHOR-01, verified on disk):
#   control-plane  ${STATE_DIR}/questions/*.yaml  (status==pending)
#   legacy-handoff <handoff>/*/questions-async/*-pending.yaml with NO sibling
#                  <qid>-answered.yaml
# Question text is founder/LLM-authored: strip '|' (SwiftBar param delimiter)
# and collapse newlines BEFORE emitting (R4 §5.5).
render_questions() {
  local qdir handoff
  qdir="${LEADV2_STATUS_QUESTIONS_DIR:-${STATE_DIR}/questions}"
  handoff="${LEADV2_STATUS_HANDOFF_DIR:-}"
  if [ -z "$handoff" ]; then
    _r4h_top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    [ -n "$_r4h_top" ] && [ -d "${_r4h_top}/docs/handoff" ] && handoff="${_r4h_top}/docs/handoff"
  fi
  unset _r4h_top 2>/dev/null || true
  LEADV2_R4_QDIR="$qdir" LEADV2_R4_HANDOFF="$handoff" python3 2>/dev/null <<'PYEOF'
import os, sys, glob
try:
    import yaml
except Exception:
    yaml = None
qdir = os.environ.get("LEADV2_R4_QDIR", "")
handoff = os.environ.get("LEADV2_R4_HANDOFF", "")

def parse(path):
    if yaml is None:
        return None
    try:
        d = yaml.safe_load(open(path, encoding="utf-8")) or {}
    except Exception:
        return None
    if not isinstance(d, dict):
        return None
    return d

def labels_of(d):
    out = []
    for o in (d.get("options") or []):
        if isinstance(o, dict):
            lab = o.get("label") or o.get("text") or ""
        else:
            lab = str(o)
        lab = str(lab).replace("|", "").replace("\n", " ").strip()
        if lab:
            out.append(lab)
    return out

items = []  # (qid, text, [labels])
if qdir and os.path.isdir(qdir):
    for qf in sorted(glob.glob(os.path.join(qdir, "*.yaml"))):
        base = os.path.basename(qf)
        qid = base[:-5] if base.endswith(".yaml") else base
        d = parse(qf)
        if d is None or d.get("status") != "pending":
            continue
        text = (d.get("question") or d.get("summary_for_lead") or "")
        text = str(text).replace("|", "").replace("\n", " ").strip()
        items.append((qid, text, labels_of(d)))

if handoff and os.path.isdir(handoff):
    for pf in sorted(glob.glob(os.path.join(handoff, "*", "questions-async", "*-pending.yaml"))):
        qd = os.path.dirname(pf)
        base = os.path.basename(pf)
        qid = base[:-len("-pending.yaml")] if base.endswith("-pending.yaml") else base
        if os.path.isfile(os.path.join(qd, qid + "-answered.yaml")):
            continue
        d = parse(pf) or {}
        text = (d.get("question") or d.get("summary_for_lead") or "")
        text = str(text).replace("|", "").replace("\n", " ").strip()
        items.append((qid, text, labels_of(d)))

sys.stdout.write("questions (%d)\n" % len(items))
for qid, text, labels in items:
    line = "%s  %s" % (qid, text[:80])
    if labels:
        line += "  [%s]" % "|".join(labels)
    sys.stdout.write(line + "\n")
PYEOF
}

# Per-provider limits. Reads a SNAPSHOT FILE only — never the live tool. The
# snapshot is the verbatim stdout of leadv2-quota-status.sh plus a first
# '# stamped <epoch>' line, written atomically by --refresh-limits. A snapshot
# older than 15 min is shown with a ' (stale Nm)' suffix — shown, never hidden,
# never refreshed in-band (no network on the read path).
render_limits() {
  local snap
  snap="${LEADV2_STATUS_LIMITS_SNAPSHOT:-${HOME}/.claude/cache/leadv2-limits-snapshot.txt}"
  if [ ! -f "$snap" ]; then
    printf 'limits\n'
    printf '  no snapshot\n'
    return 0
  fi
  local stamp_epoch age stale=""
  stamp_epoch="$(sed -n 's/^# stamped \([0-9][0-9]*\).*/\1/p' "$snap" | head -1)"
  case "$stamp_epoch" in
    ''|*[!0-9]*) ;;
    *)
      age=$(( NOW - stamp_epoch ))
      [ "$age" -lt 0 ] && age=0
      if [ "$age" -gt 900 ]; then
        stale=" (stale $(( age / 60 ))m)"
      fi
      ;;
  esac
  printf 'limits%s\n' "$stale"
  # claude 5h + weekly — from the report header line:
  #   "Quota: 5h N% (... weekly(claude,heuristic) M% ...)"
  local qline c5h cwk
  qline="$(grep '^Quota:' "$snap" | head -1)"
  c5h="$(printf '%s' "$qline" | sed -n 's/^Quota: 5h \([0-9][0-9]*\)%.*/\1/p')"
  cwk="$(printf '%s' "$qline" | sed -n 's/.*weekly(claude[^)]*) \([0-9][0-9]*\)%.*/\1/p')"
  case "$c5h" in ''|*[!0-9]*) c5h="?" ;; esac
  case "$cwk" in ''|*[!0-9]*) cwk="?" ;; esac
  printf '  claude: 5h %s%% weekly %s%% (snapshot)\n' "$c5h" "$cwk"
  # glm weekly — from "  glm weekly (live, z.ai): X%"
  local gline gwk
  gline="$(grep '^  glm weekly' "$snap" | head -1)"
  gwk="$(printf '%s' "$gline" | sed -n 's/.*(live, z.ai): \([0-9][0-9]*\)%.*/\1/p')"
  case "$gwk" in ''|*[!0-9]*) gwk="unmeasured" ;; esac
  printf '  glm: weekly %s%% (snapshot, live z.ai)\n' "$gwk"
  # codex lockout — ~/.claude/cache/codex-lockout.state; show lockout-until only
  # when it is in the future, else the subscription baseline.
  local clf until uepoch
  clf="${LEADV2_STATUS_CODEX_LOCKOUT:-${HOME}/.claude/cache/codex-lockout.state}"
  until=""
  [ -f "$clf" ] && until="$(sed -n 's/.*until=\([^ ]*\).*/\1/p' "$clf" | head -1)"
  uepoch=""
  if [ -n "$until" ]; then
    uepoch="$(LEADV2_R4_ISO="$until" python3 -c 'import os,datetime
t=os.environ["LEADV2_R4_ISO"].rstrip("Z")+"+00:00"
try: print(int(datetime.datetime.fromisoformat(t).timestamp()))
except Exception: print("")' 2>/dev/null || true)"
  fi
  if [ -n "$uepoch" ] && [ "$uepoch" -gt "$NOW" ]; then
    printf '  codex: lockout-until %s (state)\n' "$until"
  else
    printf '  codex: unmeasured (subscription)\n'
  fi
  # kimi — no probe-result cache file exists; spec-sanctioned 'unknown'. A live
  # probe would be a scope violation (R4 §3 / §8 non-goal: no new network probe).
  printf '  kimi: unknown\n'
}

# Scheduled-decisions due/overdue count. Source is the cross-repo
# scheduled-decisions-inject.sh hook (emits {"additionalContext": "..."} JSON,
# exit 0 always). Path env-overridable + [ -x ] guarded; absent → omit entirely.
render_due() {
  local hook raw
  hook="${LEADV2_STATUS_SD_HOOK:-${HOME}/Projects/persona-engine/.claude/hooks/scheduled-decisions-inject.sh}"
  [ -x "$hook" ] || return 0
  raw="$("$hook" 2>/dev/null || true)"
  [ -n "$raw" ] || raw="{}"
  printf '%s' "$raw" | python3 -c 'import sys, json
raw = sys.stdin.read()
due = overdue = 0
try:
    ctx = (json.loads(raw) or {}).get("additionalContext") or ""
    for line in ctx.splitlines():
        if line.startswith("[OVERDUE]"):
            overdue += 1; due += 1
        elif line.startswith("[DUE TODAY]") or line.startswith("[CONDITION-BOUND]"):
            due += 1
except Exception:
    pass
print("due: %d overdue: %d" % (due, overdue))'
}

# Urgent alarms from the supervise loop log. Counts [SUPERVISE-URGENT] lines
# newer than 4h, deduped by alarm key (category + subject id, volatile age=
# tokens stripped) so a persistent breach that fired once is not double-counted.
render_alarms() {
  local logf n
  logf="${LEADV2_STATUS_URGENT_LOG:-}"
  if [ -z "$logf" ] && [ -x "${STATE_PATH_SH}" ]; then
    logf="$(bash "${STATE_PATH_SH}" --no-link supervise-loop.log 2>/dev/null || true)"
  fi
  n=0
  if [ -f "$logf" ]; then
    n="$(LEADV2_R4_LOG="$logf" LEADV2_R4_NOW="$NOW" python3 -c 'import os, re, datetime
logf = os.environ["LEADV2_R4_LOG"]; now = int(os.environ["LEADV2_R4_NOW"])
seen = set()
try:
    with open(logf, encoding="utf-8") as fh:
        for line in fh:
            if "[SUPERVISE-URGENT]" not in line:
                continue
            ts_m = re.match(r"^(\S+) \[SUPERVISE-URGENT\]", line)
            if ts_m:
                try:
                    ep = int(datetime.datetime.fromisoformat(ts_m.group(1).rstrip("Z")+"+00:00").timestamp())
                except Exception:
                    ep = None
                if ep is not None and not (0 <= (now - ep) <= 14400):
                    continue
            content = line.split("[SUPERVISE-URGENT]", 1)[1].strip()
            key = " ".join(content.split()[:2])
            key = re.sub(r"age=\S+", "", key).strip() or content
            seen.add(key)
except Exception:
    pass
print(len(seen))' 2>/dev/null || true)"
  fi
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf 'urgent: %d (4h)\n' "$n"
}

# The ONLY code path allowed to run leadv2-quota-status.sh. Writes the snapshot
# atomically (tmp + mv -f) so a concurrent reader never sees a half file. Not
# wired to any cron in this round — absent snapshot is the normal first-run
# state and renders cleanly via render_limits.
render_refresh_limits() {
  local snap qs tmp
  snap="${LEADV2_STATUS_LIMITS_SNAPSHOT:-${HOME}/.claude/cache/leadv2-limits-snapshot.txt}"
  qs="${SCRIPT_DIR}/leadv2-quota-status.sh"
  mkdir -p "$(dirname "$snap")" 2>/dev/null || true
  tmp="${snap}.tmp.$$"
  {
    printf '# stamped %s\n' "$NOW"
    if [ -x "$qs" ]; then
      bash "$qs" 2>/dev/null || true
    else
      printf '# leadv2-quota-status.sh missing\n'
    fi
  } > "$tmp"
  mv -f "$tmp" "$snap"
  printf 'limits snapshot written to %s\n' "$snap"
}

# ── Dispatch ───────────────────────────────────────────────────────────────
case "$MODE" in
  oneline)        emit_oneline; exit 0 ;;
  default)        emit_lanes_table; exit 0 ;;
  questions)      render_questions; exit 0 ;;
  limits)         render_limits; exit 0 ;;
  due)            render_due; exit 0 ;;
  alarms)         render_alarms; exit 0 ;;
  refresh-limits) render_refresh_limits; exit 0 ;;
  all)
    emit_lanes_table
    printf -- '---\n'
    render_questions
    printf -- '---\n'
    render_limits
    printf -- '---\n'
    render_due
    printf -- '---\n'
    render_alarms
    exit 0
    ;;
esac
