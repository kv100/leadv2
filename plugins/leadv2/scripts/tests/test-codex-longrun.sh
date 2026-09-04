#!/bin/bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: codex-task.sh
# test-codex-longrun.sh — CODEX-DIES-MID-TEST-01
#
# A codex worker whose child runs a long test dies silently on this host
# (killer: SessionEnd hook's sendBrokerShutdown + terminateProcessTree —
# see docs/handoff/CODEX-DIES-MID-TEST-01/report.md). The worker's job log
# just STOPS mid-command, status stays "running" for hours, and nothing
# tells the router the arm failed. This suite pins the three closures:
#
#   T1  a reaped dead-worker job carries a TERMINAL line in ITS OWN job log
#       naming the cause (not a bare stop);
#   T2  the reap emits a durable leadv2-events journal row (kind=
#       codex_worker_died, arm=codex) so the dispatch journal sees the death;
#   T3  the reap records an arm-cooldown failure (reason=<cause>) so the
#       router's next resolve cools the codex arm — without ever touching a
#       glm.* state file (no arm excluded by name, no cross-arm spill);
#   T4  `codex-task.sh __deathwatch` — the per-job watcher armed at dispatch —
#       reaps a dead-worker job within its poll interval and stays quiet
#       (job untouched) while the worker pid is ALIVE (long test running).
#
# Hermetic: CODEX_GUARD_STATE_ROOT / LEADV2_EVENT_LOG_DIR /
# LEADV2_ARM_COOLDOWN_DIR all point into a mktemp fixture; no real job store,
# no codex dispatch, no network.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_TASK="${SCRIPT_DIR}/../codex-task.sh"
EVENT_SH="${SCRIPT_DIR}/../../leadv2-event.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/codex-longrun.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
STATE_ROOT="$TMP/state"
JOBS_DIR="$STATE_ROOT/fixture-lane/jobs"
mkdir -p "$JOBS_DIR"
EVENT_LOG_DIR="$TMP/events"
ARM_COOL_DIR="$TMP/arm-cooldown"
export CODEX_GUARD_STATE_ROOT="$STATE_ROOT"
export LEADV2_EVENT_LOG_DIR="$EVENT_LOG_DIR"
export LEADV2_ARM_COOLDOWN_DIR="$ARM_COOL_DIR"

FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }

# make_dead_pid: spawn a short-lived child, wait for it, echo its (dead) pid.
# kill(pid,0) AND killpg(pgid,0) must both fail for the reaper to judge it dead.
make_dead_pid() {
  sh -c 'exit 0' &
  local p=$!
  wait "$p" 2>/dev/null
  printf '%s' "$p"
}

