#!/usr/bin/env bash
set -euo pipefail
# codex-guard.sh <jobId> <cwd> -- CODEX-NEVER-LOSE-01
#
# Watches a detached Codex job (dispatched via `codex-task.sh task|review
# --background`) until it reaches a terminal state or times out, then emits
# the wake signal so the parent Claude session (or whoever is watching the
# log) learns the job finished even if the session that dispatched it died
# first.
#
# CODEX-FULLACCESS-01 (2026-07-11): this script NO LONGER commits anything.
# It used to blind-rescue a dirty <cwd> with `git add -A && git commit`,
# reasoning that Codex's workspace-write sandbox could not commit itself (a
# git-worktree's real .git lives outside the worktree cwd -> index.lock
# denied). That blind rescue is exactly what swept 19 unrelated dirty files
# from the caller's working tree into a junk commit in a real session -- `git
# add -A` has no concept of "this dirty file belongs to this job" and can
# never be made safe by tightening the commit message alone. The correct fix
# is upstream: the sandbox's workspace-write writable_roots now also cover the
# main repo's `.git` dir (see docs/handoff/CODEX-FULLACCESS-01/build-widen.md
# and ~/.codex/config.toml [sandbox_workspace_write]), so Codex commits its
# own intended changes itself, inside its own turn, with its own selective
# `git add <files>`. This script is now report-only: it never stages or
# commits anything, on any path.
#
# T13-SLICE1 W1 (CODEX-INTERRUPT-KILLER-01, 2026-08-26): codex-guard.sh is
# armed by codex-task.sh AFTER `_run_with_fallback` already returned (the
# background dispatch call already completed and printed its jobId) -- so by
# the time this script's first poll iteration runs, the actual Codex worker
# process may not have written its `pid` field yet, may still be between
# fork and exec, or its job JSON may be milliseconds old with a `logFile`
# that hasn't been created. Evidence: lane 9a920d1d 2026-08-26 02:06Z, codex
# worker died 10s after spawn, rollout shows turn_aborted reason=interrupted.
# Two independent hardenings close the race:
#   1. GRACE WINDOW -- never declare a job failed (fast-fail OR reaper sweep)
#      while it is younger than CODEX_GUARD_GRACE_SEC (default 30s), measured
#      from the job's OWN `startedAt`/`createdAt` field, not from this
#      script's wall-clock -- a guard that itself started late (slow nohup
#      fork under load) must not treat that delay as job age.
#   2. JOB-ID VERIFICATION -- before any status mutation, re-read the job
#      JSON's own `id` field and refuse to touch it unless it equals the id
#      the write path expects (the filename-derived id for reap_stale_workers,
#      or the armed $JOB_ID for this job's own fast-fail path). Guards against
#      a stale/reused job record surviving under the same filename from a
#      different workspaceRoot (the zombie-survives-cancel trap already noted
#      elsewhere in codex-task.sh) being mistaken for the job this guard was
#      armed for.
#
# Usage: codex-guard.sh <jobId> <cwd>
# Env:   CODEX_GUARD_TIMEOUT=<seconds, default 1800>
#        CODEX_GUARD_FAST_FAIL=<0|1, default 1> -- pid-liveness fast-fail (TF-01) and the
#          stale-worker reaper sweep (TF-02) both live behind this ONE flag. =0 restores the
#          pre-TF-01/TF-02 behavior byte-for-byte: blind-wait the full CODEX_GUARD_TIMEOUT for
#          this job's own status, no early declare-failed, no reaper sweep of other jobs.
#        CODEX_GUARD_GRACE_SEC=<seconds, default 30> -- minimum job age (from its own
#          startedAt/createdAt) before ANY declare-failed path (fast-fail or reaper) may act.
#
# Emits exactly ONE final stdout line (the wake signal):
#   CODEX-GUARD <jobId> status=<s> commit=<clean|uncommitted|n/a> cwd=<cwd>
# and appends the same line to ~/.claude/logs/codex-guard.log.
#   commit=clean       -- cwd is a git work tree with no pending changes
#   commit=uncommitted -- cwd is a git work tree and Codex left changes
#                         uncommitted; nothing was touched, caller must look
#   commit=n/a          -- cwd is not inside a git work tree
#
# NEVER runs `git add`/`git commit`/any mutating git command. Read-only
# status check only (`git status --porcelain`). Fail-safe: missing job json,
# non-git cwd, or timeout all report and exit 0 rather than hang or error out.

