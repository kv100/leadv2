#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-dispatch-code.sh leadv2-hook-session-kind.sh leadv2-lane-pulse-watch.sh leadv2-single-lead-beat-loop.sh
# tests/test-beat-loop-orphans.sh — BEAT-LOOP-ORPHANS-01 (fix-round 2)
#
# Locks both orphan mechanisms:
#
#   A   hook gate (mechanism 1): leadv2-single-lead-beat.sh invoked with
#       WORKER evidence (LEADV2_WORKER_ARM=1, LEADV2_SUBSESSION_ROLE, a
#       -claude-worktrees- transcript path, or mission-marker transcript
#       content) exits 0 silently — no beat triggered, no session-stamp
#       state touched. With the LEADV2_SESSION_KIND=lead pin it arms. With
#       NO worker signal it is `unknown`: the single-shot HOOK fail-opens
#       (arms, journals reason) — it spawns no loop; the LOOP scripts are
#       the fail-closed surfaces (F-cases).
#   B   owner-pid belt (mechanism 2): a loop whose recorded owner pid DIES
#       exits within one iteration (1s cadence); with a live owner it keeps
#       running until its lifetime cap.
#   C   transcript-mtime belt (mechanism 2): a loop whose owner transcript is
#       older than LEADV2_LOOP_ORPHAN_MAX_MIN exits within one iteration.
#   D   lane-pulse-watch honours the same owner belt.
#   E   predicate unit table: every evidence shape classifies as documented.
#       Fix-round 2: a real worker transcript (readable, no markers, at a
#       root project path) is `unknown`, never `lead` — E7.
#   F   loop surfaces fail closed on unknown + availability gates:
#       F1  classifier lib absent -> beat-loop STILL RUNS (owner belts are
#           independent of the classifier) and journals owner_check=unavailable.
#       F2  spawn-site grep gate: zero unpinned `claude -p` sites in the
#           plugin tree (LEADV2_SUBSESSION_ROLE or WORKER_ARM at each).
#
# Mutation negative controls (GATE-PROVES-ITS-OWN-CONTROL style, run against
# COPIES in a throwaway skeleton so the real tree is never mutated):
#   NC1  predicate forced to always return `lead` -> case A1 turns red
#        (the beat IS triggered for worker evidence).
#   NC2  owner-pid check neutered in the beat loop -> case B turns red (the
#        loop ignores its dead owner and keeps beating).
#   NC3  worktree-path signal dropped from the classifier -> case A2 turns
#        red (a worktree-cwd session is no longer seen as worker).
#   NC4  LEADV2_SUBSESSION_ROLE pin removed at one spawn site -> grep gate
#        (F2) turns red on the mutated copy.
#
# Hermetic: every case runs against a skeleton plugin tree (copies of the
# real hook/lib/loop + stub state-path/pulse-beat/heartbeat seams), scratch
# state dir, 1s cadence. No network, no real control-plane state.
# Run: bash plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh

set -uo pipefail

# Hermetic against the invoking process's own session-kind evidence: this
# suite is routinely run BY a worker session (LEADV2_SUBSESSION_ROLE=worker
# exported on the real dispatch env), and every `bash -c`/subshell it spawns
# inherits the exported environment. Left alone, that ambient var leaks into
# cases that assert "no env evidence -> unknown" and flips them to "worker"
# (observed: E7/E8/E9/D0b/A5/A6 false-red under a live worker dispatch).
unset LEADV2_SUBSESSION_ROLE LEADV2_WORKER_ARM LEADV2_SESSION_KIND \
      LEADV2_SESSION_KIND_OUT LEADV2_SESSION_KIND_REASON 2>/dev/null || true

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
# skeleton with stubbed seams. Mutations (NC1..NC4) are applied to the copies
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

# A2 worker via transcript PATH signal (-claude-worktrees- munged cwd — the
# round-1 docs/handoff|*-runs patterns matched no real transcript and are
# GONE): silent exit
_WT_TP="$HOME/.claude/projects/-Users-x--claude-worktrees-SOME-TASK/abc.jsonl"
out="$(run_hook "$SKEL_A" "$_WT_TP" 2>&1)"; rc=$?
if [[ $rc -eq 0 && ! -f "$SKEL_A/state/beats.log" ]]; then
  ok "A2 worker (worktree transcript path): silent exit, no beat"
else
  bad "A2 worker (worktree transcript path): rc=$rc beats=$(cat "$SKEL_A/state/beats.log" 2>/dev/null | wc -l | tr -d ' ')"
