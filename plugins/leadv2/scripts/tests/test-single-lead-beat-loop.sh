#!/usr/bin/env bash
# tests/test-single-lead-beat-loop.sh — MON-PULSE-01 part 2: single-lead pulse
# beat default-on.
#
# Locks leadv2-single-lead-beat-loop.sh (armed by leadv2-dispatch-code.sh at
# the first worker_spawned):
#
#   B1  kill-switch: LEADV2_PULSE_MODE=0 (and LEADV2_SINGLE_LEAD_BEAT=0) is a
#       no-op — nothing armed, no beat driven.
#   B2  beat drives while >=1 lane is live: with a live lane in the (fake)
#       active-lane status the beat bin is invoked; the loop keeps running.
#   B3  not armed twice: a second invocation while the first loop holds the
#       pidfile is an immediate no-op (beat count does not grow).
#   B4  stops when no lanes remain: the live count drops to a REAL zero and
#       stays there -> after ZERO_MAX consecutive zero passes the loop exits
#       and removes its pidfile (re-arm is possible afterwards).
#   B5  a TRANSIENT zero does not stop the loop (fix-round H3): the board
#       reads empty for a couple of passes, then a lane is live again — the
#       loop must still be alive and beating (the pre-fix code exited on the
#       first zero pass).
#   B6  running_stale counts as live (fix-round H3): a lane whose heartbeat
#       verdict is `running_stale` keeps the beat running.
#   B7  per-root pidfile (fix-round 2 H3): two project roots sharing ONE
#       pidfile dir (the production shape — the state root is shared by the
#       main checkout and every worktree) each arm their OWN loop; the
#       pre-fix repo-global pidfile name made root B's arming a no-op against
#       root A's live pid, so B never got a beat.
#   B8  reader errors never stop the beat (fix-round 3 H-2): a heartbeat
#       error OBJECT (registry unreadable) parses as UNKNOWN — 5+
#       consecutive reader-error passes leave the loop alive and beating;
#       the pre-fix code counted them toward UNKNOWN_MAX=3 and stopped the
#       beat with no re-arm.
#
# Hermetic: fake lane-heartbeat bin (LEADV2_LANE_HEARTBEAT_BIN), fake beat bin
# (LEADV2_PULSE_BEAT_BIN) recording invocations to a log, scratch pidfile,
# interval 1s. No network, no real control-plane state.
# Run: bash scripts/tests/test-single-lead-beat-loop.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
LOOP="$SCRIPT_DIR/leadv2-single-lead-beat-loop.sh"

PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d /tmp/leadv2-beat-loop-XXXXXX)"
cleanup() {
  local p q
  for p in "${LOOP_PID:-}" "${LOOP_A:-}" "${LOOP_B:-}"; do
    [[ -n "$p" ]] && kill "$p" 2>/dev/null || true
  done
  # fix-round 3 H-1: kill the pidfile-owning loops too — $! alone can be a
  # dead wrapper while the real loop (owner of the pid) runs on as an orphan.
  for p in "$PID_FILE" "${PID_DIR2:-}"/.single-lead-beat-loop-*.pid; do
    [[ -f "$p" ]] || continue
    q="$(cat "$p" 2>/dev/null | tr -d ' ')"
    [[ "$q" =~ ^[0-9]+$ ]] && kill "$q" 2>/dev/null || true
  done
  rm -rf "$TMP"
}
trap cleanup EXIT

REPO="$TMP/repo"
mkdir -p "$REPO"
PID_FILE="$TMP/beat-loop.pid"
BEATS="$TMP/beats.log"
HB_STATE="$TMP/hb-state.json"   # what the fake heartbeat answers with

# fake lane-heartbeat: `status --all --json` -> the JSON in $HB_STATE
cat > "$TMP/fake-hb.sh" <<'EOF'
#!/usr/bin/env bash
# fake leadv2-lane-heartbeat.sh — prints the JSON staged by the test
cat "${FAKE_HB_STATE:?}" 2>/dev/null || echo '[]'
EOF
chmod +x "$TMP/fake-hb.sh"

# fake pulse-beat: records one line per invocation
cat > "$TMP/fake-beat.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$(date +%s)" >> "${FAKE_BEATS_LOG:?}"
exit 0
EOF
chmod +x "$TMP/fake-beat.sh"