# make_job <id> <pid-or-null> <status> [log_age_s] -> writes jobs/<id>.json,
# echoes log path. The job log's mtime is the reaper's liveness source of truth
# (CODEX_REAP_LOG_GRACE_S, default 120s): a dead-worker fixture must backdate
# its log so the reaper judges it, the same way an overnight corpse's log went
# quiet long before any sweep found it.
make_job() {
  local id="$1" pid="$2" status="$3" log_age_s="${4:-0}"
  local log="$JOBS_DIR/$id.log"
  printf '%s\n' "[2026-09-01T13:33:16Z] Running command: timeout 120 bash test-something" > "$log"
  if [[ "$log_age_s" -gt 0 ]]; then
    python3 -c "import os,sys,time; os.utime(sys.argv[1], (time.time()-float(sys.argv[2]),)*2)" "$log" "$log_age_s"
  fi
  python3 - "$JOBS_DIR/$id.json" "$id" "$pid" "$status" "$log" <<'PYEOF'
import json, sys
from datetime import datetime, timedelta, timezone
path, jid, pid, status, log = sys.argv[1:6]
# Aged 10min past start: past CODEX_RUNNING_DEAD_KILL_MIN (5) so the plain
# `reap` sweep judges the fixture job, like the overnight incident jobs were.
ts = (datetime.now(timezone.utc) - timedelta(minutes=10)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
rec = {
    "id": jid, "kind": "task", "kindLabel": "task", "title": "fixture",
    "status": status, "phase": status,
    "pid": None if pid == "null" else int(pid),
    "createdAt": ts, "startedAt": ts,
    "workspaceRoot": "/tmp/fixture-lane-ws",
    "logFile": log, "summary": "fixture job", "request": {"prompt": "x"},
}
with open(path, "w") as f:
    json.dump(rec, f, indent=2)
PYEOF
  printf '%s' "$log"
}

terminal_line_present() { # <log>
  grep -q 'TERMINAL: job=' "$1" && grep -q 'cause=' "$1"
}

# ── T1+T2+T3: plain `reap` on a dead worker ──────────────────────────────────
DEAD_PID="$(make_dead_pid)"
J1=task-fixdead01-aaaa01
LOG1="$(make_job "$J1" "$DEAD_PID" "running" 600)"

REAP_OUT="$TMP/reap1.out"
CODEX_VERBOSE=0 bash "$CODEX_TASK" reap > "$REAP_OUT" 2> "$TMP/reap1.err"
RC=$?
[[ $RC -eq 0 ]] || fail "T1: reap rc=$RC (stderr: $(tail -1 "$TMP/reap1.err"))"
if terminal_line_present "$LOG1"; then
  pass "T1: reaped job log carries TERMINAL line naming cause"
else
  fail "T1: job log still ends bare at the last Running-command line (no TERMINAL line)"
fi

J1_STATUS="$(python3 -c "import json;print(json.load(open('$JOBS_DIR/$J1.json'))['status'])")"
[[ "$J1_STATUS" == "failed" ]] || fail "T1b: job status=$J1_STATUS, expected failed"

# ── T4: __deathwatch ─────────────────────────────────────────────────────────
# T4a: dead worker → deathwatch reaps it inside its poll interval.
# The deathwatch (armed on every real --background dispatch) is ALSO the
# journal+arm-ladder announcer: plain `reap` stays a pure state mutation so
# hermetic suites exercising it can never write the LIVE arm ladder (measured
# 2026-09-01: recording inside _codex_reap made every test-codex-task-reap run
# append real cooldown rows, which then refused the next real dispatch).
DEAD_PID2="$(make_dead_pid)"
J2=task-fixdead02-bbbb02
LOG2="$(make_job "$J2" "$DEAD_PID2" "running" 600)"
CODEX_DEATHWATCH_POLL_S=1 CODEX_DEATHWATCH_MAX_S=10 \
  bash "$CODEX_TASK" __deathwatch "$J2" --state-dir "$STATE_ROOT/fixture-lane" \
  > "$TMP/dw1.out" 2>&1
RC=$?
[[ $RC -eq 0 ]] || fail "T4a: deathwatch rc=$RC"
if terminal_line_present "$LOG2"; then
  pass "T4a: deathwatch reaped dead worker; TERMINAL line landed"
else
  fail "T4a: deathwatch did not produce a TERMINAL line for a dead worker"
fi

EVFILE="$(ls "$EVENT_LOG_DIR"/*.jsonl 2>/dev/null | head -1)"
if [[ -n "$EVFILE" ]] && grep -q '"kind": *"codex_worker_died"' "$EVFILE" 2>/dev/null \
   && grep -q '"arm": *"codex"' "$EVFILE" 2>/dev/null; then
  pass "T2: dispatch journal row emitted (kind=codex_worker_died arm=codex)"
else
  fail "T2: no codex_worker_died row in the dispatch journal under $EVENT_LOG_DIR"
fi

# The deathwatch names the cause itself: worker_died_stale when the shared
# app-server is alive, transport_gone_app_server_absent when it is gone too
# (the incident signature). Either way an arm failure must be recorded.
if [[ -f "$ARM_COOL_DIR/codex.state" ]] \
   && grep -Eq 'reason=(worker_died_stale|transport_gone_app_server_absent)' "$ARM_COOL_DIR/codex.state"; then
  pass "T3: arm-cooldown recorded the reap cause for codex ($(tail -1 "$ARM_COOL_DIR/codex.state" | grep -o 'reason=[^ ]*'))"
else
  fail "T3: no arm failure recorded in $ARM_COOL_DIR/codex.state"
fi
if [[ -e "$ARM_COOL_DIR/glm.state" ]]; then
  fail "T3b: cross-arm spill — glm.state was written by a codex-only path"
else
  pass "T3b: no cross-arm spill (no glm.state)"
fi

# T4b: ALIVE worker (long test running) → deathwatch must NOT reap it, and must
# exit within MAX_S rather than hang.
sleep 60 &
LIVE_PID=$!
J3=task-fixlive03-cccc03
LOG3="$(make_job "$J3" "$LIVE_PID" "running")"
DW_START="$(date +%s)"
CODEX_DEATHWATCH_POLL_S=1 CODEX_DEATHWATCH_MAX_S=3 \
  bash "$CODEX_TASK" __deathwatch "$J3" --state-dir "$STATE_ROOT/fixture-lane" \
  > "$TMP/dw2.out" 2>&1
RC=$?
DW_ELAPSED=$(( $(date +%s) - DW_START ))
kill "$LIVE_PID" 2>/dev/null; wait "$LIVE_PID" 2>/dev/null
J3_STATUS="$(python3 -c "import json;print(json.load(open('$JOBS_DIR/$J3.json'))['status'])")"
[[ $RC -eq 0 ]] || fail "T4b: deathwatch rc=$RC on live worker"
[[ "$J3_STATUS" == "running" ]] || fail "T4b: LIVE worker was reaped (status=$J3_STATUS)"
[[ $DW_ELAPSED -le 10 ]] || fail "T4b: deathwatch hung ${DW_ELAPSED}s past MAX_S"
if [[ "$J3_STATUS" == "running" && $RC -eq 0 && $DW_ELAPSED -le 10 ]]; then
  pass "T4b: live (long-test) worker untouched; deathwatch exits on timeout"
fi
if terminal_line_present "$LOG3"; then
  fail "T4b: TERMINAL line written for a LIVE job (false kill record)"
else
  pass "T4b: no kill record for a live job"
fi

rm -rf "$TMP"
if [[ $FAIL -eq 0 ]]; then
  echo "ALL PASS"
  exit 0
fi
echo "SOME FAILED"
exit 1