fi

# A3 worker via transcript CONTENT signal: a headless `claude -p` session's
# first user message IS the mission text — silent exit
_MK_TP="$TMP/no-worktree-here/proj.jsonl"
mkdir -p "$(dirname "$_MK_TP")"
{ printf '{"type":"user","message":"LANE ROOT: /tmp/x WORKTREE PIN: y\\n"}\n'; seq 1 5 | sed 's/^/{"filler":/' ; } > "$_MK_TP"
out="$(run_hook "$SKEL_A" "$_MK_TP" 2>&1)"; rc=$?
if [[ $rc -eq 0 && ! -f "$SKEL_A/state/beats.log" ]]; then
  ok "A3 worker (mission-marker transcript content): silent exit, no beat"
else
  bad "A3 worker (mission-marker transcript content): rc=$rc beats=$(cat "$SKEL_A/state/beats.log" 2>/dev/null | wc -l | tr -d ' ')"
fi

# A4 lead via the LEADV2_SESSION_KIND=lead pin: arms + owner transcript
# stamped (fix-round 2: with no pin there is NO positive lead evidence — a
# founder lead that needs the autonomous loop pins itself, see report.md)
out="$(LEADV2_SESSION_KIND=lead run_hook "$SKEL_A" "$TMP/lead-transcript.jsonl" 2>&1)"; rc=$?
if [[ $rc -eq 0 && -f "$SKEL_A/state/.beat-owner-transcript" ]] \
   && wait_file "$SKEL_A/state/beats.log" 3; then
  ok "A4 lead (pin): beat triggered + owner transcript stamped"
else
  bad "A4 lead (pin): rc=$rc beats=$(cat "$SKEL_A/state/beats.log" 2>/dev/null | wc -l | tr -d ' ') stamp=$([[ -f "$SKEL_A/state/.beat-owner-transcript" ]] && echo y || echo n)"
fi

# A5 unknown evidence (no transcript, no env): hook fail-opens (it spawns no
# loop) but journals kind=unknown reason=no_transcript
out="$(run_hook "$SKEL_A" "" 2>&1)"; rc=$?
if [[ $rc -eq 0 && -f "$SKEL_A/state/loop-arm-journal.log" ]] \
   && grep -q "event=loop_armed_by_unknown_session loop=single-lead-beat-hook kind=unknown reason=no_transcript" "$SKEL_A/state/loop-arm-journal.log" 2>/dev/null; then
  ok "A5 unknown (no transcript): fail-open arm journaled with reason"
else
  bad "A5 unknown: rc=$rc journal=$(cat "$SKEL_A/state/loop-arm-journal.log" 2>/dev/null | head -1)"
fi

# A6 readable transcript, NO worker signal (a root project path): still
# `unknown` for the predicate — hook fail-opens + journals
# reason=no_worker_evidence (E7 locks the predicate half of this)
_ROOT_TP="$TMP/plain-project/transcript.jsonl"
mkdir -p "$(dirname "$_ROOT_TP")"
printf '{"type":"user","message":"hello world"}\n' > "$_ROOT_TP"
out="$(run_hook "$SKEL_A" "$_ROOT_TP" 2>&1)"; rc=$?
if [[ $rc -eq 0 ]] \
   && grep -q "loop=single-lead-beat-hook kind=unknown reason=no_worker_evidence" "$SKEL_A/state/loop-arm-journal.log" 2>/dev/null; then
  ok "A6 root transcript, no signals -> unknown, journaled with reason"
else
  bad "A6 root transcript: rc=$rc journal tail=$(tail -1 "$SKEL_A/state/loop-arm-journal.log" 2>/dev/null)"
fi

# ══════════════════ B/C. beat loop owner belts (mechanism 2) ═════════════
# NOTE (fix-round 2): the loop scripts FAIL CLOSED on unknown — every belt
# harness below pins LEADV2_SESSION_KIND=lead because it tests the OWNER
# belts, not the classifier (the classifier is unit-tabled in E).

