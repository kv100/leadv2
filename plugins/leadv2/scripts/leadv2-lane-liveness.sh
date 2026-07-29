#!/usr/bin/env bash
# One authoritative lane verdict.  The lane's output log is the primary
# signal; active.yaml supplies only the optional process identity.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-$PWD}"
LANE_ID=""
JOB_ID=""
ALL=0
JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) PROJECT_ROOT="${2:-}"; shift 2 ;;
    --lane) LANE_ID="${2:-}"; shift 2 ;;
    --job) JOB_ID="${2:-}"; shift 2 ;;
    --all) ALL=1; shift ;;
    --json) JSON=1; shift ;;
    *) printf '[lane-liveness] unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [[ -n "$LANE_ID" && ( -n "$JOB_ID" || "$ALL" -eq 1 ) ]] || [[ -n "$JOB_ID" && "$ALL" -eq 1 ]]; then
  printf '[lane-liveness] choose exactly one of --lane, --job, or --all\n' >&2
  exit 2
fi

# State paths may be outside a worktree.  Keep the local path as a fallback
# for standalone fixtures and old plugin installs.
ACTIVE_YAML="$PROJECT_ROOT/docs/leadv2/active.yaml"
TOMBSTONES="$PROJECT_ROOT/docs/leadv2/tombstones.yaml"
if [[ -f "$SCRIPT_DIR/leadv2-state-path.sh" ]]; then
  ACTIVE_YAML="$(PROJECT_ROOT="$PROJECT_ROOT" "$SCRIPT_DIR/leadv2-state-path.sh" active.yaml 2>/dev/null || printf '%s' "$ACTIVE_YAML")"
  TOMBSTONES="$(PROJECT_ROOT="$PROJECT_ROOT" "$SCRIPT_DIR/leadv2-state-path.sh" tombstones.yaml 2>/dev/null || printf '%s' "$TOMBSTONES")"
fi

CODEX_TASK="${CODEX_TASK_SH:-${SCRIPT_DIR}/codex-task.sh}"
CODEX_RAW=''
if [[ -f "$CODEX_TASK" ]]; then
  if [[ -n "$JOB_ID" ]]; then
    CODEX_RAW="$(bash "$CODEX_TASK" status "$JOB_ID" --json --cwd "$PROJECT_ROOT" 2>/dev/null || true)"
  else
    CODEX_RAW="$(bash "$CODEX_TASK" status --all --json --cwd "$PROJECT_ROOT" 2>/dev/null || true)"
  fi
fi

# --all resolves every lane in one Python pass.  BSD stat is invoked as
# `stat -f %m` (never GNU stat/date syntax) so this remains portable to macOS.
python3 - "$PROJECT_ROOT" "$ACTIVE_YAML" "$TOMBSTONES" "$LANE_ID" "$JOB_ID" "$ALL" "$JSON" "$CODEX_RAW" "${LEADV2_LANE_SILENT_MAX_S:-900}" "${LEADV2_LANE_LIVENESS_V2:-1}" <<'PY'
import glob, json, os, subprocess, sys, time

(root, active_path, tombstones_path, wanted_lane, wanted_job, all_mode, json_mode,
 codex_raw, silent_max_raw, v2_raw) = sys.argv[1:]
all_mode = all_mode == "1"
json_mode = json_mode == "1"
# LEADV2_LANE_LIVENESS_V2=0 is the one-flag rollback to the exact prior
# implementation (self-reported provider queued/running trusted as alive
# with no log-age check). Default-on: =1 or unset runs the corrected logic.
v2_mode = v2_raw != "0"
try:
    silent_max = max(0, int(silent_max_raw))
except ValueError:
    silent_max = 900

def bsd_mtime(path):
    try:
        return int(subprocess.run(["stat", "-f", "%m", path], capture_output=True, text=True,
                                  timeout=2, check=True).stdout.strip())
    except Exception:
        return None

def pid_alive(value):
    try:
        os.kill(int(value), 0)
        return True
    except (TypeError, ValueError, ProcessLookupError, PermissionError):
        return False

def ps_stat(value):
    try:
        return subprocess.run(["ps", "-o", "stat=", "-p", str(value)], capture_output=True,
                              text=True, timeout=2).stdout.strip()
    except Exception:
        return ""

def load_yaml(path, default):
    try:
        import yaml
        with open(path, encoding="utf-8") as fh:
            value = yaml.safe_load(fh)
        return default if value is None else value
    except Exception:
        return default