run_loop() {  # extra env via caller
  # fix-round 3 H-1: exec so `run_loop &` makes $! the LOOP's own pid — the
  # pre-fix wrapper subshell meant kill $LOOP_PID killed the wrapper while
  # the pidfile-owning grandchild loop ran on as an orphan (flaky B5/B6).
  LEADV2_PROJECT_ROOT="$REPO" \
  LEADV2_SINGLE_LEAD_BEAT_LOOP_PID="$PID_FILE" \
  LEADV2_SINGLE_LEAD_BEAT_LOOP_S=1 \
  LEADV2_SINGLE_LEAD_BEAT_LOOP_MAX_S=30 \
  LEADV2_LANE_HEARTBEAT_BIN="$TMP/fake-hb.sh" \
  LEADV2_PULSE_BEAT_BIN="$TMP/fake-beat.sh" \
  FAKE_HB_STATE="$HB_STATE" FAKE_BEATS_LOG="$BEATS" \
    exec bash "$LOOP" "$@" >/dev/null 2>&1
}

beats_n() {
  if [[ -f "$BEATS" ]]; then wc -l < "$BEATS" | tr -d ' '; else printf '0'; fi
}
pidfile_alive_loop() {  # rc0 iff the pid in the pidfile is a live process
  [[ -f "$PID_FILE" ]] || return 1
  local p; p="$(cat "$PID_FILE" 2>/dev/null | tr -d ' ')"
  [[ "$p" =~ ^[0-9]+$ ]] && kill -0 "$p" 2>/dev/null
}
wait_exit() {  # <pid> <max_s> -> rc0 if the process exited in time
  local pid="$1" max="$2" i
  for ((i = 0; i < max * 10; i++)); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.1
  done
  kill -0 "$pid" 2>/dev/null && return 1
  return 0
}
wait_gone() {  # <max_s> — wait until the pidfile's process exits
  local max="$1" i p
  for ((i = 0; i < max * 10; i++)); do
    pidfile_alive_loop || { [[ -f "$PID_FILE" ]] || return 0; }
    sleep 0.1
  done
  return 1
}

# ── B1: kill-switch is a no-op ───────────────────────────────────────────────
printf '[{"task":"dispatch-x","status":"running"}]' > "$HB_STATE"
LEADV2_PROJECT_ROOT="$REPO" \
LEADV2_SINGLE_LEAD_BEAT_LOOP_PID="$PID_FILE" \
LEADV2_PULSE_MODE=0 \
LEADV2_LANE_HEARTBEAT_BIN="$TMP/fake-hb.sh" \
LEADV2_PULSE_BEAT_BIN="$TMP/fake-beat.sh" \
FAKE_HB_STATE="$HB_STATE" FAKE_BEATS_LOG="$BEATS" \
  bash "$LOOP" >/dev/null 2>&1
rc=$?
LEADV2_PROJECT_ROOT="$REPO" \
LEADV2_SINGLE_LEAD_BEAT_LOOP_PID="$PID_FILE" \
LEADV2_SINGLE_LEAD_BEAT=0 \
LEADV2_LANE_HEARTBEAT_BIN="$TMP/fake-hb.sh" \
LEADV2_PULSE_BEAT_BIN="$TMP/fake-beat.sh" \
FAKE_HB_STATE="$HB_STATE" FAKE_BEATS_LOG="$BEATS" \
  bash "$LOOP" >/dev/null 2>&1
rc2=$?
if [[ $rc -eq 0 && $rc2 -eq 0 && ! -f "$PID_FILE" && "$(beats_n)" == "0" ]]; then
  ok "B1 kill-switch: LEADV2_PULSE_MODE=0 / LEADV2_SINGLE_LEAD_BEAT=0 -> no-op, nothing armed"
else
  bad "B1 kill-switch: rc=$rc/$rc2 pidfile=$([[ -f $PID_FILE ]] && echo yes || echo no) beats=$(beats_n)"
fi