# B1 owner pid dies -> loop exits within one iteration
SKEL_B="$TMP/skelB"; build_skeleton "$SKEL_B"
sleep 30 &
OWNER_PID=$!
(
  LEADV2_SESSION_KIND=lead \
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
  LEADV2_SESSION_KIND=lead \
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
  LEADV2_SESSION_KIND=lead \
  LEADV2_LANE_HEARTBEAT_BIN="$SKEL_D/plugins/leadv2/scripts/leadv2-lane-heartbeat.sh" \
  LEADV2_PULSE_BEAT_BIN="$SKEL_D/plugins/leadv2/scripts/leadv2-pulse-beat.sh" \
  LEADV2_SINGLE_LEAD_BEAT_LOOP_S=1 LEADV2_SINGLE_LEAD_BEAT_LOOP_MAX_S=6 \
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

# D0b (fix-round 2, fail-closed lock): the SAME harness WITHOUT the lead pin
# classifies `unknown` -> the loop must NOT arm at all (no pidfile, no beat).
SKEL_D2="$TMP/skelD2"; build_skeleton "$SKEL_D2"
sleep 60 &
D2_OWNER=$!
(
  LEADV2_LANE_HEARTBEAT_BIN="$SKEL_D2/plugins/leadv2/scripts/leadv2-lane-heartbeat.sh" \
  LEADV2_PULSE_BEAT_BIN="$SKEL_D2/plugins/leadv2/scripts/leadv2-pulse-beat.sh" \
  LEADV2_SINGLE_LEAD_BEAT_LOOP_S=1 LEADV2_SINGLE_LEAD_BEAT_LOOP_MAX_S=3 \
  LEADV2_SINGLE_LEAD_BEAT_LOOP_PID_DIR="$SKEL_D2/state" TEST_STATE_DIR="$SKEL_D2/state" \
  LEADV2_PROJECT_ROOT="$SKEL_D2" LEADV2_LOOP_OWNER_PID="$D2_OWNER" \
    bash "$SKEL_D2/plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh" \
    >"$SKEL_D2/loop.out" 2>&1
) &
sleep 2.2
_d2_pidfile="$SKEL_D2/state/.single-lead-beat-loop"-"$(printf '%s' "$SKEL_D2" | cksum | cut -d' ' -f1)".pid
if [[ ! -f "$_d2_pidfile" && ! -s "$SKEL_D2/state/beats.log" ]] \
   && grep -q "loop=single-lead-beat-loop kind=unknown" "$SKEL_D2/docs/leadv2/loop-arm-journal.log" 2>/dev/null; then
  ok "D0b unknown (no pin): loop FAILS CLOSED — not armed, journaled"
else
  bad "D0b unknown: pidfile=$([[ -f "$_d2_pidfile" ]] && echo present || echo absent) journal=$(cat "$SKEL_D2/docs/leadv2/loop-arm-journal.log" 2>/dev/null | head -1)"
fi
kill "$LOOP_PID" 2>/dev/null; wait "$LOOP_PID" 2>/dev/null
kill "$D2_OWNER" 2>/dev/null; wait "$D2_OWNER" 2>/dev/null

# ═════════════════ D. lane-pulse-watch honours the owner belt ════════════
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
  LEADV2_SESSION_KIND=lead \
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
kind_reason() {  # <transcript> -> "kind:reason"
  bash -c "
    source '$LIB' >/dev/null 2>&1
    leadv2_hook_session_kind '$1' >/dev/null
    printf '%s:%s' \"\$LEADV2_SESSION_KIND_OUT\" \"\$LEADV2_SESSION_KIND_REASON\"
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
u_out="$(kind_of "$HOME/.claude/projects/-Users-x--claude-worktrees-TASK-1/abc.jsonl")"
[[ "$u_out" == "worker" ]] && ok "E5 worktree-cwd transcript path -> worker" || bad "E5 got '$u_out'"
_MK_TP2="$TMP/marker-proj/t.jsonl"; mkdir -p "$(dirname "$_MK_TP2")"
printf '{"type":"queued-command"}\n{"type":"user","message":"... LANE_WRITES: a,b,c ..."}\n' > "$_MK_TP2"
u_out="$(kind_of "$_MK_TP2")"
[[ "$u_out" == "worker" ]] && ok "E6 mission marker in transcript head -> worker" || bad "E6 got '$u_out'"
_LATE_TP="$TMP/late-marker/t.jsonl"; mkdir -p "$(dirname "$_LATE_TP")"
{ seq 1 25 | sed 's/^/{"filler":/'; } > "$_LATE_TP"
printf '{"type":"user","message":"LEADV2_LANE_OUTCOME=ok"}\n' >> "$_LATE_TP"
u_out="$(kind_of "$_LATE_TP")"
[[ "$u_out" == "unknown" ]] && ok "E9 marker beyond the 20-line window -> unknown (bounded read)" || bad "E9 got '$u_out'"
u_out="$(kind_of "$HOME/.claude/projects/-Users-x/abc.jsonl")"
[[ "$u_out" == "unknown" ]] && ok "E7 root project transcript, no signals -> unknown (FIXED: was lead)" || bad "E7 got '$u_out'"
u_out="$(kind_of "")"
[[ "$u_out" == "unknown" ]] && ok "E8 no evidence -> unknown" || bad "E8 got '$u_out'"
kr="$(kind_reason "$HOME/.claude/projects/-Users-x--claude-worktrees-TASK-1/abc.jsonl")"
[[ "$kr" == "worker:worktree_path" ]] && ok "E10 reason=worktree_path on the path signal" || bad "E10 got '$kr'"
kr="$(kind_reason "$_MK_TP2")"
[[ "$kr" == "worker:mission_transcript" ]] && ok "E10 reason=mission_transcript on the content signal" || bad "E10 got '$kr'"
_CLEAN_TP="$TMP/clean-root/t.jsonl"; mkdir -p "$(dirname "$_CLEAN_TP")"
printf '{"type":"user","message":"hello world"}\n' > "$_CLEAN_TP"
kr="$(kind_reason "$_CLEAN_TP")"
[[ "$kr" == "unknown:no_worker_evidence" ]] && ok "E10 reason=no_worker_evidence for a clean root transcript" || bad "E10 got '$kr'"
kr="$(kind_reason "$HOME/.claude/projects/-Users-x/abc.jsonl")"
[[ "$kr" == "unknown:no_transcript" ]] && ok "E10 reason=no_transcript for an unreadable path" || bad "E10 got '$kr'"

# ═════════════ F. loop-surface gates (fail closed / availability) ════════
# F1 classifier lib ABSENT: the beat loop must STILL RUN (mechanism-2 owner
# belts are independent of the classifier) and journal owner_check=unavailable
# — a missing lib must never kill the founder beat with rc 127 (round-1
# finding 4).
SKEL_G="$TMP/skelG"; build_skeleton "$SKEL_G"
sleep 60 &
F1_OWNER=$!
(
  LEADV2_SESSION_KIND_LIB=/nonexistent/leadv2-hook-session-kind.sh \
  LEADV2_LANE_HEARTBEAT_BIN="$SKEL_G/plugins/leadv2/scripts/leadv2-lane-heartbeat.sh" \
  LEADV2_PULSE_BEAT_BIN="$SKEL_G/plugins/leadv2/scripts/leadv2-pulse-beat.sh" \
  LEADV2_SINGLE_LEAD_BEAT_LOOP_S=1 LEADV2_SINGLE_LEAD_BEAT_LOOP_MAX_S=3 \
  LEADV2_SINGLE_LEAD_BEAT_LOOP_PID_DIR="$SKEL_G/state" TEST_STATE_DIR="$SKEL_G/state" \
  LEADV2_PROJECT_ROOT="$SKEL_G" LEADV2_LOOP_OWNER_PID="$F1_OWNER" \
    bash "$SKEL_G/plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh" \
    >"$SKEL_G/loop.out" 2>&1
) &
LOOP_PID=$!
_f1=YES
wait_file "$SKEL_G/state/beats.log" 5 || _f1=NO
sleep 0.3
if [[ "$_f1" == "YES" ]] \
   && grep -q "event=owner_check_unavailable loop=single-lead-beat-loop reason=classifier_lib_missing" "$SKEL_G/docs/leadv2/loop-arm-journal.log" 2>/dev/null; then
  ok "F1 lib absent -> beat still runs + owner_check=unavailable journaled"
else
  bad "F1 lib absent: beats=$(cat "$SKEL_G/state/beats.log" 2>/dev/null | wc -l | tr -d ' ') journal=$(cat "$SKEL_G/docs/leadv2/loop-arm-journal.log" 2>/dev/null | head -1)"
fi
kill "$LOOP_PID" 2>/dev/null; wait "$LOOP_PID" 2>/dev/null
kill "$F1_OWNER" 2>/dev/null; wait "$F1_OWNER" 2>/dev/null

# F2 spawn-site grep gate: ZERO unpinned `claude -p` sites in the plugin
# tree. spawn_gate prints offending file:line rows; rc 0 when none.
spawn_gate() {  # <scripts_dir> <hooks_dir>
  local sdir="$1" hdir="$2" hits rows="" row f line
  hits="$(grep -rnE '(claude|CLAUDE_BIN|FREEPOOL_CLAUDE_BIN|KIMI_CLAUDE_BIN|GLM_CLAUDE_BIN)[^|;&>]*[" -]-p( |")|spawn_args=\(-p|claude_args=\(|claude -p|claude --print' \
    "$sdir" "$hdir" --include='*.sh' 2>/dev/null \
    | grep -v '/tests/' | grep -vE ':[0-9]+:[[:space:]]*#' || true)"
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    f="${row%%:*}"
    case "$f" in
      */leadv2-lanes.sh) continue ;;  # python string list of runner names, not a spawn
    esac
    if printf '%s' "$row" | grep -q 'LEADV2_SUBSESSION_ROLE'; then continue; fi
    if grep -qE 'export LEADV2_SUBSESSION_ROLE|LEADV2_WORKER_ARM=1' "$f" 2>/dev/null; then continue; fi
    rows+="$row"$'\n'
  done <<< "$hits"
  if [[ -n "$rows" ]]; then
    printf '%s' "$rows"
    return 1
  fi
  return 0
}
if gate_out="$(spawn_gate "$SCRIPTS_DIR" "$PLUGIN_DIR/hooks")"; then
  ok "F2 spawn grep gate: zero unpinned claude -p sites in the live tree"
else
  bad "F2 spawn grep gate found unpinned sites:
$gate_out"
fi

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
  LEADV2_SESSION_KIND=lead \
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

# NC3 (fix-round 2): worktree-path signal dropped from the classifier ->
# A2's invariant breaks: a worktree-cwd session is no longer seen as worker
# and the hook arms.
SKEL_N3="$TMP/skelN3"; build_skeleton "$SKEL_N3"
python3 - "$SKEL_N3/plugins/leadv2/hooks/lib/leadv2-hook-session-kind.sh" <<'PYMUT'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('''  case "$tp" in
    *-claude-worktrees-*)
      LEADV2_SESSION_KIND_REASON="worktree_path"
      return 0
      ;;
  esac''', '  :', 1)
open(p, "w").write(s)
PYMUT
_skel="$SKEL_N3" _tp="$HOME/.claude/projects/-Users-x--claude-worktrees-SOME-TASK/abc.jsonl" \
  bash -c '
    mkdir -p "$_skel/state"
    LEADV2_SINGLE_LEAD_BEAT=1 TEST_STATE_DIR="$_skel/state" \
    CLAUDE_PLUGIN_ROOT="$_skel/plugins/leadv2" \
    bash "$_skel/plugins/leadv2/hooks/leadv2-single-lead-beat.sh" <<EOF
{"hook_event_name":"UserPromptSubmit","session_id":"nc3$$","cwd":"$_skel","transcript_path":"$_tp"}
EOF
  ' >/dev/null 2>&1
if wait_file "$SKEL_N3/state/beats.log" 3; then
  ok "NC3 mutation (worktree signal dropped): A2 invariant broke — control red as required"
else
  bad "NC3 mutation NOT caught: worktree-cwd session still blocked without the path signal"
fi

# NC4 (fix-round 2): LEADV2_SUBSESSION_ROLE pin removed at one spawn site ->
# F2 grep gate turns red on the MUTATED COPY of the tree.
SKEL_N4="$TMP/skelN4"
mkdir -p "$SKEL_N4"
cp -R "$SCRIPTS_DIR" "$SKEL_N4/scripts"
cp -R "$PLUGIN_DIR/hooks" "$SKEL_N4/hooks"
python3 - "$SKEL_N4/scripts/leadv2-task-judge.sh" <<'PYMUT'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('raw="$(LEADV2_SUBSESSION_ROLE="${LEADV2_SUBSESSION_ROLE:-judge}" "${CLAUDE_BIN}" -p "${prompt}"',
              'raw="$("${CLAUDE_BIN}" -p "${prompt}"', 1)
open(p, "w").write(s)
PYMUT
if gate_out="$(spawn_gate "$SKEL_N4/scripts" "$SKEL_N4/hooks")"; then
  bad "NC4 mutation NOT caught: grep gate green with the task-judge pin stripped"
else
  if printf '%s' "$gate_out" | grep -q 'leadv2-task-judge.sh'; then
    ok "NC4 mutation (pin stripped at task-judge): F2 gate red as required"
  else
    bad "NC4 mutation: gate red but not on task-judge (got: $gate_out)"
  fi
fi

# ═══════════════════════════════ summary ═════════════════════════════════
printf '[TEST] %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
