#!/usr/bin/env bash
# tests/test-beat-loop-orphans.sh — BEAT-LOOP-ORPHANS-01
#
# Locks both orphan mechanisms:
#
#   A   hook gate (mechanism 1): leadv2-single-lead-beat.sh invoked with
#       WORKER evidence (LEADV2_WORKER_ARM=1 or transcript under docs/handoff
#       or *-runs/) exits 0 silently — no beat triggered, no session-stamp
#       state touched. With LEAD evidence it arms (beat triggered).
#   B   owner-pid belt (mechanism 2): a loop whose recorded owner pid DIES
#       exits within one iteration (1s cadence); with a live owner it keeps
#       running until its lifetime cap.
#   C   transcript-mtime belt (mechanism 2): a loop whose owner transcript is
#       older than LEADV2_LOOP_ORPHAN_MAX_MIN exits within one iteration.
#   D   lane-pulse-watch honours the same owner belt.
#   E   predicate unit table: every evidence shape classifies as documented.
#
# Mutation negative controls (GATE-PROVES-ITS-OWN-CONTROL style, run against
# COPIES in a throwaway skeleton so the real tree is never mutated):
#   NC1  predicate forced to always return `lead` -> case A-worker turns red
#        (the beat IS triggered for worker evidence).
#   NC2  owner-pid check neutered in the beat loop -> case B turns red (the
#        loop ignores its dead owner and keeps beating).
#
# Hermetic: every case runs against a skeleton plugin tree (copies of the
# real hook/lib/loop + stub state-path/pulse-beat/heartbeat seams), scratch
# state dir, 1s cadence. No network, no real control-plane state.
# Run: bash plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$TESTS_DIR/.." && pwd)"
PLUGIN_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"

PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d /tmp/leadv2-beat-loop-orphans-XXXXXX)"
cleanup() { rm -rf "$TMP" 2>/dev/null || true; }
trap cleanup EXIT

# ── skeleton builder ─────────────────────────────────────────────────────
# build_skeleton <dest> — copies the REAL files under test into a plugin
# skeleton with stubbed seams. Mutations (NC1/NC2) are applied to the copies
# only.
build_skeleton() {
  local dest="$1"
  mkdir -p "$dest/plugins/leadv2/hooks/lib" "$dest/plugins/leadv2/scripts" "$dest/state"
  cp "$PLUGIN_DIR/hooks/leadv2-single-lead-beat.sh" "$dest/plugins/leadv2/hooks/"
  cp "$PLUGIN_DIR/hooks/lib/leadv2-hook-session-kind.sh" "$dest/plugins/leadv2/hooks/lib/"
  cp "$SCRIPTS_DIR/leadv2-single-lead-beat-loop.sh" "$dest/plugins/leadv2/scripts/"
  cp "$SCRIPTS_DIR/leadv2-lane-pulse-watch.sh" "$dest/plugins/leadv2/scripts/"
  # state-path stub: root -> $dest/state, supervise-loop.log -> under it
  cat > "$dest/plugins/leadv2/scripts/leadv2-state-path.sh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *supervise-loop.log*) echo "${TEST_STATE_DIR}/supervise-loop.log" ;;
  *) echo "${TEST_STATE_DIR}" ;;
esac
STUB
  # pulse-beat sentinel: every invocation appends one line
  cat > "$dest/plugins/leadv2/scripts/leadv2-pulse-beat.sh" <<'STUB'
#!/usr/bin/env bash
printf 'beat %s\n' "$(date +%s)" >> "${TEST_STATE_DIR}/beats.log"
exit 0
STUB
  # heartbeat stub: one live lane -> the loop keeps beating on its own merit
  cat > "$dest/plugins/leadv2/scripts/leadv2-lane-heartbeat.sh" <<'STUB'
#!/usr/bin/env bash
printf '[{"status":"running"}]\n'
exit 0
STUB
  chmod +x "$dest/plugins/leadv2/scripts/"*.sh "$dest/plugins/leadv2/hooks/"*.sh
}

# run the hook once: run_hook <skeleton> <env A=B passed via env> <transcript>
run_hook() {  # <skeleton> <transcript_path>
  local skel="$1" tp="$2"
  local sid="testsess$$"
  LEADV2_SINGLE_LEAD_BEAT="${LEADV2_SINGLE_LEAD_BEAT_OVERRIDE:-1}" \
  TEST_STATE_DIR="$skel/state" \
  CLAUDE_PLUGIN_ROOT="$skel/plugins/leadv2" \
  bash "$skel/plugins/leadv2/hooks/leadv2-single-lead-beat.sh" <<EOF
{"hook_event_name":"UserPromptSubmit","session_id":"$sid","cwd":"$skel","transcript_path":"$tp"}
EOF
}

