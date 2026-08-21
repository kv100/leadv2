#!/usr/bin/env bash
# test-codex-transport-attribution.sh — CODEX-TRANSPORT-ATTRIBUTION-01.
#
# WHY THIS TEST EXISTS: `codex app-server` is a SINGLE shared process, and this
# script's own header records the coupling — "a job dies the instant its launching
# client drops the app-server connection." So when the server goes, every in-flight
# job across every worktree dies together, and each was stamped `worker_died_stale`:
# one shared cause reported as N independent worker failures.
#
# On 2026-08-21 that cost a day. Three lanes in three different worktrees stopped
# logging within 32 seconds of each other, were filed under two different per-job
# diagnoses, and three separate wrong mechanisms were investigated (zero API
# credits, concurrent codex jobs, unregistered worktrees) before anyone checked
# whether the shared server was alive. It was not.
#
# What is asserted here is the CAUSE STRING, not just that a reap happened — the
# reap was always correct, the diagnosis was not.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${SCRIPT_DIR}/../codex-task.sh"

PASS=0; FAIL=0; GREEN_PRE_FIX=0; COULD_NOT_RUN=0
declare -a ERRORS=()
log() { printf '[TEST] %s\n' "$*"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/transport-attr.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

REPO="$(cd "${SCRIPT_DIR}" && git rev-parse --show-toplevel 2>/dev/null)"
PRE_SH="${WORK}/pre-codex-task.sh"
if [[ -n "${REPO}" ]]; then
  git -C "${REPO}" show "HEAD:plugins/leadv2/scripts/codex-task.sh" > "${PRE_SH}" 2>/dev/null || : > "${PRE_SH}"
fi
[[ -s "${PRE_SH}" ]] || PRE_SH=""

_extract_py() { # <codex-task.sh> <out.py>
  python3 - "$1" "$2" <<'PY' 2>/dev/null || return 2
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r"python3 - [^\n]*CODEX_REAP_STATE_ROOT[^\n]*<<'PY'\n(.*?)\nPY\n", src, re.S)
if not m:
    sys.exit(2)
open(sys.argv[2], "w").write(m.group(1))
PY
  [[ -s "$2" ]] || return 2
}

# Runs reap_one on a synthetic dead-pid, stale-log, past-threshold job and prints
# the cause string the reaper wrote. `fake_pgrep` controls whether a `codex
# app-server` process appears to exist, via a PATH shim — no real process is
# started or killed.
_cause_with() { # <codex-task.sh> <server_present: yes|no>
  local sh="$1" present="$2" d py shim
  d="$(mktemp -d "${WORK}/case.XXXXXX")" || return 2
  py="${d}/reaper.py"
  _extract_py "$sh" "$py" || return 2

  shim="${d}/bin"; mkdir -p "$shim"
  if [[ "$present" == yes ]]; then
    printf '#!/bin/sh\necho 4242\nexit 0\n' > "${shim}/pgrep"
  else
    printf '#!/bin/sh\nexit 1\n' > "${shim}/pgrep"
  fi
  chmod +x "${shim}/pgrep"

  mkdir -p "${d}/state/lane-abc/jobs"
  local job="${d}/state/lane-abc/jobs/task-probe.json"
  local lg="${d}/state/lane-abc/jobs/task-probe.log"
  JOB="$job" LG="$lg" python3 - <<'PY' || return 2
import json, os, time, datetime
started = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=12)
json.dump({"id": "task-probe", "status": "running", "phase": "running", "pid": 999999,
           "startedAt": started.strftime("%Y-%m-%dT%H:%M:%S.000Z"),
           "createdAt": started.strftime("%Y-%m-%dT%H:%M:%S.000Z"),
           "workspaceRoot": "/tmp/nonexistent-lane"}, open(os.environ["JOB"], "w"), indent=2)
lg = os.environ["LG"]
open(lg, "w").write("[probe] silent for a long time\n")
mt = time.time() - 900
os.utime(lg, (mt, mt))
PY

  PATH="${shim}:${PATH}" python3 - "$py" "${d}/state" "$job" <<'PY' 2>/dev/null
import json, sys, os
pyfile, state_root, job = sys.argv[1], sys.argv[2], sys.argv[3]
sys.argv = ["reaper", state_root, "45", "5", "all", "", os.path.join(state_root, "repair")]
g = {"__name__": "not_main"}
try:
    exec(compile(open(pyfile).read(), pyfile, "exec"), g)
except SystemExit:
    pass
except Exception:
    raise SystemExit(2)
fn = g.get("reap_one")
if fn is None:
    raise SystemExit(2)
r = fn(job)
if not r:
    print("NOT_REAPED"); raise SystemExit(0)
print(json.load(open(job)).get("errorMessage", ""))
PY
}

# 1: server ABSENT -> the death is attributed to the shared transport.
case_absent_says_transport() {
  local out; out="$(_cause_with "$1" no)" || return 2
  [[ -z "$out" ]] && return 2
  [[ "$out" == *transport_gone* ]] && return 0
  return 1
}

# 2: server PRESENT -> the old per-job cause is preserved. The fix must not
#    relabel every death as a transport problem; that would be the same sin in
#    the opposite direction.
case_present_keeps_stale() {
  local out; out="$(_cause_with "$1" yes)" || return 2
  [[ -z "$out" ]] && return 2
  [[ "$out" == *worker_died_stale* ]] && return 0
  return 1
}

# 3: either way the job DOES reach a terminal state -- attribution must not
#    accidentally leave a dead job marked running forever, which is the lying
#    status this whole thread keeps tripping over.
case_still_terminal() {
  local out; out="$(_cause_with "$1" no)" || return 2
  [[ "$out" == "NOT_REAPED" ]] && return 1
  [[ -n "$out" ]] && return 0
  return 1
}

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

run_case "absent-server-blames-transport" case_absent_says_transport
run_case "present-server-keeps-per-job"   case_present_keeps_stale
run_case "always-reaches-terminal"        case_still_terminal

echo ""
echo "Results: ${PASS} passed(red->green), ${FAIL} failed, ${GREEN_PRE_FIX} green-pre-fix, ${COULD_NOT_RUN} could-not-run"
if [[ ${FAIL} -gt 0 ]]; then printf -- 'FAIL: %s\n' "${ERRORS[@]}"; exit 1; fi
exit 0