JOB_ID="${1:-}"
CWD="${2:-}"

STATE_ROOT="${CODEX_GUARD_STATE_ROOT:-$HOME/.claude/plugins/data/codex-openai-codex/state}"
LOG_FILE="${CODEX_GUARD_LOG_FILE:-$HOME/.claude/logs/codex-guard.log}"
TIMEOUT="${CODEX_GUARD_TIMEOUT:-1800}"
FAST_FAIL="${CODEX_GUARD_FAST_FAIL:-1}"
GRACE_SEC="${CODEX_GUARD_GRACE_SEC:-30}"
POLL_INTERVAL_SEC=15
JOB_LOCK_MAX_WAIT_SEC=10
JOB_LOCK_STALE_SEC=60

log() { printf -- '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

mkdir -p "$(dirname "$LOG_FILE")"

emit_final() {
  local line="$1"
  printf -- '%s\n' "$line"
  printf -- '%s\n' "$line" >> "$LOG_FILE"
}

if [[ -z "$JOB_ID" || -z "$CWD" ]]; then
  log "usage: codex-guard.sh <jobId> <cwd> -- got jobId='${JOB_ID}' cwd='${CWD}'"
  emit_final "CODEX-GUARD ${JOB_ID:-unknown} status=error commit=none cwd=${CWD:-unknown}"
  exit 0
fi

find_job_json() {
  find "$STATE_ROOT" -path "*/jobs/${JOB_ID}.json" 2>/dev/null | head -1
}

read_status() {
  local json_path="$1"
  python3 - "$json_path" <<'PY' 2>/dev/null || true
import json
import sys

try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get("status", ""))
except Exception:
    print("")
PY
}

read_pid() {
  local json_path="$1"
  python3 - "$json_path" <<'PY' 2>/dev/null || true
import json
import sys

try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    pid = data.get("pid")
    print(pid if pid is not None else "")
except Exception:
    print("")
PY
}

read_log_file() {
  local json_path="$1"
  python3 - "$json_path" <<'PY' 2>/dev/null || true
import json
import sys

try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get("logFile") or "")
except Exception:
    print("")
PY
}

# T13-SLICE1 W1: job age in whole seconds, from the job's OWN startedAt (falls
# back to createdAt) -- never from this script's wall-clock. An unknown age
# is zero: an unreadable, malformed, or legacy record remains inside grace and
# is never killed merely because the guard cannot prove its age.
read_job_age_sec() {
  local json_path="$1"
  python3 - "$json_path" <<'PY' || { log "WARN: job age unreadable for $(basename "$json_path"); treating as age=0"; echo 0; }
import json
import sys
import time
from datetime import datetime, timezone

try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    ts = data.get("startedAt") or data.get("createdAt")
    if not ts:
        print("WARN: job age missing timestamp; treating as age=0", file=sys.stderr)
        print(0)
        sys.exit(0)
    ts_norm = ts.replace("Z", "+00:00")
    started = datetime.fromisoformat(ts_norm)
    if started.tzinfo is None:
        started = started.replace(tzinfo=timezone.utc)
    now = datetime.now(timezone.utc)
    age = int((now - started).total_seconds())
    print(max(age, 0))
except Exception:
    print("WARN: job age malformed; treating as age=0", file=sys.stderr)
    print(0)
PY
}