# ── B2 + B3: beat drives while a lane is live; second arm is a no-op ─────────
printf '[{"task":"dispatch-x","status":"running"}]' > "$HB_STATE"
run_loop &
LOOP_PID=$!
sleep 2.5
b_after_first="$(beats_n)"
if [[ "$b_after_first" -ge 1 ]] && pidfile_alive_loop; then
  ok "B2 beat driven: ${b_after_first} beat(s) while 1 lane live, loop still running"
else
  bad "B2 beat driven: beats=$(beats_n) loop_alive=$(pidfile_alive_loop && echo yes || echo no)"
fi
# second arm attempt while the first holds the pidfile: must exit fast,
# leave the FIRST loop's pid in place (it keeps beating at its own rate —
# the count is not the signal, pid ownership is)
first_pid="$(cat "$PID_FILE" 2>/dev/null | tr -d ' ')"
run_loop &
SECOND=$!
if wait_exit "$SECOND" 3 && [[ "$(cat "$PID_FILE" 2>/dev/null | tr -d ' ')" == "$first_pid" ]] \
   && kill -0 "$first_pid" 2>/dev/null; then
  ok "B3 not armed twice: second invocation exited immediately, pidfile still owns pid ${first_pid}"
else
  bad "B3 not armed twice: second invocation hung or stole the pidfile"
  kill "$SECOND" 2>/dev/null || true
fi

# ── B4: stops when no lanes remain (ZERO_MAX consecutive real zeros) ─────────
printf '[]' > "$HB_STATE"   # REAL zero: no live lanes, and it stays zero
if wait_gone 10 && [[ ! -f "$PID_FILE" ]]; then
  ok "B4 stops on empty board: loop exited after consecutive zeros, pidfile removed"
else
  bad "B4 stops on empty board: loop still alive or pidfile left behind"
fi
kill "$LOOP_PID" 2>/dev/null || true
LOOP_PID=""

# re-arm is possible after the stop (pidfile was cleaned, not leaked)
printf '[{"task":"dispatch-y","status":"running"}]' > "$HB_STATE"
run_loop &
LOOP_PID=$!
sleep 1.5
if pidfile_alive_loop; then
  ok "B4b re-arm after stop works (pidfile clean, loop re-armed)"
else
  bad "B4b re-arm after stop failed"
fi
kill "$LOOP_PID" 2>/dev/null || true
# TERM lands while the loop is inside `sleep 1`; bash defers the trap (and the
# pidfile cleanup) until the sleep exits — wait for it or the next arm no-ops
# against the dying pid and every later assertion races a dead pidfile.
# fix-round 3 H-1: FATAL — with exec, $LOOP_PID IS the loop, so a hang here is
# an orphaned beat loop on the host, never something to || true away.
wait_gone 5 || bad "B4b teardown: TERM'd loop pid did not exit within 5s (orphaned beat loop)"
LOOP_PID=""

# ── B5: a transient zero does not stop the loop (fix-round H3) ───────────────
# Dedicated loop with ZERO_MAX pinned high (5): the board reads empty for ~2-3
# passes, then a lane is live again. The pre-fix code exited on the FIRST zero
# pass; the fix requires ZERO_MAX consecutive ones.
printf '[{"task":"dispatch-y2","status":"running"}]' > "$HB_STATE"
LEADV2_SINGLE_LEAD_BEAT_LOOP_ZERO_MAX=5 run_loop &
LOOP_PID=$!
sleep 1.5
b_before="$(beats_n)"
printf '[]' > "$HB_STATE"   # transient zero
sleep 2.5                    # >=2 zero passes — the pre-fix loop is dead here
printf '[{"task":"dispatch-z1","status":"running"}]' > "$HB_STATE"
sleep 1.5
if pidfile_alive_loop && [[ "$(beats_n)" -gt "$b_before" ]]; then
  ok "B5 transient zero: board-empty blip did not stop the beat (H3)"
else
  bad "B5 transient zero: loop died on a non-consecutive zero (H3)"
fi

# ── B6: running_stale counts as live (fix-round H3) ─────────────────────────
printf '[{"task":"dispatch-z2","status":"running_stale"}]' > "$HB_STATE"
b_before="$(beats_n)"
sleep 2.5
if pidfile_alive_loop && [[ "$(beats_n)" -gt "$b_before" ]]; then
  ok "B6 running_stale live: stale lane keeps the beat running (H3)"
else
  bad "B6 running_stale live: stale lane silenced the beat (H3)"
