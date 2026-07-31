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

MODE="default"
if [ "${1:-}" = "--oneline" ]; then
  MODE="oneline"
fi

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
           python3 2>/dev/null <<'PYEOF'
import os, sys, subprocess

STATE_DIR   = os.environ.get("LEADV2_SS_STATE_DIR", "")
LEDGER_FILE = os.environ.get("LEADV2_SS_LEDGER_FILE", "")
RUNS_ROOT   = os.environ.get("LEADV2_SS_RUNS_ROOT", "")
NOW         = int(os.environ.get("LEADV2_SS_NOW", "0") or "0")

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
    return status in ("complete", "failed", "cancelled") or \
           ledger_state in ("closed", "failed", "cancelled")

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
            }
    except Exception:
        pass

# ---- build rows --------------------------------------------------------
rows = []        # each: dict(id, display, model, age, cause, cls)
seen_sig8 = set()

def add_row(sig8, phase, model, pid, birth, log_path, last_pulse_epoch,
            created_epoch, ledger_state, handle, arm):
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
    # age-out: terminal + silent > 7200s -> drop. Non-terminal never dropped
    # (a 9h silent lane stays visible as stale).
    if terminal:
        ref = max_mtime if max_mtime is not None else 0
        if ref and (NOW - ref) > 7200:
            return None

    display = phase or ledger_state or "-"
    mdl = model or pmodel or arm or "-"
    age = age_label(NOW - max_mtime) if max_mtime is not None else "-"
    return {
        "id": sig8,
        "display": display,
        "model": mdl,
        "age": age,
        "cause": cause,
        "cls": cls,
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
    log_path = s.get("log_path") or s.get("pulse_log") or ""
    r = add_row(sig8, s.get("phase"), s.get("lead_model"),
                s.get("pid"), s.get("pid_birth"), log_path,
                iso_to_epoch(s.get("last_pulse_at")) or iso_to_epoch(s.get("started_at")),
                created_epoch, ledger_state, handle, arm)
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
    r = add_row(sig8, None, None, None, None, None, None,
                le.get("created_epoch"), ledger_state, handle, arm)
    if r:
        rows.append(r)

if warn_msg and not rows:
    rows = [{
        "id": "warn", "display": "active.yaml", "model": "-",
        "age": "-", "cause": warn_msg, "cls": "dead",
    }]

live_n = sum(1 for r in rows if r["cls"] == "live")
dead_n = sum(1 for r in rows if r["cls"] != "live")

out = ["#LIVE %d" % live_n, "#DEAD %d" % dead_n]
for r in rows:
    out.append("\t".join([r["id"], r["display"], r["model"], r["age"], r["cause"], r["cls"]]))
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
if [ "$MODE" = "oneline" ]; then
  case "$SUP_STATE" in
    on)     head="sup:ON pid=${SUP_PID}${SUP_BEAT:+ ${SUP_BEAT}}" ;;
    stale)  head="sup:OFF(stale pid ${SUP_PID})" ;;
    *)      head="sup:OFF" ;;
  esac
  lane_str=""
  if [ "$LANE_COUNT" -gt 0 ]; then
    lane_str="$(printf '%s\n' "$LANE_ROWS" | awk -F '\t' '
      { printf "%s%s %s %s %s", (NR>1?" | ":""), $1, $2, $4, $5 }
      END { printf "\n" }')"
    lane_str="$(printf '%s' "$lane_str" | tr -d '\n')"
  fi
  if [ -n "$lane_str" ]; then
    printf '%s | lanes %d: %s\n' "$head" "$LANE_COUNT" "$lane_str"
  else
    printf '%s | lanes %d\n' "$head" "$LANE_COUNT"
  fi
  exit 0
fi

# default multi-line table
case "$SUP_STATE" in
  on)     printf 'supervisor: ON  pid=%s  %s\n' "$SUP_PID" "$SUP_BEAT" ;;
  stale)  printf 'supervisor: OFF  (stale sentinel, pid %s gone)\n' "$SUP_PID" ;;
  *)      printf 'supervisor: OFF\n' ;;
esac
printf 'lanes (%d)\n' "$LANE_COUNT"
if [ "$LANE_COUNT" -eq 0 ]; then
  printf '  (none)\n'
else
  printf '  %-10s %-10s %-8s %-6s %s\n' "ID" "PHASE" "MODEL" "AGE" "STATE"
  printf '%s\n' "$LANE_ROWS" | awk -F '\t' '{ printf "  %-10s %-10s %-8s %-6s %s\n", $1, $2, $3, $4, $5 }'
fi