# CG-CAS-01: mkdir-based lock, one per job JSON, serializing concurrent
# codex-guard.sh instances (this job's own loop vs. another job's reaper
# sweep, or two guards reaping the same STATE_ROOT) against each other on the
# SAME file. mkdir is atomic even across processes/hosts sharing the dir.
acquire_job_lock() {
  local lock_dir="$1.lock" waited=0 age
  while ! mkdir "$lock_dir" 2>/dev/null; do
    if [[ -d "$lock_dir" ]]; then
      age="$(( $(date +%s) - $(stat_mtime "$lock_dir") ))" 2>/dev/null || age=0
      if (( age > JOB_LOCK_STALE_SEC )); then
        rmdir "$lock_dir" 2>/dev/null || true
        continue
      fi
    fi
    sleep 0.2
    waited=$((waited + 1))
    (( waited < JOB_LOCK_MAX_WAIT_SEC * 5 )) || return 1
  done
  return 0
}

release_job_lock() {
  rmdir "$1.lock" 2>/dev/null || true
}

# TF-01 (T-f fix 1+2): terminal-status write, idempotent -- a no-op if the job
# already reached a terminal status.
# CG-CAS-01: the real writer (the Codex worker process itself) can complete
# between our earlier read and this write with no lock of its own, so on top
# of the mkdir lock above (which only serializes OTHER codex-guard.sh
# instances) this re-derives status/pid/log-freshness from a FRESH read
# immediately before the atomic os.replace. The final compare-and-swap below
# additionally rejects a filename that was replaced by a different job in the
# residual write window.
# T13-SLICE1 W1: two new args -- expected_id (refuse to touch a record whose
# own `id` field doesn't match, e.g. a stale/reused file under the same
# filename from a different workspaceRoot) and grace_sec (refuse to declare
# failed while the record's own age is under this many seconds, re-derived
# from the SAME fresh read as the pid/log recheck below, not from an earlier
# snapshot).
mark_job_failed() {
  local json_path="$1" reason="$2" recheck_max_age="${3:-0}" grace_sec="${4:-0}" expected_id="${5:-}"
  acquire_job_lock "$json_path" || { log "mark_job_failed: could not acquire lock for $(basename "$json_path"), skipping"; return 0; }
  python3 - "$json_path" "$reason" "$recheck_max_age" "$grace_sec" "$expected_id" <<'PY' 2>/dev/null || true
import json
import os
import sys
import time
from datetime import datetime, timezone

path, reason, recheck_max_age, grace_sec, expected_id = (
    sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
)
try:
    with open(path) as f:
        data = json.load(f)
    original_stat = os.stat(path)
except Exception:
    sys.exit(0)

if data.get("status") in ("completed", "failed", "cancelled"):
    sys.exit(0)

# T13-SLICE1 W1 fix 2: job-id verification. A record whose own `id` doesn't
# match what the caller believes it is watching is never mutated -- this is
# the only place a wrong-file match (stale record surviving under this
# filename) could otherwise flip an unrelated job to failed.
if expected_id and data.get("id") != expected_id:
    sys.exit(0)

# T13-SLICE1 W1 fix 1: grace window, measured from the record's own
# startedAt/createdAt -- never from the caller's wall-clock. A record with no
# parseable timestamp fails open to LIFE (inside grace) rather than blocking
# forever.
if grace_sec > 0:
    ts = data.get("startedAt") or data.get("createdAt")
    if not ts:
        print("WARN: mark_job_failed age missing timestamp; preserving job", file=sys.stderr)
        sys.exit(0)
    else:
        try:
            ts_norm = ts.replace("Z", "+00:00")
            started = datetime.fromisoformat(ts_norm)
            if started.tzinfo is None:
                started = started.replace(tzinfo=timezone.utc)
            age = (datetime.now(timezone.utc) - started).total_seconds()
            if age < grace_sec:
                sys.exit(0)  # too young -- never declare failed inside the grace window
        except Exception:
            print("WARN: mark_job_failed age malformed; preserving job", file=sys.stderr)
            sys.exit(0)

pid = data.get("pid")
if pid is not None:
    try:
        os.kill(int(pid), 0)
        sys.exit(0)  # pid answers again -- worker resumed, do not mark failed
    except (ProcessLookupError, ValueError):
        pass
    except PermissionError:
        sys.exit(0)  # pid exists, owned elsewhere -- treat as alive

if recheck_max_age > 0:
    log_path = data.get("logFile")
    if log_path and os.path.exists(log_path):
        if time.time() - os.path.getmtime(log_path) <= recheck_max_age:
            sys.exit(0)  # log went fresh again -- worker is alive, abort

data["status"] = "failed"
data["phase"] = "failed"
data["pid"] = None
data["errorMessage"] = reason
data["completedAt"] = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())