active = load_yaml(active_path, {})
sessions = {str(s.get("task_id")): s for s in (active.get("sessions") or [])
            if isinstance(s, dict) and s.get("task_id")}
tombstones = load_yaml(tombstones_path, [])
tombstoned = {str(item.get("task_id")) for item in tombstones if isinstance(item, dict) and item.get("task_id")}

def provider_jobs(raw):
    jobs = []
    try:
        payload = json.loads(raw)
    except Exception:
        return jobs
    if not isinstance(payload, dict):
        return jobs
    if isinstance(payload.get("job"), dict):
        jobs.append(payload["job"])
    jobs.extend(j for j in (payload.get("running") or []) if isinstance(j, dict))
    jobs.extend(j for j in (payload.get("recent") or []) if isinstance(j, dict))
    if isinstance(payload.get("latestFinished"), dict):
        jobs.append(payload["latestFinished"])
    out = {}
    for job in jobs:
        if job.get("id"):
            out[str(job["id"])] = job
    return out

jobs = provider_jobs(codex_raw)

def lane_job_id(tid):
    path = os.path.join(root, "docs", "handoff", tid, "codex-plan.json")
    try:
        with open(path, encoding="utf-8") as fh:
            value = json.load(fh)
        return str(value.get("job_id") or "")
    except Exception:
        return ""

def resolve(tid):
    lane_dir = os.path.join(root, "docs", "handoff", tid)
    row = {"lane": tid, "verdict": None, "age_s": None, "source": None,
           "log_path": None, "pid": None, "pid_alive": None, "reason": None}
    session = sessions.get(tid)
    if session is not None:
        row["pid"] = session.get("pid")
        row["pid_alive"] = pid_alive(row["pid"])

    # B9/B14 fix (SUPERVISOR-AUDIT-01 fix-round-2): consult the active row's
    # OWN recorded log_path first. leadv2-fanout.sh's single-worker funnel
    # (launch_via_dispatch_code) writes to docs/handoff/dispatch-<sig8>/
    # developer.stream.jsonl, never to docs/handoff/<task_id>/ — the funnel's
    # active.yaml row carries that path in its log_path field precisely so
    # liveness can find it. Ignoring it made every fresh funnel dispatch
    # resolve dead:no_handoff_dir, and the two-poll prune path in
    # leadv2-supervise.sh could then delete a live worker. Only a
    # session-recorded log_path that resolves to a REAL, EXISTING file is
    # treated as authoritative here — a session with no log_path, or one
    # pointing at a file that does not (yet) exist, falls through to the
    # unchanged directory scan below, so pre-funnel lanes (whose log_path is
    # the phase-cycle pulse.md default) keep their exact prior resolution.
    session_log_path = None
    if session is not None:
        raw_log_path = session.get("log_path")
        if raw_log_path:
            candidate = raw_log_path if os.path.isabs(raw_log_path) else os.path.join(root, raw_log_path)
            if os.path.isfile(candidate):
                session_log_path = candidate

    if session_log_path is None and not os.path.isdir(lane_dir):
        row.update(verdict="dead:no_handoff_dir", source="handoff", reason="no_handoff_dir")
        return row

    log_path = session_log_path
    source = "active.yaml:log_path" if session_log_path else None
    if log_path is None:
        candidates = [os.path.join(lane_dir, "session.log"), os.path.join(lane_dir, "fanout.log")]
        existing = [(p, os.path.basename(p)) for p in candidates if os.path.isfile(p)]
        if existing:
            # MINOR fix: when both logs exist, the NEWEST by mtime is authoritative
            # — the first-found path used to win even if it was a stale leftover,
            # producing false silence while the other log was actively updating.
            log_path, source = max(existing, key=lambda pair: os.path.getmtime(pair[0]))
    if log_path is None:
        files = [p for p in glob.glob(os.path.join(lane_dir, "*")) if os.path.isfile(p)]
        if files:
            log_path = max(files, key=lambda p: os.path.getmtime(p))
            source = "fallback:newest_file"
    if log_path is None:
        row.update(verdict="dead:no_log_artifact", source="handoff", reason="no_log_artifact")
        return row
    # `source` is the selected artifact path, not an inferred status label;
    # callers can therefore prove session.log/fanout.log/log_path selection
    # directly.
    row["log_path"], row["source"] = log_path, log_path
    mtime = bsd_mtime(log_path)
    if mtime is None:
        row.update(verdict="dead:log_stat_failed", reason="log_stat_failed")
        return row
    row["age_s"] = max(0, int(time.time()) - mtime)
    # A Codex mapping is the sole provider exception.  It never applies to a
    # Claude lane merely because a Codex job happens to be running.
    job_id = lane_job_id(tid)
    job = jobs.get(job_id) if job_id else None
    provider_status = None
    if job:
        provider_status = str(job.get("status") or "unknown").lower()
        row["source"] = "codex-task.sh"
        row["provider_status"] = provider_status
    is_fresh = row["age_s"] <= silent_max
    if not v2_mode:
        # LEADV2_LANE_LIVENESS_V2=0 rollback: exact prior implementation —
        # self-reported queued/running is trusted as alive before log age or
        # PID evidence is evaluated.
        if provider_status in ("queued", "running"):
            row.update(verdict="alive", reason=f"provider_{provider_status}")
            return row
        if provider_status in ("completed", "done", "cancelled", "failed"):
            row.update(verdict=f"dead:provider_{provider_status}", reason=f"provider_{provider_status}")
            return row
    elif not is_fresh and provider_status in ("completed", "done", "cancelled", "failed"):
        # B8 fix (SUPERVISOR-AUDIT-01 fix-round-3): terminal provider status is
        # only corroborating evidence the job is provably finished ONCE the
        # log itself has gone silent. A FRESH log (age <= silent_max) is
        # authoritative on its own and must never be overridden by a terminal
        # self-report — the reviewer's exact probe was a fresh session.log, no
        # PID, and a mapped provider job reporting "cancelled": that must
        # resolve alive (or silent, never dead) because something is still
        # actively writing regardless of what the provider job says finished.
        row.update(verdict=f"dead:provider_{provider_status}", reason=f"provider_{provider_status}")
        return row
    # Provider queued/running (v2_mode) is now ANNOTATION ONLY — it never
    # short-circuits the verdict; log mtime + process evidence below decide.
    # Preserve stopped-process detection in the same verdict source.
    if row["pid"] is not None and row["pid_alive"]:
        stat = ps_stat(row["pid"])
        if "T" in stat:
            row.update(verdict=f"dead:wedged_STAT={stat}", reason=f"wedged_STAT={stat}")
            return row
    suffix = f"+provider_{provider_status}" if provider_status else ""
    if is_fresh:
        row.update(verdict="alive", reason=f"log_fresh{suffix}")
    elif row["pid"] is None:
        row.update(verdict=f"silent:{row['age_s']}", reason=f"no_pid_recorded{suffix}")
    elif row["pid_alive"]:
        row.update(verdict=f"silent:{row['age_s']}", reason=f"log_silent_process_alive{suffix}")
    else:
        row.update(verdict=f"dead:silent_{row['age_s']}s_no_process", reason=f"log_silent_no_process{suffix}")
    return row

