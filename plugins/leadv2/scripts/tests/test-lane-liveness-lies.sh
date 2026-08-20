#!/usr/bin/env bash
# tests/test-lane-liveness-lies.sh — LANE-LIVENESS-LIES-01.
#
# Root 1 (symptom A + B2): leadv2-active-registry.sh:556 wrote pid_birth via
# `ps -o lstart= | tr -s ' '` (Darwin right-pads the field; `tr -s ' '`
# collapses the trailing run to ONE space, never strips it). The reader
# (_pid_birth_of() in leadv2-lanes-snapshot.sh) `.strip()`s. So stored != live for
# EVERY healthy lane with a recorded pid_birth -> "pid birth mismatch
# (reuse)" fired on demonstrably alive processes and, after 2 polls,
# corroborated-dead escalation. Change 1a normalises both sides (writer +
# stored-at-read) to the same trim the (now-retired) supervisor loop used at line 115. Change 1b
# adds a freshness veto: a lane whose authoritative liveness verdict
# (leadv2-lane-liveness.sh, log-mtime-based) is fresh must never escalate,
# regardless of what the pid heuristic says.
#
# All four tests below drive the REAL leadv2-lanes-snapshot.sh --json binary
# against a scratch active.yaml (never the live one) -- no assertion on a
# helper function in isolation.
#
# Run: bash scripts/tests/test-lane-liveness-lies.sh
# Exit 0 = all pass; non-zero = failures found.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SUPERVISE_SH="${PLUGIN_DIR}/scripts/leadv2-lanes-snapshot.sh"
STATE_PATH_SH="${PLUGIN_DIR}/scripts/leadv2-state-path.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

CLEANUP_DIRS=()
cleanup() {
  for d in "${CLEANUP_DIRS[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
  done
  return 0
}
trap cleanup EXIT

_new_fixture() {
  local repo state
  repo="$(lv2_mktemp_dir "lll-repo")"
  state="$(lv2_mktemp_dir "lll-state")"
  CLEANUP_DIRS+=("$repo" "$state")
  (cd "$repo" && git init -q)
  lv2_assert_scratch_repo "$repo"
  mkdir -p "$repo/docs/leadv2" "$repo/docs/handoff"
  printf -- '%s %s\n' "$repo" "$state"
}

_active_yaml() {
  LEADV2_PROJECT_ROOT="$1" LEADV2_STATE_ROOT="$2" \
    PROJECT_ROOT="$1" bash "$STATE_PATH_SH" active.yaml
}

json_get() {
  python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
print($1)
"
}

_bypass_reconcile_grace() {
  # The first 2 FULL reconciliation cycles after rollout are ALWAYS
  # observe-only for legacy rows (leadv2-lanes-snapshot.sh "D-e") -- pre-seed
  # .supervise-last.json with reconcile_cycle_count=5 so this test's two
  # polls are past that grace window and prunes actually apply, exactly
  # like test-supervise-v2.sh's Test 7/2 fixtures do.
  local repo="$1" state="$2" snap
  snap="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    PROJECT_ROOT="$repo" bash "$STATE_PATH_SH" .supervise-last.json)"
  mkdir -p "$(dirname "$snap")"
  printf -- '{"rendered_at":"2020-01-01T00:00:00+00:00","tasks":{},"reported_events":[],"dead_candidates":{},"reconcile_cycle_count":5}' > "$snap"
}

_row_present() {
  # _row_present <active_path> <task_id>
  python3 -c "
import yaml
d = yaml.safe_load(open('$1')) or {}
print(any(s.get('task_id')=='$2' for s in d.get('sessions', [])))
"
}

# ── shared spawn: a real, long-lived process this test controls ────────────
_SLEEPER_PID=""
_start_sleeper() {
  sleep 300 &
  _SLEEPER_PID=$!
}
_stop_sleeper() {
  [[ -n "$_SLEEPER_PID" ]] && kill "$_SLEEPER_PID" 2>/dev/null || true
  wait "$_SLEEPER_PID" 2>/dev/null || true
}
trap '_stop_sleeper; cleanup' EXIT

# The OLD (pre-fix) writer formula: `tr -s ' '` alone, no strip. On Darwin
# `ps -o lstart=` right-pads the field, so this preserves the trailing space
# the python reader's `.strip()` used to disagree with.
_old_writer_birth() {
  ps -o lstart= -p "$1" 2>/dev/null | tr -s ' '
}

# ── Test 1: live lane, birth written in the OLD (buggy) writer form -> alive ─