tmp = f"{path}.tmp.{os.getpid()}"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
# F1: the worker does not participate in our mkdir lock. Re-read the path
# immediately before publishing and require the same record identity and file
# generation. A recycled filename must never receive this job's failure.
hook = os.environ.get("CODEX_GUARD_TEST_BEFORE_REPLACE_HOOK")
if hook:
    os.system(hook)
try:
    with open(path) as f:
        current = json.load(f)
    current_stat = os.stat(path)
except Exception:
    os.unlink(tmp)
    sys.exit(0)
if (current.get("id") != data.get("id") or
        (current_stat.st_dev, current_stat.st_ino, current_stat.st_mtime_ns) !=
        (original_stat.st_dev, original_stat.st_ino, original_stat.st_mtime_ns)):
    print("WARN: mark_job_failed CAS mismatch; preserving replacement job", file=sys.stderr)
    os.unlink(tmp)
    sys.exit(0)
os.replace(tmp, path)
PY
  release_job_lock "$json_path"
}

# BSD (macOS) and GNU `stat` disagree on flags -- try both, silently.
stat_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null
}

# True (rc 0) if $1's mtime is no older than $2 seconds. False (incl. missing
# file) counts as "not fresh" -- callers treat that as "log has gone silent".
log_is_fresh() {
  local path="$1" max_age="$2" mtime
  [[ -f "$path" ]] || return 1
  mtime="$(stat_mtime "$path")"
  [[ -n "$mtime" ]] || return 1
  (( $(date +%s) - mtime <= max_age ))
}

# TF-02 (T-f fix 2): stale-worker reaper. Sweeps EVERY job JSON under
# STATE_ROOT (not just $JOB_ID) each poll cycle, so an orphaned or crashed
# guard's job still gets flipped even when nobody is actively watching it.
# NEVER touches a job whose pid answers `kill -0` -- that check is the very
# first thing evaluated per job, before any log-mtime look-up, precisely so a
# live worker can never be marked failed by this sweep.
# T13-SLICE1 W1: also never touches a job younger than GRACE_SEC (its own
# age, read BEFORE the pid check so a young job with a dead placeholder pid
# is skipped just as fast as one with a live pid) -- a job just spawned by
# ANOTHER guard's dispatch can appear in this sweep before its pid field is
# even populated, and the reaper is not the process that armed it, so it has
# no basis to declare it dead this early.
reap_stale_workers() {
  local state_root="$1" job_json status pid log_path job_id_from_path age_sec
  while IFS= read -r job_json; do
    [[ -f "$job_json" ]] || continue
    status="$(read_status "$job_json")"
    [[ "$status" == "running" ]] || continue

    age_sec="$(read_job_age_sec "$job_json")"
    (( age_sec >= GRACE_SEC )) || continue   # too young for the reaper to judge

    pid="$(read_pid "$job_json")"
    [[ -n "$pid" && "$pid" != "null" ]] || continue

    if kill -0 "$pid" 2>/dev/null; then
      continue   # ALIVE -- untouched, no exceptions
    fi

    log_path="$(read_log_file "$job_json")"
    if [[ -n "$log_path" ]] && log_is_fresh "$log_path" 300; then
      continue   # dead pid but log still fresh <=300s -- give it a little more rope
    fi

    job_id_from_path="$(basename "$job_json" .json)"
    log "reaper: ${job_id_from_path} status=running pid=${pid} is dead, log silent >300s -- marking failed:worker_died_silent"
    mark_job_failed "$job_json" "worker_died_silent" 300 "$GRACE_SEC" "$job_id_from_path"
  done < <(find "$state_root" -path '*/jobs/*.json' -type f 2>/dev/null)
}