def compatible_jobs():
    out = []
    for job in jobs.values():
        status = str(job.get("status") or "unknown").lower()
        verdict = {"queued": "running", "running": "running", "completed": "done", "done": "done",
                   "cancelled": "cancelled", "failed": "failed"}.get(status, "unknown")
        out.append({"id": job.get("id", "?"), "status": status, "phase": str(job.get("phase") or status),
                    "verdict": verdict, "started_at": job.get("startedAt") or job.get("createdAt"),
                    "updated_at": job.get("updatedAt"), "reason": job.get("reason") or job.get("error") or job.get("message"),
                    "source": "codex-task.sh status"})
    return out

if wanted_job:
    # Back-compatible provider response for callers that ask by job id.
    payload = {"provider": "codex", "precedence": "authoritative_provider_status",
               "jobs": compatible_jobs(), "availability": "authoritative" if jobs else "unavailable"}
    print(json.dumps(payload) if json_mode else (payload["jobs"][0]["verdict"] if payload["jobs"] else "unknown"))
elif wanted_lane:
    row = resolve(wanted_lane)
    print(json.dumps(row, separators=(",", ":")) if json_mode else row["verdict"])
else:
    ids = set(sessions)
    for pattern in ("session.log", "fanout.log"):
        ids.update(os.path.basename(os.path.dirname(p)) for p in glob.glob(os.path.join(root, "docs", "handoff", "*", pattern)))
    ids = sorted(tid for tid in ids if tid not in tombstoned and not os.path.exists(os.path.join(root, "docs", "handoff", tid, ".close")))
    lanes = [resolve(tid) for tid in ids]
    payload = {"lanes": lanes, "jobs": compatible_jobs(), "availability": "authoritative" if jobs else "unavailable"}
    if json_mode:
        print(json.dumps(payload))
    else:
        for row in lanes:
            print(f"{row['lane']} {row['verdict']}")
PY