fi
kill "$LOOP_PID" 2>/dev/null || true
LOOP_PID=""

# ── B7: per-root pidfile — parallel roots each get their own beat (H3) ──────
PID_DIR2="$TMP/shared-pid-dir"   # the production shape: ONE shared state root
mkdir -p "$PID_DIR2"
REPO_A="$TMP/repo-a"; REPO_B="$TMP/repo-b"
mkdir -p "$REPO_A" "$REPO_B"
arm_root() {  # <root> — arm the loop for that root against the shared pid dir
  # fix-round 3 H-1: exec — see run_loop
  LEADV2_PROJECT_ROOT="$1" \
  LEADV2_SINGLE_LEAD_BEAT_LOOP_PID_DIR="$PID_DIR2" \
  LEADV2_SINGLE_LEAD_BEAT_LOOP_S=1 \
  LEADV2_SINGLE_LEAD_BEAT_LOOP_MAX_S=30 \
  LEADV2_LANE_HEARTBEAT_BIN="$TMP/fake-hb.sh" \
  LEADV2_PULSE_BEAT_BIN="$TMP/fake-beat.sh" \
  FAKE_HB_STATE="$HB_STATE" FAKE_BEATS_LOG="$BEATS" \
    exec bash "$LOOP" >/dev/null 2>&1
}
printf '[{"task":"dispatch-a1","status":"running"}]' > "$HB_STATE"
arm_root "$REPO_A" &
LOOP_A=$!
sleep 1.5
printf '[{"task":"dispatch-b1","status":"running"}]' > "$HB_STATE"
arm_root "$REPO_B" &
LOOP_B=$!
sleep 2
_n_pidfiles="$(find "$PID_DIR2" -name '.single-lead-beat-loop-*.pid' | wc -l | tr -d ' ')"
if kill -0 "$LOOP_A" 2>/dev/null && kill -0 "$LOOP_B" 2>/dev/null \
   && [[ "$_n_pidfiles" -eq 2 ]]; then
  ok "B7 per-root pidfile: both roots armed their own loop ($_n_pidfiles pidfiles, shared dir)"
else
  bad "B7 per-root pidfile: a=$(kill -0 "$LOOP_A" 2>/dev/null && echo alive || echo dead) b=$(kill -0 "$LOOP_B" 2>/dev/null && echo alive || echo dead) pidfiles=$_n_pidfiles"
fi
kill "$LOOP_A" 2>/dev/null || true
kill "$LOOP_B" 2>/dev/null || true
sleep 1.5   # let the traps clean the pidfiles
LOOP_A=""; LOOP_B=""

# ── B8: reader errors never stop the beat (fix-round 3 H-2) ─────────────────
# leadv2-lane-heartbeat.sh can emit an ERROR OBJECT (registry unreadable),
# which the loop parses as UNKNOWN. 5+ consecutive reader-error passes must
# leave the loop alive AND still beating; the pre-fix code counted them toward
# UNKNOWN_MAX=3 and permanently stopped the beat with no re-arm — silent
# founder blindness, the exact failure MON-PULSE-01 exists to kill.
printf '[{"task":"dispatch-r1","status":"running"}]' > "$HB_STATE"
run_loop &
LOOP_PID=$!
sleep 1.5
b_before="$(beats_n)"
printf '{"error":"registry unreadable","status":"error"}' > "$HB_STATE"   # reader-error object
sleep 7   # >=5 consecutive UNKNOWN passes at 1s interval — pre-fix dead at pass 3
if pidfile_alive_loop && kill -0 "$LOOP_PID" 2>/dev/null && [[ "$(beats_n)" -gt "$b_before" ]]; then
  ok "B8 reader errors: 5+ unknown passes, loop still alive and beating (H-2)"
else
  bad "B8 reader errors: loop stopped or went silent on reader errors (H-2): alive=$(pidfile_alive_loop && echo yes || echo no) beats=$(beats_n) before=$b_before"
fi
kill "$LOOP_PID" 2>/dev/null || true
wait_gone 5 || bad "B8 teardown: TERM'd loop pid did not exit within 5s (orphaned beat loop)"
LOOP_PID=""

printf 'test-single-lead-beat-loop: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