wait_gone() {  # <pidfile> <timeout_s> -> 0 if pidfile disappeared in time
  local f="$1" t="${2:-5}" i
  for i in $(seq 1 $(( t * 10 ))); do
    [[ ! -f "$f" ]] && return 0
    sleep 0.1
  done
  return 1
}

wait_file() {  # <file> <timeout_s> -> 0 if file appeared in time (the hook's
  # beat trigger is a disowned background job — its sentinel lands async)
  local f="$1" t="${2:-3}" i
  for i in $(seq 1 $(( t * 10 ))); do
    [[ -f "$f" ]] && return 0
    sleep 0.1
  done
  return 1
}

# ═══════════════════════════════ A. hook gate ════════════════════════════
SKEL_A="$TMP/skelA"
build_skeleton "$SKEL_A"

# A1 worker via launcher env marker: silent exit, nothing touched
out="$(LEADV2_WORKER_ARM=1 run_hook "$SKEL_A" "$TMP/anywhere.jsonl" 2>&1)"; rc=$?
if [[ $rc -eq 0 && ! -f "$SKEL_A/state/beats.log" && ! -f "$SKEL_A/state/.pulse-session.testsess$$" ]]; then
  ok "A1 worker (env marker): silent exit, no beat, no session stamp"
else
  bad "A1 worker (env marker): rc=$rc beats=$(cat "$SKEL_A/state/beats.log" 2>/dev/null | wc -l | tr -d ' ')"
fi

# A2 worker via transcript shape (docs/handoff): silent exit
out="$(run_hook "$SKEL_A" "$TMP/repo/docs/handoff/SOME-TASK/transcript-x.jsonl" 2>&1)"; rc=$?
if [[ $rc -eq 0 && ! -f "$SKEL_A/state/beats.log" ]]; then
  ok "A2 worker (docs/handoff transcript): silent exit, no beat"
else
  bad "A2 worker (docs/handoff transcript): rc=$rc beats=$(cat "$SKEL_A/state/beats.log" 2>/dev/null | wc -l | tr -d ' ')"
fi

# A3 worker via transcript shape (*-runs/): silent exit
out="$(run_hook "$SKEL_A" "$TMP/.claude/cache/glm-runs/260901-221700/x.jsonl" 2>&1)"; rc=$?
if [[ $rc -eq 0 && ! -f "$SKEL_A/state/beats.log" ]]; then
  ok "A3 worker (glm-runs transcript): silent exit, no beat"
else
  bad "A3 worker (glm-runs transcript): rc=$rc"
fi

# A4 lead evidence: arms (beat triggered) + owner transcript stamped
out="$(run_hook "$SKEL_A" "$TMP/lead-transcript.jsonl" 2>&1)"; rc=$?
if [[ $rc -eq 0 && -f "$SKEL_A/state/.beat-owner-transcript" ]] \
   && wait_file "$SKEL_A/state/beats.log" 3; then
  ok "A4 lead: beat triggered + owner transcript stamped"
else
  bad "A4 lead: rc=$rc beats=$(cat "$SKEL_A/state/beats.log" 2>/dev/null | wc -l | tr -d ' ') stamp=$([[ -f "$SKEL_A/state/.beat-owner-transcript" ]] && echo y || echo n)"
fi

# A5 unknown evidence (no transcript, no env): fail-open, journaled
out="$(run_hook "$SKEL_A" "" 2>&1)"; rc=$?
if [[ $rc -eq 0 && -f "$SKEL_A/state/loop-arm-journal.log" ]] \
   && grep -q "event=loop_armed_by_unknown_session loop=single-lead-beat-hook" "$SKEL_A/state/loop-arm-journal.log" 2>/dev/null; then
  ok "A5 unknown: fail-open arm journaled"
else
  bad "A5 unknown: rc=$rc journal=$(cat "$SKEL_A/state/loop-arm-journal.log" 2>/dev/null | head -1)"
fi

# ══════════════════ B/C. beat loop owner belts (mechanism 2) ═════════════
LOOP="$SKEL_A/plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh"

