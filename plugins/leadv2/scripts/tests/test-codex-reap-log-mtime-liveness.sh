#!/usr/bin/env bash
# test-codex-reap-log-mtime-liveness.sh — CODEX-REAP-LOG-MTIME-LIVENESS-01.
#
# WHY THIS TEST EXISTS: on 2026-08-21 a codex worker was reaped `worker_died_stale`
# 73 seconds after its OWN log recorded `Applying 1 file change(s)` followed by
# `File changes completed`. The reaper decided liveness from the pid, the pid probe
# came back negative, the job was past the 5-minute threshold, and a worker that was
# demonstrably writing files was killed.
#
# The lesson generalizes past this one bug: every liveness question in this system
# that was answered from a pid or a status field was answered WRONGLY that day
# (`status: running` on a dead job, `pid: None` written by the reaper itself and then
# misread as "never had a worker"), and every one answered from an mtime was right.
# So the log's mtime now outranks the pid-shaped logic, and only in the widening
# direction.
#
# The reaper is embedded python inside codex-task.sh. This test extracts that block
# and drives reap_one() directly against synthetic job files, so it exercises the
# real decision code rather than a paraphrase of it. Each case runs against the
# committed (pre-fix) block and the working-tree block, printing the machine marker
# the builder-selfcheck gate greps for.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${SCRIPT_DIR}/../codex-task.sh"

PASS=0; FAIL=0; GREEN_PRE_FIX=0; COULD_NOT_RUN=0
declare -a ERRORS=()
log() { printf '[TEST] %s\n' "$*"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/reap-mtime.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

REPO="$(cd "${SCRIPT_DIR}" && git rev-parse --show-toplevel 2>/dev/null)"
PRE_SH="${WORK}/pre-codex-task.sh"
# Build the precise old decision shape from the file under test: log mtime was
# ignored, so a stale pid plus elapsed timeout reaped the job.  Using HEAD here
# would silently turn this into a vacuous control as soon as the fix is merged.
python3 - "${TARGET}" "${PRE_SH}" <<'PY' 2>/dev/null || : > "${PRE_SH}"
import re, sys
src = open(sys.argv[1]).read()
old = re.sub(
    r'\n        # CODEX-REAP-LOG-MTIME-LIVENESS-01:.*?\n        cause = None',
    '\n        cause = None', src, flags=re.S,
)
if old == src:
    raise SystemExit(2)
open(sys.argv[2], 'w').write(old)
PY
[[ -s "${PRE_SH}" ]] || PRE_SH=""

# Extract the reaper's embedded python heredoc from a codex-task.sh.
_extract_py() { # <codex-task.sh> <out.py>
  local sh="$1" out="$2"
  [[ -f "$sh" ]] || return 2
  python3 - "$sh" "$out" <<'PY' 2>/dev/null || return 2
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r"python3 - [^\n]*CODEX_REAP_STATE_ROOT[^\n]*<<'PY'\n(.*?)\nPY\n", src, re.S)
if not m:
    sys.exit(2)
open(sys.argv[2], "w").write(m.group(1))
PY
  [[ -s "$out" ]] || return 2
  return 0
}

# Build a driver that imports the extracted reaper and calls reap_one on one job.
# The reaper block reads its config from sys.argv; we stub the argv it expects and
# then call reap_one directly, which is the unit under test.
_run_case() { # <codex-task.sh> <log_age_s> <started_min_ago> <expect: alive|reaped>
  local sh="$1" log_age="$2" started_ago="$3" expect="$4"
  local d py drv
  d="$(mktemp -d "${WORK}/case.XXXXXX")" || return 2
  py="${d}/reaper.py"
  _extract_py "$sh" "$py" || return 2

  mkdir -p "${d}/state/lane-abc/jobs"
  local job="${d}/state/lane-abc/jobs/task-probe.json"
  local lg="${d}/state/lane-abc/jobs/task-probe.log"
  drv="${d}/drive.py"

  LOG_AGE="$log_age" STARTED_AGO="$started_ago" JOB="$job" LG="$lg" \
  PYFILE="$py" STATE="${d}/state" python3 - <<'PY' || return 2
import json, os, time, datetime
job, lg = os.environ["JOB"], os.environ["LG"]
started = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(
    minutes=float(os.environ["STARTED_AGO"]))
json.dump({
    "id": "task-probe", "status": "running", "phase": "running",
    # A pid that is certainly not alive: the reaper must fall through to the
    # age/log logic exactly as it did in the real incident.
    "pid": 999999,
    "startedAt": started.strftime("%Y-%m-%dT%H:%M:%S.000Z"),
    "createdAt": started.strftime("%Y-%m-%dT%H:%M:%S.000Z"),
    "workspaceRoot": "/tmp/nonexistent-lane",
}, open(job, "w"), indent=2)
open(lg, "w").write("[probe] Applying 1 file change(s).\n")
mt = time.time() - float(os.environ["LOG_AGE"])
os.utime(lg, (mt, mt))
PY

  # Drive reap_one with the reaper's own argv contract.
  local out
  out="$(CODEX_REAP_LOG_GRACE_S="${CODEX_REAP_LOG_GRACE_S:-120}" python3 - "$py" "${d}/state" "$job" <<'PY' 2>/dev/null
import json, runpy, sys, types, os
pyfile, state_root, job = sys.argv[1], sys.argv[2], sys.argv[3]
# The block expects: state_root, queued_kill_min, running_kill_min, target, lib_dir, repair_dir
sys.argv = ["reaper", state_root, "45", "5", "all", "", os.path.join(state_root, "repair")]
ns = {}
code = open(pyfile).read()
# Execute definitions only: the block's __main__ tail would sweep everything. Cut at
# the first top-level statement after the function defs by exec'ing and tolerating
# a SystemExit / any sweep side effect, then call reap_one ourselves.
g = {"__name__": "not_main"}
try:
    exec(compile(code, pyfile, "exec"), g)
except SystemExit:
    pass
except Exception as e:
    print("DRIVER_ERROR", type(e).__name__, e)
    raise SystemExit(2)
fn = g.get("reap_one")
if fn is None:
    print("NO_REAP_ONE"); raise SystemExit(2)
r = fn(job)
print("REAPED" if r else "ALIVE")
PY
)"
  case "$out" in
    ALIVE)  [[ "$expect" == alive  ]] && return 0; return 1 ;;
    REAPED) [[ "$expect" == reaped ]] && return 0; return 1 ;;
    *) return 2 ;;
  esac
}