test_1_live_lane_old_writer_form_reported_alive() {
  log "Test 1: live pid + pre-fix trailing-space pid_birth -> reader normalises -> NOT flagged"
  _start_sleeper
  local repo state active_path old_birth
  read -r repo state < <(_new_fixture)
  active_path="$(_active_yaml "$repo" "$state")"
  old_birth="$(_old_writer_birth "$_SLEEPER_PID")"
  if [[ -z "$old_birth" ]]; then
    fail "Test 1: could not read birth of sleeper pid $_SLEEPER_PID"
    _stop_sleeper
    return
  fi
  _bypass_reconcile_grace "$repo" "$state"
  mkdir -p "$(dirname "$active_path")"
  python3 - "$active_path" "$_SLEEPER_PID" "$old_birth" <<'PY'
import sys, yaml
path, pid, birth = sys.argv[1], int(sys.argv[2]), sys.argv[3]
doc = {"sessions": [{
    "task_id": "OLD-WRITER-FORM-LIVE",
    "session_id": "s1",
    "started_at": "2020-01-01T00:00:00+00:00",
    "phase": "build",
    "pid": pid,
    "pid_birth": birth,  # deliberately the UN-stripped pre-fix form
    "protocol_version": 2,
    "backend": "terminal",
    "last_pulse_at": "2020-01-01T00:00:00+00:00",
    "stale": False,
}]}
with open(path, "w") as fh:
    yaml.safe_dump(doc, fh)
PY

  local out1 out2 dead2
  out1="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$SUPERVISE_SH" --json 2>/dev/null)" || { fail "Test 1: poll 1 exited nonzero"; _stop_sleeper; return; }
  out2="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$SUPERVISE_SH" --json 2>/dev/null)" || { fail "Test 1: poll 2 exited nonzero"; _stop_sleeper; return; }
  dead2="$(printf -- '%s' "$out2" | json_get "any(x['task_id']=='OLD-WRITER-FORM-LIVE' for x in d.get('dead', []))")"
  local still
  still="$(_row_present "$active_path" "OLD-WRITER-FORM-LIVE")"
  if [[ "$dead2" == False && "$still" == True ]]; then
    pass "Test 1: pre-fix writer-form birth on a genuinely live pid -> NOT dead, row kept"
  else
    fail "Test 1: dead=$dead2 still_present=$still (writer/reader trim skew must not false-flag a live lane)"
  fi
  _stop_sleeper
}

# ── Test 2: genuinely dead lane still reported dead (control case) ─────────

test_2_dead_lane_still_dead() {
  log "Test 2: dead pid (birth match irrelevant) + missing tmux window -> still corroborated dead"
  local repo state active_path snap sock
  read -r repo state < <(_new_fixture)
  active_path="$(_active_yaml "$repo" "$state")"
  snap="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    PROJECT_ROOT="$repo" bash "$STATE_PATH_SH" .supervise-last.json)"
  mkdir -p "$(dirname "$snap")"

  local dead_pid
  ( sleep 0 ) & dead_pid=$!
  wait "$dead_pid" 2>/dev/null || true   # pid now exits; reused-or-not, os.kill(pid,0) will fail

  cat > "$active_path" <<YAML
sessions:
  - task_id: GENUINELY-DEAD
    session_id: s2
    started_at: "2020-01-01T00:00:00+00:00"
    phase: build
    pid: $dead_pid
    pid_birth: null
    protocol_version: 2
    backend: tmux
    tmux_window: GENUINELY-DEAD
    last_pulse_at: "2020-01-01T00:00:00+00:00"
    stale: false
YAML
  printf -- '{"rendered_at":"2020-01-01T00:00:00+00:00","tasks":{},"reported_events":{},"dead_candidates":{},"reconcile_cycle_count":5}' > "$snap"

  local sock
  sock="lll-t2-$$-$RANDOM"
  LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_SUPERVISE_TMUX_SOCKET="$sock" bash "$SUPERVISE_SH" --json >/dev/null 2>&1 \
    || { fail "Test 2: poll 1 exited nonzero"; return; }
  LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_SUPERVISE_TMUX_SOCKET="$sock" bash "$SUPERVISE_SH" --json >/dev/null 2>&1 \
    || { fail "Test 2: poll 2 exited nonzero"; return; }

  local removed
  removed="$(python3 -c "
import yaml
d = yaml.safe_load(open('$active_path')) or {}
print(not any(s.get('task_id')=='GENUINELY-DEAD' for s in d.get('sessions', [])))
")"
  if [[ "$removed" == True ]]; then
    pass "Test 2: genuinely dead pid + missing tmux window -> still corroborated dead, pruned"
  else
    fail "Test 2: removed=$removed (Change 1a must not disable real-death detection)"
  fi
}

# ── Test 3: real pid-reuse (different birth) still caught, no liveness row ──

