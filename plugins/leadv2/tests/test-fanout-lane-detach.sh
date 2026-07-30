#!/usr/bin/env bash
# tests/test-fanout-lane-detach.sh — regression test for
# P0-FANOUT-EXIT-KILLS-ITS-OWN-LANES-01.
#
# Part A proves the falsifiable core of the fix directly: a child spawned via
# leadv2-fanout.sh's new _leadv2_new_session_exec helper survives a
# group-directed SIGTERM aimed at its caller's process group -- exactly what
# the harness Bash tool does when a 600s command ceiling is hit. It also
# reproduces the OLD (pre-fix) fallback pattern inline (verbatim from
# leadv2-fanout.sh's launch_headless nohup-without-setsid branch) and shows
# THAT one dies with the group, so this test would fail against the old
# mechanism and passes against the new one.
#
# Part B exercises the real leadv2-fanout-lane-launcher.sh end to end: a
# stubbed dispatch-code.sh (success path, worker survives the launcher's own
# exit) and a crash path (dispatch-code.sh fails -> a `dead` terminal row
# lands in the ledger and the claim/reservation are released, never silently
# dropped).
#
# Usage: bash tests/test-fanout-lane-detach.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/../scripts"
FANOUT_SH="${SCRIPTS_DIR}/leadv2-fanout.sh"
LAUNCHER_SH="${SCRIPTS_DIR}/leadv2-fanout-lane-launcher.sh"

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$(( PASS + 1 )); }
fail() { echo "FAIL: $1"; FAIL=$(( FAIL + 1 )); }

TMPD="$(mktemp -d)"
cleanup() { rm -rf "$TMPD" 2>/dev/null || true; }
trap cleanup EXIT

# ── Part A: process-group survival ──────────────────────────────────────────
# Extract just the new helper (no top-level fanout.sh execution: classify,
# drift-guard, and the launch loop never run) so this exercises the REAL
# production function, not a reimplementation.
FUNCS_FILE="${TMPD}/funcs.sh"
sed -n '/^_leadv2_new_session_exec() {/,/^}$/p' "$FANOUT_SH" > "$FUNCS_FILE"
if [[ ! -s "$FUNCS_FILE" ]]; then
  fail "could not extract _leadv2_new_session_exec from leadv2-fanout.sh -- has it been renamed/removed?"
else
  funcs_lines="$(wc -l < "$FUNCS_FILE")"
  pass "extracted _leadv2_new_session_exec from leadv2-fanout.sh (${funcs_lines} lines)"
fi

# _test_new_session_bg <cmd...> — background <cmd...> into a NEW OS session
# (pid == pgid), setting global _TNS_PID. This test's own machine has no
# `setsid` binary either (the exact condition the fix's fallback exists
# for) -- reuse the same python3-setsid technique the production fix uses,
# purely to give this test an isolated, killable process group to represent
# "the harness's own group" (Part A) or to launch a lane launcher the same
# way fanout would (Part B). Not a test of the shim itself -- that already
# happens inside _leadv2_new_session_exec in "fixed" mode below.
_test_new_session_bg() {
  ( exec python3 -c 'import os,sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' "$@" ) &
  _TNS_PID=$!
}