STATUS=""
DEADLINE=$(( $(date +%s) + TIMEOUT ))

while true; do
  JOB_JSON="$(find_job_json)"
  if [[ -n "$JOB_JSON" && -f "$JOB_JSON" ]]; then
    STATUS="$(read_status "$JOB_JSON")"
    case "$STATUS" in
      completed|failed|cancelled)
        log "job $JOB_ID reached terminal status=$STATUS"
        break
        ;;
    esac

    # TF-01 (fix 1): this job's own pid liveness -- don't blind-wait the full
    # CODEX_GUARD_TIMEOUT (default 1800s) on a worker that already died
    # without writing a terminal status. Gated by FAST_FAIL (=0 restores the
    # pre-TF-01 blind wait for this job's own status only).
    # T13-SLICE1 W1: gated ALSO on this job's own age (>= GRACE_SEC) and on
    # job-id verification (the JSON's own `id` field must equal $JOB_ID) --
    # both checked again inside mark_job_failed against a fresh read.
    if [[ "$FAST_FAIL" == "1" ]]; then
      JOB_AGE="$(read_job_age_sec "$JOB_JSON")"
      if (( JOB_AGE >= GRACE_SEC )); then
        JOB_PID="$(read_pid "$JOB_JSON")"
        if [[ -n "$JOB_PID" && "$JOB_PID" != "null" ]] && ! kill -0 "$JOB_PID" 2>/dev/null; then
          JOB_LOG="$(read_log_file "$JOB_JSON")"
          if [[ -z "$JOB_LOG" ]] || ! log_is_fresh "$JOB_LOG" 120; then
            log "job $JOB_ID pid=$JOB_PID is dead and log silent >120s (age=${JOB_AGE}s) -- declaring failed now (was: blind wait up to ${TIMEOUT}s)"
            mark_job_failed "$JOB_JSON" "worker_process_died" 120 "$GRACE_SEC" "$JOB_ID"
            STATUS="failed"
            break
          fi
        fi
      fi
    fi
  else
    log "job json not found yet for $JOB_ID (searched $STATE_ROOT)"
  fi

  # TF-02 (fix 2): broader reaper sweep, every poll cycle, regardless of
  # whether $JOB_ID's own record was found above. Gated by FAST_FAIL (=0
  # restores the pre-TF-02 behavior: no sweep of other jobs at all).
  if [[ "$FAST_FAIL" == "1" ]]; then
    reap_stale_workers "$STATE_ROOT"
  fi

  if (( $(date +%s) >= DEADLINE )); then
    STATUS="${STATUS:-unknown}-timeout"
    log "timeout after ${TIMEOUT}s waiting for $JOB_ID (last status='${STATUS}')"
    break
  fi

  sleep "$POLL_INTERVAL_SEC"
done

COMMIT="n/a"
if git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [[ -n "$(git -C "$CWD" status --porcelain 2>/dev/null)" ]]; then
    COMMIT="uncommitted"
    log "job $JOB_ID left $CWD dirty -- report-only, nothing staged or committed by this script"
  else
    COMMIT="clean"
  fi
else
  COMMIT="n/a"
  log "$CWD is not inside a git work tree -- status-only report"
fi

emit_final "CODEX-GUARD ${JOB_ID} status=${STATUS:-unknown} commit=${COMMIT} cwd=${CWD}"