test_3_pid_reuse_still_caught() {
  log "Test 3: live pid + genuinely DIFFERENT stored birth, no liveness row -> mismatch still fires"
  _start_sleeper
  local repo state active_path fake_birth
  read -r repo state < <(_new_fixture)
  active_path="$(_active_yaml "$repo" "$state")"
  # A birth timestamp that cannot possibly match the sleeper's real birth --
  # this is the reuse case: same pid number, different process instance.
  fake_birth="Wed Jan  1 00:00:00 2020"
  _bypass_reconcile_grace "$repo" "$state"

  python3 - "$active_path" "$_SLEEPER_PID" "$fake_birth" <<'PY'
import sys, yaml
path, pid, birth = sys.argv[1], int(sys.argv[2]), sys.argv[3]
doc = {"sessions": [{
    "task_id": "REUSE-STILL-CAUGHT",
    "session_id": "s3",
    "started_at": "2020-01-01T00:00:00+00:00",
    "phase": "build",
    "pid": pid,
    "pid_birth": birth,
    "protocol_version": 2,
    "backend": "terminal",
    "last_pulse_at": "2020-01-01T00:00:00+00:00",
    "stale": False,
    # deliberately NO log_path -> lane_liveness_by_id has no row for this
    # task_id -> the Change 1b freshness veto must not fire (absence of
    # evidence is never evidence of life).
}]}
with open(path, "w") as fh:
    yaml.safe_dump(doc, fh)
PY

  LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$SUPERVISE_SH" --json >/dev/null 2>&1 || { fail "Test 3: poll 1 exited nonzero"; _stop_sleeper; return; }
  LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$SUPERVISE_SH" --json >/dev/null 2>&1 || { fail "Test 3: poll 2 exited nonzero"; _stop_sleeper; return; }

  local removed
  removed="$(python3 -c "
import yaml
d = yaml.safe_load(open('$active_path')) or {}
print(not any(s.get('task_id')=='REUSE-STILL-CAUGHT' for s in d.get('sessions', [])))
")"
  if [[ "$removed" == True ]]; then
    pass "Test 3: genuine birth mismatch (pid reuse), no liveness row -> still corroborated dead, pruned"
  else
    fail "Test 3: removed=$removed (normalising must not disable real pid-reuse detection)"
  fi
  _stop_sleeper
}

# ── Test 4: freshness veto (Change 1b) -- fresh stream outranks pid heuristic ─

test_4_freshness_veto_suppresses_escalation() {
  log "Test 4: same birth-mismatch as Test 3, but a FRESH stream mtime -> veto suppresses escalation"
  _start_sleeper
  local repo state active_path fake_birth log_rel log_abs
  read -r repo state < <(_new_fixture)
  active_path="$(_active_yaml "$repo" "$state")"
  fake_birth="Wed Jan  1 00:00:00 2020"

  mkdir -p "$repo/docs/handoff/dispatch-freshveto"
  log_rel="docs/handoff/dispatch-freshveto/developer.stream.jsonl"
  log_abs="$repo/$log_rel"
  printf '{"type":"assistant","text":"still working"}\n' > "$log_abs"   # mtime = now
  _bypass_reconcile_grace "$repo" "$state"

  python3 - "$active_path" "$_SLEEPER_PID" "$fake_birth" "$log_rel" <<'PY'
import sys, yaml
path, pid, birth, log_path = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
doc = {"sessions": [{
    "task_id": "FRESH-VETO",
    "session_id": "s4",
    "started_at": "2020-01-01T00:00:00+00:00",
    "phase": "build",
    "pid": pid,
    "pid_birth": birth,
    "protocol_version": 2,
    "backend": "terminal",
    "log_path": log_path,
    "last_pulse_at": "2020-01-01T00:00:00+00:00",
    "stale": False,
}]}
with open(path, "w") as fh:
    yaml.safe_dump(doc, fh)
PY

  LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$SUPERVISE_SH" --json >/dev/null 2>&1 || { fail "Test 4: poll 1 exited nonzero"; _stop_sleeper; return; }
  local out2
  out2="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$SUPERVISE_SH" --json 2>/dev/null)" || { fail "Test 4: poll 2 exited nonzero"; _stop_sleeper; return; }

  local dead2 still
  dead2="$(printf -- '%s' "$out2" | json_get "any(x['task_id']=='FRESH-VETO' for x in d.get('dead', []))")"
  still="$(_row_present "$active_path" "FRESH-VETO")"
  if [[ "$dead2" == False && "$still" == True ]]; then
    pass "Test 4: birth mismatch + fresh stream mtime -> freshness veto suppresses escalation, row kept"
  else
    fail "Test 4: dead=$dead2 still_present=$still (a fresh stream must outrank the pid heuristic)"
  fi
  _stop_sleeper
}

test_1_live_lane_old_writer_form_reported_alive
test_2_dead_lane_still_dead
test_3_pid_reuse_still_caught
test_4_freshness_veto_suppresses_escalation

echo
log "==================================================================="
log "RESULTS: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  for e in "${ERRORS[@]}"; do log "$e"; done
  exit 1
fi
exit 0