# B1 owner pid dies -> loop exits within one iteration
SKEL_B="$TMP/skelB"; build_skeleton "$SKEL_B"
sleep 30 &
OWNER_PID=$!
(
  LEADV2_LANE_HEARTBEAT_BIN="$SKEL_B/plugins/leadv2/scripts/leadv2-lane-heartbeat.sh" \
  LEADV2_PULSE_BEAT_BIN="$SKEL_B/plugins/leadv2/scripts/leadv2-pulse-beat.sh" \
  LEADV2_SINGLE_LEAD_BEAT_LOOP_S=1 LEADV2_SINGLE_LEAD_BEAT_LOOP_MAX_S=30 \
  LEADV2_SINGLE_LEAD_BEAT_LOOP_PID_DIR="$SKEL_B/state" TEST_STATE_DIR="$SKEL_B/state" \
  LEADV2_PROJECT_ROOT="$SKEL_B" LEADV2_LOOP_OWNER_PID="$OWNER_PID" \
    bash "$SKEL_B/plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh" \
    >"$SKEL_B/loop.out" 2>&1
) &
LOOP_PID=$!
sleep 1.2            # let the loop record the (still alive) owner
kill "$OWNER_PID" 2>/dev/null; wait "$OWNER_PID" 2>/dev/null
_pidfile_b="$SKEL_B/state/.single-lead-beat-loop"-"$(printf '%s' "$SKEL_B" | cksum | cut -d' ' -f1)".pid
if wait_gone "$_pidfile_b" 5; then
  ok "B1 owner pid died -> loop exited within one iteration"
else
  bad "B1 owner pid died but loop still running (pidfile present)"
fi
kill "$LOOP_PID" 2>/dev/null; wait "$LOOP_PID" 2>/dev/null

# C1 owner transcript stale -> loop exits within one iteration
SKEL_C="$TMP/skelC"; build_skeleton "$SKEL_C"
touch "$SKEL_C/stale-transcript.jsonl"
touch -t "$(date -v-10M +%Y%m%d%H%M 2>/dev/null || date -d '10 minutes ago' +%Y%m%d%H%M)" "$SKEL_C/stale-transcript.jsonl"
(
  LEADV2_LANE_HEARTBEAT_BIN="$SKEL_C/plugins/leadv2/scripts/leadv2-lane-heartbeat.sh" \
  LEADV2_PULSE_BEAT_BIN="$SKEL_C/plugins/leadv2/scripts/leadv2-pulse-beat.sh" \
  LEADV2_SINGLE_LEAD_BEAT_LOOP_S=1 LEADV2_SINGLE_LEAD_BEAT_LOOP_MAX_S=30 \
  LEADV2_LOOP_ORPHAN_MAX_MIN=5 \
  LEADV2_SINGLE_LEAD_BEAT_LOOP_PID_DIR="$SKEL_C/state" TEST_STATE_DIR="$SKEL_C/state" \
  LEADV2_PROJECT_ROOT="$SKEL_C" LEADV2_LOOP_OWNER_TRANSCRIPT="$SKEL_C/stale-transcript.jsonl" \
    bash "$SKEL_C/plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh" \
    >"$SKEL_C/loop.out" 2>&1
) &
LOOP_PID=$!
_pidfile_c="$SKEL_C/state/.single-lead-beat-loop"-"$(printf '%s' "$SKEL_C" | cksum | cut -d' ' -f1)".pid
# (the exited subshell is a zombie until waited, so kill -0 on LOOP_PID is
# meaningless here; and the loop exits on pass 1, faster than any pidfile
# observation — assert on the loop's own exit message, polled)
_c1=NO
for _i in 1 2 3 4 5 6 7 8 9 10; do
  grep -q "owner transcript stale" "$SKEL_C/loop.out" 2>/dev/null && { _c1=YES; break; }
  sleep 0.3
done
if [[ "$_c1" == "YES" ]]; then
  ok "C1 stale owner transcript -> loop exited within one iteration"
else
  bad "C1 stale transcript but loop still running (out: $(head -3 "$SKEL_C/loop.out" 2>/dev/null))"
fi
kill "$LOOP_PID" 2>/dev/null; wait "$LOOP_PID" 2>/dev/null