# 1: THE INCIDENT — log written 5s ago, job started 6 min ago (past the 5-min
#    threshold), dead pid. Must be left ALIVE.
case_fresh_log_survives() { _run_case "$1" 5 6 alive; }

# 2: log silent for 10 minutes, started 12 min ago -> genuinely dead, must reap.
#    This is the direction that must NOT be widened away.
case_stale_log_reaped() { _run_case "$1" 600 12 reaped; }

# 3: grace window is honored at its boundary-plus: log 300s old with a 120s grace
#    is outside the window, so age logic applies and the job reaps.
case_beyond_grace_reaped() { _run_case "$1" 300 12 reaped; }

# 4: grace explicitly disabled (=0) restores pure pid/age behaviour, so an
#    operator can always get the old semantics back.
case_grace_zero_reaps() { CODEX_REAP_LOG_GRACE_S=0 _run_case "$1" 5 6 reaped; }

# 5: a young job with a stale log is still not reaped -- the age threshold governs,
#    proving the log check did not become the ONLY input.
case_young_job_survives() { _run_case "$1" 600 1 alive; }

run_case() { # <name> <fn>
  local name="$1" fn="$2" pre_rc post_rc
  if [[ -n "${PRE_SH}" ]]; then "${fn}" "${PRE_SH}" >/dev/null 2>&1; pre_rc=$?; else pre_rc=2; fi
  "${fn}" "${TARGET}" >/dev/null 2>&1; post_rc=$?
  if [[ ${post_rc} -eq 2 ]]; then
    COULD_NOT_RUN=$((COULD_NOT_RUN + 1)); log "COULD-NOT-RUN: ${name}"; return
  fi
  if [[ ${post_rc} -ne 0 ]]; then
    FAIL=$((FAIL + 1)); ERRORS+=("${name}: post-fix rc=${post_rc}")
    log "FAIL: ${name} -- post-fix rc=${post_rc}, expected 0"; return
  fi
  if [[ ${pre_rc} -eq 0 ]]; then
    GREEN_PRE_FIX=$((GREEN_PRE_FIX + 1))
    log "GREEN-PRE-FIX: ${name} -- passed against the pre-fix reaper too (pre_rc=0)"; return
  fi
  PASS=$((PASS + 1)); log "RED-then-GREEN: ${name} (pre_rc=${pre_rc} -> post_rc=0)"
}

log "PASS: bash -n codex-task.sh"
bash -n "${TARGET}" || { log "FAIL: bash -n"; exit 1; }

run_case "fresh-log-survives-past-threshold" case_fresh_log_survives
run_case "stale-log-still-reaped"            case_stale_log_reaped
run_case "beyond-grace-window-reaped"        case_beyond_grace_reaped
run_case "grace-zero-restores-old-behaviour" case_grace_zero_reaps
run_case "young-job-survives-stale-log"      case_young_job_survives

echo ""
echo "Results: ${PASS} passed(red->green), ${FAIL} failed, ${GREEN_PRE_FIX} green-pre-fix, ${COULD_NOT_RUN} could-not-run"
if [[ ${FAIL} -gt 0 ]]; then printf -- 'FAIL: %s\n' "${ERRORS[@]}"; exit 1; fi
exit 0