# _test_new_session_bg_redir <logfile> <cmd...> — same, but stdout+stderr of
# <cmd...> append to <logfile> (stdin /dev/null), matching how fanout itself
# invokes _leadv2_new_session_exec.
_test_new_session_bg_redir() {
  local logf="$1"; shift
  ( exec python3 -c 'import os,sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \
      "$@" </dev/null >>"$logf" 2>&1 ) &
  _TNS_PID=$!
}

run_group_survival_test() {
  # $1 = "fixed" (use _leadv2_new_session_exec) | "old" (verbatim pre-fix
  #      fallback: plain nohup, no setsid -- launch_headless's else-branch)
  local mode="$1" outf="${TMPD}/${1}.out" logf="${TMPD}/${1}.log"
  : > "$outf"
  # Run the "harness" itself as its own new session (setsid) so we have an
  # isolated, controllable process group to kill from outside -- standing in
  # for the real harness Bash tool's own group.
  if [[ "$mode" == "fixed" ]]; then
    _test_new_session_bg bash -c "
      source '$FUNCS_FILE'
      log_error() { printf '[test] %s\n' \"\$*\" >&2; }
      _leadv2_new_session_exec '$logf' sleep 20 > '$outf'
    "
  else
    # Verbatim reproduction of leadv2-fanout.sh's launch_headless() else
    # branch (no setsid binary path) -- 'nohup + trailing & still detaches'
    # is FANOUT-MACOS-LAUNCHER-01's disproven claim.
    _test_new_session_bg bash -c "
      ( exec nohup sleep 20 </dev/null >>'$logf' 2>&1 ) &
      pid=\$!
      printf '%s false\n' \"\$pid\" > '$outf'
    "
  fi
  local harness_pid=$_TNS_PID

  local waited=0
  while [[ ! -s "$outf" && "$waited" -lt 50 ]]; do sleep 0.1; waited=$(( waited + 1 )); done
  local spawned_pid used
  read -r spawned_pid used < "$outf"
  sleep 0.3

  if [[ -z "$spawned_pid" ]]; then
    fail "${mode}: spawner never reported a pid"
    return
  fi

  # This is the exact action the harness performs on a timed-out Bash tool
  # call: reap the WHOLE process group.
  kill -TERM -- "-${harness_pid}" 2>/dev/null || true
  sleep 1

  if kill -0 "$spawned_pid" 2>/dev/null; then
    if [[ "$mode" == "fixed" ]]; then
      pass "fixed: spawned child (pid=${spawned_pid}, used_new_session=${used}) SURVIVES harness-group SIGTERM"
    else
      fail "old: spawned child (pid=${spawned_pid}) survived harness-group SIGTERM -- expected it to die (test setup is wrong, this contradicts the documented bug)"
    fi
    kill -TERM "$spawned_pid" 2>/dev/null || true
  else
    if [[ "$mode" == "fixed" ]]; then
      fail "fixed: spawned child (pid=${spawned_pid}) died with the harness group -- P0-FANOUT-EXIT-KILLS-ITS-OWN-LANES-01 NOT fixed"
    else
      pass "old (pre-fix pattern): spawned child died with the harness group, reproducing the original bug"
    fi
  fi
}

run_group_survival_test fixed
run_group_survival_test old

# ── Part B: real leadv2-fanout-lane-launcher.sh, success + crash paths ─────
PROJECT_ROOT="${TMPD}/repo"
mkdir -p "$PROJECT_ROOT/docs/leadv2" "$PROJECT_ROOT/docs/handoff"
( cd "$PROJECT_ROOT" && git init -q && git config user.email t@t.com && git config user.name t && git commit -q --allow-empty -m init )
cat > "$PROJECT_ROOT/docs/tasks.yaml" <<'EOF'
total_open: 0
tasks: []
EOF

LEDGER_FILE="${TMPD}/terminal-ledger.jsonl"

MISSION_FILE="${TMPD}/mission.txt"
printf 'Task test-lane-1: do a thing\n' > "$MISSION_FILE"

# Stub dispatch-code.sh: success path -- sleeps briefly (proving the launcher
# tolerates a slow synchronous call once detached), then forks a fake worker
# that keeps appending to STREAM_FILE, then reports success on stdout in the
# exact format launch_via_dispatch_code/the launcher parse.
FAKE_DC_OK="${TMPD}/fake-dispatch-ok.sh"
STREAM_FILE="${TMPD}/stream.jsonl"
cat > "$FAKE_DC_OK" <<EOF
#!/usr/bin/env bash
sleep 1
# Redirect this background loop's own stdio away from whatever fds this
# script inherited (the launcher captures our stdout via a command
# substitution -- a background child that keeps that pipe's write end open
# would hang the launcher's \$(...) until the loop finishes, exactly the
# real-world fd-inheritance trap dispatch-code.sh's glm arm guards against
# with '9>&-'; our own stdout redirect below is the equivalent guard here).
( for i in \$(seq 1 100); do date -u +%Y-%m-%dT%H:%M:%SZ >> "${STREAM_FILE}"; sleep 0.2; done ) \
  </dev/null >/dev/null 2>&1 &
disown
printf 'worker_spawned by=router model=sonnet task=deadbeef1 handle=PID=%s attempt=att-ok\n' "\$!"
exit 0
EOF
chmod +x "$FAKE_DC_OK"

FAKE_DC_CRASH="${TMPD}/fake-dispatch-crash.sh"
cat > "$FAKE_DC_CRASH" <<'EOF'
#!/usr/bin/env bash
echo "simulated crash" >&2
exit 137
EOF
chmod +x "$FAKE_DC_CRASH"

SIG_DIR_OK="${PROJECT_ROOT}/docs/handoff/fanout-lane-test-lane-1"

_test_new_session_bg_redir "${TMPD}/launcher-ok.log" \
  env LEADV2_PROJECT_ROOT="$PROJECT_ROOT" PROJECT_ROOT="$PROJECT_ROOT" \
    LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$LEDGER_FILE" \
  bash "$LAUNCHER_SH" \
    --task-id test-lane-1 --class Light --mission-file "$MISSION_FILE" \
    --project-root "$PROJECT_ROOT" --sig-dir "$SIG_DIR_OK" \
    --dispatch-bin "$FAKE_DC_OK" --lead-model sonnet --lead-effort medium \
    --provider claude
LAUNCHER_OK_PID=$_TNS_PID

# Ack: launcher.pid should appear almost immediately (well before
# dispatch-code.sh's 1s sleep even returns) -- proving fanout's short wait
# would have already moved on to the next lane by the time this appears.
waited=0
while [[ ! -f "${SIG_DIR_OK}/launcher.pid" && "$waited" -lt 50 ]]; do sleep 0.1; waited=$(( waited + 1 )); done
if [[ -f "${SIG_DIR_OK}/launcher.pid" ]]; then
  ack_pid="$(cat "${SIG_DIR_OK}/launcher.pid")"
  if kill -0 "$ack_pid" 2>/dev/null; then
    pass "launcher acks (pid file present, live pid) within ${waited}00ms -- well under a caller's ack-wait window"
  else
    fail "launcher.pid present but not a live pid"
  fi
else
  fail "launcher never wrote launcher.pid (no ack signal) within 5s"
fi

wait "$LAUNCHER_OK_PID" 2>/dev/null
launcher_ok_rc=$?
if [[ "$launcher_ok_rc" -eq 0 ]]; then
  pass "launcher exits 0 on dispatch-code.sh success"
else
  fail "launcher exited rc=${launcher_ok_rc} on the success path (expected 0): $(cat "${TMPD}/launcher-ok.log")"
fi

# Worker must still be alive and its stream still advancing AFTER the
# launcher process itself has exited -- this is the mission's core liveness
# assertion, one level down from fanout (launcher -> worker).
mtime1="$(stat -f '%m' "$STREAM_FILE" 2>/dev/null || stat -c '%Y' "$STREAM_FILE" 2>/dev/null)"
sleep 2
mtime2="$(stat -f '%m' "$STREAM_FILE" 2>/dev/null || stat -c '%Y' "$STREAM_FILE" 2>/dev/null)"
if [[ -n "$mtime1" && -n "$mtime2" && "$mtime2" -gt "$mtime1" ]]; then
  pass "fake worker's stream is still advancing after the launcher process exited"
else
  fail "fake worker's stream stopped advancing after the launcher exited (mtime1=${mtime1} mtime2=${mtime2})"
fi

ACTIVE_YAML="${PROJECT_ROOT}/docs/leadv2/active.yaml"
if [[ -f "$ACTIVE_YAML" ]] && grep -q 'task_id: test-lane-1' "$ACTIVE_YAML" 2>/dev/null; then
  pass "active.yaml carries a finalized row for test-lane-1"
else
  fail "active.yaml has no row for test-lane-1 after a successful launch"
fi

# ── Crash path: dispatch-code.sh fails -> dead terminal row, no silent drop ─
SIG_DIR_CRASH="${PROJECT_ROOT}/docs/handoff/fanout-lane-test-lane-2"
env LEADV2_PROJECT_ROOT="$PROJECT_ROOT" PROJECT_ROOT="$PROJECT_ROOT" \
    LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$LEDGER_FILE" \
  bash "$LAUNCHER_SH" \
    --task-id test-lane-2 --class Standard --mission-file "$MISSION_FILE" \
    --project-root "$PROJECT_ROOT" --sig-dir "$SIG_DIR_CRASH" \
    --dispatch-bin "$FAKE_DC_CRASH" --lead-model sonnet --lead-effort medium \
    --provider claude >"${TMPD}/launcher-crash.log" 2>&1
launcher_crash_rc=$?

if [[ "$launcher_crash_rc" -ne 0 ]]; then
  pass "launcher exits non-zero on dispatch-code.sh crash (rc=${launcher_crash_rc})"
else
  fail "launcher exited 0 despite dispatch-code.sh crashing"
fi

if [[ -f "$LEDGER_FILE" ]] && grep -q '"task_sig":"fanout-test-lane-2"' "$LEDGER_FILE" \
     && grep -q '"terminal":"dead"' "$LEDGER_FILE"; then
  pass "a 'dead' terminal row was written for the crashed lane -- not silently dropped"
else
  fail "no 'dead' terminal row found in the ledger for the crashed lane: $(cat "$LEDGER_FILE" 2>/dev/null)"
fi

if grep -q 'task_id: test-lane-2' "$ACTIVE_YAML" 2>/dev/null; then
  fail "active.yaml still carries a row for the crashed lane test-lane-2 (should have been unregistered)"
else
  pass "active.yaml has no lingering row for the crashed lane"
fi

# ── Part C: fanout's own ack-wait bounds every lane, even a stuck launcher ──
# Exercises _fanout_launch_lane_detached itself (extracted, not
# reimplemented) with LEADV2_FANOUT_LANE_LAUNCHER_BIN pointed at a stub that
# never acks (never writes launcher.pid) -- this is Assert B from the
# design's acceptance section: fanout must not block past the ack timeout
# for ANY lane, and every planned lane ends up with a terminal record, not
# silence.
DETACH_FUNCS_FILE="${TMPD}/detach-funcs.sh"
{
  sed -n '/^_fanout_kill_child() {/,/^}$/p' "$FANOUT_SH"
  sed -n '/^_leadv2_new_session_exec() {/,/^}$/p' "$FANOUT_SH"
  sed -n '/^_fanout_write_lane_terminal() {/,/^}$/p' "$FANOUT_SH"
  sed -n '/^_fanout_launch_lane_detached() {/,/^}$/p' "$FANOUT_SH"
} > "$DETACH_FUNCS_FILE"
if [[ ! -s "$DETACH_FUNCS_FILE" ]]; then
  fail "could not extract _fanout_launch_lane_detached (and its helpers) from leadv2-fanout.sh"
else
  pass "extracted _fanout_launch_lane_detached + helpers from leadv2-fanout.sh"
fi

STUCK_LAUNCHER="${TMPD}/stuck-launcher.sh"
cat > "$STUCK_LAUNCHER" <<'EOF'
#!/usr/bin/env bash
# Never writes launcher.pid -- simulates a launcher that hangs before ack
# (e.g. a lane launcher script that itself failed to start).
sleep 60
EOF
chmod +x "$STUCK_LAUNCHER"

ACK_TIMEOUT_LEDGER="${TMPD}/ack-timeout-ledger.jsonl"
HARNESS_C="${TMPD}/harness-c.sh"
cat > "$HARNESS_C" <<HARNESS
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="${SCRIPTS_DIR}"
PROJECT_ROOT="${PROJECT_ROOT}"
log() { printf -- '[fanout] %s\n' "\$*" >&2; }
log_error() { log "ERROR: \$*"; }
source "${SCRIPTS_DIR}/leadv2-active-registry.sh"
source "${SCRIPTS_DIR}/leadv2-tasks-lib.sh"
source "$DETACH_FUNCS_FILE"
export LEADV2_PROJECT_ROOT="${PROJECT_ROOT}"
export LEADV2_FANOUT_LANE_ACK_TIMEOUT_SEC=3
export LEADV2_FANOUT_LANE_LAUNCHER_BIN="$STUCK_LAUNCHER"
export LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$ACK_TIMEOUT_LEDGER"
t0=\$(date +%s)
_fanout_launch_lane_detached "test-lane-timeout" "Light" "sonnet" "medium" "" "" "claude" "" "" "label" \\
  "mission text" "" "" "0" "/nonexistent-dispatch-bin"
t1=\$(date +%s)
echo "ELAPSED=\$(( t1 - t0 ))"
HARNESS
chmod +x "$HARNESS_C"

harness_c_out="$(timeout 30 bash "$HARNESS_C" 2>&1)"
elapsed="$(printf '%s\n' "$harness_c_out" | sed -n 's/^ELAPSED=\([0-9]*\)$/\1/p')"

if [[ -n "$elapsed" && "$elapsed" -le 10 ]]; then
  pass "fanout's lane-detach call returns in ${elapsed}s despite a stuck (never-acking) launcher -- bounded by the ack timeout, not the 840s dispatch-code.sh ceiling"
else
  fail "fanout's lane-detach call did not return promptly for a stuck launcher (output: ${harness_c_out})"
fi

if [[ -f "$ACK_TIMEOUT_LEDGER" ]] && grep -q '"task_sig":"fanout-test-lane-timeout"' "$ACK_TIMEOUT_LEDGER" \
     && grep -q '"cause":"launcher_handoff_timeout"' "$ACK_TIMEOUT_LEDGER"; then
  pass "a 'dead cause=launcher_handoff_timeout' terminal row was written for the stuck lane -- never silently dropped"
else
  fail "no launcher_handoff_timeout terminal row found: $(cat "$ACK_TIMEOUT_LEDGER" 2>/dev/null)"
fi

sleep 0.5
if pgrep -f "$(basename "$STUCK_LAUNCHER")" >/dev/null 2>&1; then
  fail "the stuck launcher process is still running after the ack-timeout kill"
else
  pass "the stuck launcher process was killed after the ack timeout"
fi

echo "----"
echo "PASS=${PASS} FAIL=${FAIL}"
[[ "$FAIL" -eq 0 ]]