# D0 positive control for B1/C1: LIVE owner + FRESH transcript -> loop keeps
# beating until its lifetime cap (owner belts must not fire spuriously).
SKEL_D="$TMP/skelD"; build_skeleton "$SKEL_D"
sleep 60 &
LIVE_OWNER=$!
(
  LEADV2_LANE_HEARTBEAT_BIN="$SKEL_D/plugins/leadv2/scripts/leadv2-lane-heartbeat.sh" \
  LEADV2_PULSE_BEAT_BIN="$SKEL_D/plugins/leadv2/scripts/leadv2-pulse-beat.sh" \
  LEADV2_SINGLE_LEAD_BEAT_LOOP_S=1 LEADV2_SINGLE_LEAD_BEAT_LOOP_MAX_S=3 \
  LEADV2_SINGLE_LEAD_BEAT_LOOP_PID_DIR="$SKEL_D/state" TEST_STATE_DIR="$SKEL_D/state" \
  LEADV2_PROJECT_ROOT="$SKEL_D" LEADV2_LOOP_OWNER_PID="$LIVE_OWNER" \
    bash "$SKEL_D/plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh" \
    >"$SKEL_D/loop.out" 2>&1
) &
LOOP_PID=$!
sleep 2.2
_alive=YES
kill -0 "$LOOP_PID" 2>/dev/null || _alive=NO
beats="$(cat "$SKEL_D/state/beats.log" 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$_alive" == "YES" && "${beats:-0}" -ge 1 ]]; then
  ok "D0 live owner + fresh state: loop kept beating past one iteration (${beats} beats)"
else
  bad "D0 live owner: loop died early (alive=$_alive beats=${beats:-0})"
fi
wait "$LOOP_PID" 2>/dev/null
kill "$LIVE_OWNER" 2>/dev/null; wait "$LIVE_OWNER" 2>/dev/null

# ════════════════ D. lane-pulse-watch honours the owner belt ═════════════
SKEL_E="$TMP/skelE"; build_skeleton "$SKEL_E"
mkdir -p "$SKEL_E/state/lpw"
cat > "$SKEL_E/plugins/leadv2/scripts/leadv2-pulse.sh" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$SKEL_E/plugins/leadv2/scripts/leadv2-pulse.sh"
mkdir -p "$SKEL_E/lane/journal"
printf 'worker_spawned task=abc12345\n' > "$SKEL_E/lane/journal.md"
sleep 30 &
LPW_OWNER=$!
(
  LEADV2_LANE_PULSE_BIN="$SKEL_E/plugins/leadv2/scripts/leadv2-pulse.sh" \
  LEADV2_LANE_PULSE_WATCH_INTERVAL=1 LEADV2_LANE_PULSE_WATCH_TIMEOUT=30 \
  TEST_STATE_DIR="$SKEL_E/state" LEADV2_PROJECT_ROOT="$SKEL_E" \
  LEADV2_LOOP_OWNER_PID="$LPW_OWNER" \
    bash "$SKEL_E/plugins/leadv2/scripts/leadv2-lane-pulse-watch.sh" \
    --sig abc12345 --root "$SKEL_E" --journal "$SKEL_E/lane/journal.md" \
    --state-dir "$SKEL_E/state" >"$SKEL_E/lpw.out" 2>&1
) &
LOOP_PID=$!
sleep 1.2
kill "$LPW_OWNER" 2>/dev/null; wait "$LPW_OWNER" 2>/dev/null
if wait_gone "$SKEL_E/state/lane-pulse-watch/abc12345.pid" 5; then
  ok "D1 lane-pulse-watch: dead owner -> watcher exited"
else
  bad "D1 lane-pulse-watch: dead owner but watcher still running"
fi
kill "$LOOP_PID" 2>/dev/null; wait "$LOOP_PID" 2>/dev/null

# ═══════════════════════ E. predicate unit table ═════════════════════════
SKEL_F="$TMP/skelF"; build_skeleton "$SKEL_F"
LIB="$SKEL_F/plugins/leadv2/hooks/lib/leadv2-hook-session-kind.sh"
kind_of() {  # <transcript> [env via caller]
  bash -c "
    source '$LIB' >/dev/null 2>&1
    leadv2_hook_session_kind '$1'
  " 2>/dev/null
}
u_out="$(LEADV2_WORKER_ARM=1 kind_of "$TMP/whatever.jsonl")"
[[ "$u_out" == "worker" ]] && ok "E1 LEADV2_WORKER_ARM=1 -> worker" || bad "E1 got '$u_out'"
u_out="$(LEADV2_SUBSESSION_ROLE=worker kind_of "")"
[[ "$u_out" == "worker" ]] && ok "E2 LEADV2_SUBSESSION_ROLE=worker -> worker" || bad "E2 got '$u_out'"
u_out="$(LEADV2_SUBSESSION_ROLE=lead kind_of "")"
[[ "$u_out" == "unknown" ]] && ok "E3 LEADV2_SUBSESSION_ROLE=lead (not worker evidence) -> unknown" || bad "E3 got '$u_out'"
u_out="$(LEADV2_SESSION_KIND=lead kind_of "")"
[[ "$u_out" == "lead" ]] && ok "E4 LEADV2_SESSION_KIND pin -> lead" || bad "E4 got '$u_out'"
u_out="$(kind_of "$TMP/repo/docs/handoff/TASK-1/t.jsonl")"
[[ "$u_out" == "worker" ]] && ok "E5 docs/handoff transcript -> worker" || bad "E5 got '$u_out'"
u_out="$(kind_of "$TMP/.claude/cache/freepool-runs/260901-1/x.jsonl")"
[[ "$u_out" == "worker" ]] && ok "E6 *-runs transcript -> worker" || bad "E6 got '$u_out'"
u_out="$(kind_of "$HOME/.claude/projects/-Users-x/abc.jsonl")"
[[ "$u_out" == "lead" ]] && ok "E7 normal project transcript -> lead" || bad "E7 got '$u_out'"
u_out="$(kind_of "")"
[[ "$u_out" == "unknown" ]] && ok "E8 no evidence -> unknown" || bad "E8 got '$u_out'"

# ════════════════ mutation negative controls (red expected) ══════════════
# NC1: predicate forced to `lead` unconditionally -> A1's invariant breaks:
# the beat IS triggered for worker evidence. The control PASSES when the
# mutation makes the A1 harness arm.
SKEL_N1="$TMP/skelN1"; build_skeleton "$SKEL_N1"
python3 - "$SKEL_N1/plugins/leadv2/hooks/lib/leadv2-hook-session-kind.sh" <<'PYMUT'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace(
  'leadv2_hook_session_kind() {  # <transcript_path> -> prints lead|worker|unknown\n  local transcript="${1:-}"',
  'leadv2_hook_session_kind() {  # <transcript_path> -> prints lead|worker|unknown\n  local transcript="${1:-}"\n  printf \'lead\\n\'\n  return 0',
  1,
)
open(p, "w").write(s)
PYMUT
NC_ARMS=0
LEADV2_WORKER_ARM=1 run_hook "$SKEL_N1" "$TMP/anywhere.jsonl" >/dev/null 2>&1 \
  && wait_file "$SKEL_N1/state/beats.log" 3 && NC_ARMS=1
if [[ "$NC_ARMS" == "1" ]]; then
  ok "NC1 mutation (predicate always lead): A1 invariant broke — control red as required"
else
  bad "NC1 mutation NOT caught: worker still blocked with broken predicate"
fi

# NC2: owner-pid check neutered in the beat loop -> B1's invariant breaks:
# the loop ignores its dead owner and keeps beating.
SKEL_N2="$TMP/skelN2"; build_skeleton "$SKEL_N2"
python3 - "$SKEL_N2/plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh" <<'PYMUT'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('leadv2_loop_owner_check "$OWNER_FILE" "beat-loop"', 'true', 1)
open(p, "w").write(s)
PYMUT
sleep 30 &
NC2_OWNER=$!
(
  LEADV2_LANE_HEARTBEAT_BIN="$SKEL_N2/plugins/leadv2/scripts/leadv2-lane-heartbeat.sh" \
  LEADV2_PULSE_BEAT_BIN="$SKEL_N2/plugins/leadv2/scripts/leadv2-pulse-beat.sh" \
  LEADV2_SINGLE_LEAD_BEAT_LOOP_S=1 LEADV2_SINGLE_LEAD_BEAT_LOOP_MAX_S=30 \
  LEADV2_SINGLE_LEAD_BEAT_LOOP_PID_DIR="$SKEL_N2/state" TEST_STATE_DIR="$SKEL_N2/state" \
  LEADV2_PROJECT_ROOT="$SKEL_N2" LEADV2_LOOP_OWNER_PID="$NC2_OWNER" \
    bash "$SKEL_N2/plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh" \
    >"$SKEL_N2/loop.out" 2>&1
) &
LOOP_PID=$!
sleep 1.2
kill "$NC2_OWNER" 2>/dev/null; wait "$NC2_OWNER" 2>/dev/null
_pidfile_n2="$SKEL_N2/state/.single-lead-beat-loop"-"$(printf '%s' "$SKEL_N2" | cksum | cut -d' ' -f1)".pid
if ! wait_gone "$_pidfile_n2" 4; then
  ok "NC2 mutation (owner check neutered): B1 invariant broke — control red as required"
else
  bad "NC2 mutation NOT caught: loop still exited with check deleted"
fi
kill "$LOOP_PID" 2>/dev/null; wait "$LOOP_PID" 2>/dev/null

# ═══════════════════════════════ summary ═════════════════════════════════
printf '[TEST] %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
