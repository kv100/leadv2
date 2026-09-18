#!/usr/bin/env bash
# tests/test-fanout-ambiguous-live-worker-row.sh — regression test for
# DISPATCH-AMBIGUOUS-ROW-RELEASE-01 (lane 04b0ba0f5334).
#
# dispatch-code.sh's rc=5 shape is AMBIGUOUS: spawn_worker positively verified
# a live worker, but the dispatch_confirm ledger write failed. On that path
# dispatch-code.sh deliberately disarms its own EXIT-trap slot release and
# exits 1, leaving the lane's active.yaml row for the stale-sweeper to reap.
# Its callers (leadv2-fanout-lane-launcher.sh and leadv2-fanout.sh's
# synchronous funnel) run dispatch-code.sh as a SUBPROCESS and used to bare-
# unregister their own row on any non-{0,2,3,6} rc — deleting exactly the row
# dispatch-code.sh just decided not to touch. The task was re-claimed and
# re-dispatched while the orphaned worker ran on: two live workers on one lane.
#
# dispatch-code.sh now flags that shape with a stdout marker line
#   dispatch_ambiguous_live_worker=1
# and all three callers must, on seeing it: skip the row unregister, skip the
# full-cycle re-launch fallback, and park (never `dead`: the worker may be
# live). A dispatch-code.sh crash that never emitted the marker keeps today's
# unconditional cleanup — that path is load-bearing for the genuine
# "dispatch-code.sh never even ran" case (test-fanout-lane-detach.sh's
# FAKE_DC_CRASH section is the end-to-end negative control for it; Part B
# below repeats a local copy so this suite is self-contained).
#
# Part A: real leadv2-fanout-lane-launcher.sh end to end against a stub
#         dispatch-code.sh emitting the marker + exit 1 (the rc=5 process
#         shape): the active.yaml row must SURVIVE the launcher's exit, a
#         parked terminal row must be written (this is also what disarms the
#         launcher's own EXIT trap — without it _cleanup_on_death would
#         unregister the row anyway and silently undo the fix), and the lane
#         worktree must be left alone (a live worker may still be writing it).
# Part B: negative control — a marker-less crash stub (exit 137, the
#         FAKE_DC_CRASH shape) must still unregister the row.
# Part C: leadv2-fanout.sh's synchronous funnel branch (launch_via_dispatch_code,
#         LEADV2_FANOUT_LANE_DETACH=0), extracted and its collaborators
#         stubbed with call counters: with the marker, neither
#         leadv2_active_unregister nor _fanout_launch_full_cycle may fire and
#         a parked terminal is written; without it, both must fire exactly as
#         before (the fallback is the "second full cycle" half of the bug).
# Part D: leadv2-backlog-pump.sh's cmd_async_dispatch catch-all (`*)` branch,
#         the THIRD caller), extracted with _pump_release_lane the same way:
#         with the marker, neither _pump_release_lane (=
#         leadv2_active_unregister) nor the generic pump_skip/spawn_failed
#         path may fire, the claim IS released, and the journal surfaces the
#         ambiguity; without it, the unconditional release must still fire
#         (negative control).
#
# Usage: bash plugins/leadv2/tests/test-fanout-ambiguous-live-worker-row.sh
# run-all-triggers: leadv2-dispatch-code leadv2-fanout leadv2-fanout-lane-launcher leadv2-backlog-pump

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

# ── Fixture repo (same shape as test-fanout-lane-detach.sh Part B) ──────────
PROJECT_ROOT="${TMPD}/repo"
mkdir -p "$PROJECT_ROOT/docs/leadv2" "$PROJECT_ROOT/docs/handoff"
( cd "$PROJECT_ROOT" && git init -q && git config user.email t@t.com && git config user.name t && git commit -q --allow-empty -m init )
cat > "$PROJECT_ROOT/docs/tasks.yaml" <<'EOF'
total_open: 0
tasks: []
EOF

LEDGER_FILE="${TMPD}/terminal-ledger.jsonl"
ACTIVE_YAML="${PROJECT_ROOT}/docs/leadv2/active.yaml"
MISSION_FILE="${TMPD}/mission.txt"
printf 'Task test-amb: do a thing\n' > "$MISSION_FILE"

# The rc=5 process shape: a worker was spawned+verified, then the confirm
# write failed; dispatch-code.sh emits the marker and exits 1.
FAKE_DC_AMBIG="${TMPD}/fake-dispatch-ambiguous.sh"
cat > "$FAKE_DC_AMBIG" <<'EOF'
#!/usr/bin/env bash
printf 'worker_spawned by=router model=sonnet task=deadbeef2 handle=PID=999999 attempt=att-amb\n'
printf 'dispatch_ambiguous_live_worker=1\n'
printf 'simulated confirm-write failure: worker may be live but unrecorded\n' >&2
exit 1
EOF
chmod +x "$FAKE_DC_AMBIG"

# The genuine-crash shape: dispatch-code.sh never even ran its dispatch logic,
# no marker — today's unconditional cleanup must stay in force.
FAKE_DC_CRASH="${TMPD}/fake-dispatch-crash.sh"
cat > "$FAKE_DC_CRASH" <<'EOF'
#!/usr/bin/env bash
echo "simulated crash" >&2
exit 137
EOF
chmod +x "$FAKE_DC_CRASH"

# ── Part A: launcher + marker stub -> row survives, parked terminal ─────────
SIG_DIR_AMB="${PROJECT_ROOT}/docs/handoff/fanout-lane-test-amb-1"
mkdir -p "$SIG_DIR_AMB"
env LEADV2_PROJECT_ROOT="$PROJECT_ROOT" PROJECT_ROOT="$PROJECT_ROOT" \
    LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$LEDGER_FILE" \
  bash "$LAUNCHER_SH" \
    --task-id test-amb-1 --class Light --mission-file "$MISSION_FILE" \
    --project-root "$PROJECT_ROOT" --sig-dir "$SIG_DIR_AMB" \
    --dispatch-bin "$FAKE_DC_AMBIG" --lead-model sonnet --lead-effort medium \
    --provider claude >"${TMPD}/launcher-amb.log" 2>&1
launcher_amb_rc=$?

if [[ "$launcher_amb_rc" -ne 0 ]]; then
  pass "launcher exits non-zero on the ambiguous dispatch-code.sh shape (rc=${launcher_amb_rc})"
else
  fail "launcher exited 0 despite dispatch-code.sh reporting ambiguity (expected 1)"
fi

if grep -q 'task_id: test-amb-1' "$ACTIVE_YAML" 2>/dev/null; then
  pass "active.yaml row for test-amb-1 SURVIVES the ambiguous rc -- not released on a guess"
else
  fail "active.yaml row for test-amb-1 was released despite dispatch_ambiguous_live_worker=1 -- the pre-fix double-dispatch bug: $(cat "${TMPD}/launcher-amb.log")"
fi

if [[ -f "$LEDGER_FILE" ]] \
   && grep -q '"task_sig":"fanout-test-amb-1"' "$LEDGER_FILE" \
   && grep -q '"terminal":"parked"' "$LEDGER_FILE" \
   && grep -q '"cause":"dispatch_code_ambiguous_live_worker"' "$LEDGER_FILE"; then
  pass "a parked cause=dispatch_code_ambiguous_live_worker terminal row was written (also disarms the launcher's EXIT trap)"
else
  fail "no parked dispatch_code_ambiguous_live_worker terminal row found: $(cat "$LEDGER_FILE" 2>/dev/null)"
fi

if grep -q 'dispatch_ambiguous_live_worker=1' "${TMPD}/launcher-amb.log"; then
  pass "launcher log surfaces the ambiguity instead of a generic failure"
else
  fail "launcher log does not mention dispatch_ambiguous_live_worker=1: $(cat "${TMPD}/launcher-amb.log")"
fi

# ── Part B: negative control — marker-less crash keeps unconditional cleanup ─
SIG_DIR_CTL="${PROJECT_ROOT}/docs/handoff/fanout-lane-test-amb-2"
mkdir -p "$SIG_DIR_CTL"
env LEADV2_PROJECT_ROOT="$PROJECT_ROOT" PROJECT_ROOT="$PROJECT_ROOT" \
    LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$LEDGER_FILE" \
  bash "$LAUNCHER_SH" \
    --task-id test-amb-2 --class Standard --mission-file "$MISSION_FILE" \
    --project-root "$PROJECT_ROOT" --sig-dir "$SIG_DIR_CTL" \
    --dispatch-bin "$FAKE_DC_CRASH" --lead-model sonnet --lead-effort medium \
    --provider claude >"${TMPD}/launcher-ctl.log" 2>&1
launcher_ctl_rc=$?

if [[ "$launcher_ctl_rc" -ne 0 ]]; then
  pass "control: launcher exits non-zero on a genuine crash (rc=${launcher_ctl_rc})"
else
  fail "control: launcher exited 0 despite dispatch-code.sh crashing"
fi

if grep -q 'task_id: test-amb-2' "$ACTIVE_YAML" 2>/dev/null; then
  fail "control: active.yaml still carries a row for the crashed lane test-amb-2 (cleanup must stay unconditional when no marker was emitted)"
else
  pass "control: marker-less crash still unregisters the active.yaml row (negative control intact)"
fi

# ── Part C: fanout.sh synchronous funnel branch (extracted + call counters) ─
FUNNEL_FUNCS="${TMPD}/funnel-funcs.sh"
sed -n '/^launch_via_dispatch_code() {/,/^}$/p' "$FANOUT_SH" > "$FUNNEL_FUNCS"
if [[ -s "$FUNNEL_FUNCS" ]]; then
  pass "extracted launch_via_dispatch_code from leadv2-fanout.sh ($(wc -l < "$FUNNEL_FUNCS") lines)"
else
  fail "could not extract launch_via_dispatch_code from leadv2-fanout.sh -- has it been renamed/removed?"
fi

# _run_sync_funnel <dispatch-bin> <tid> -- runs the extracted function in a
# subshell with every collaborator stubbed; each stub appends to a call file.
_run_sync_funnel() {
  local dc_bin="$1" tid="$2"
  (
    set -uo pipefail
    export LEADV2_FANOUT_LANE_DETACH=0        # force the SYNCHRONOUS branch
    export LEADV2_WRITES_CONFLICT_NOTIFY=0    # skip the writes-overlap block
    export LEADV2_FANOUT_DISPATCH_BIN="$dc_bin"
    SCRIPT_DIR="$SCRIPTS_DIR"
    PROJECT_ROOT="$PROJECT_ROOT"
    log()       { :; }
    log_error() { printf '[fanout-sync-test] %s\n' "$*" >&2; }
    _fanout_ensure_tasks_lib()   { return 0; }
    leadv2_tasks_claim()         { return 0; }
    _fanout_mission_for_task()   { printf 'mission text'; }
    _fanout_task_lane_contract() { printf '\t\t0'; }
    _fanout_register_session()   { return 0; }
    leadv2_tasks_unclaim()       { printf '%s\n' "$1" >> "${TMPD}/unclaim.${tid}.calls"; return 0; }
    leadv2_active_unregister()   { printf '%s\n' "$1" >> "${TMPD}/unreg.${tid}.calls"; return 0; }
    _fanout_launch_full_cycle()  { printf '%s\n' "$1" >> "${TMPD}/fullcycle.${tid}.calls"; return 0; }
    _fanout_write_lane_terminal() { printf '%s\n' "$*" >> "${TMPD}/terminal.${tid}.calls"; return 0; }
    # shellcheck disable=SC1090
    source "$FUNNEL_FUNCS"
    launch_via_dispatch_code "$tid" "Light" "sonnet" "medium" "" "" "claude" "" "" "label"
  )
}

# C1: ambiguous shape -> no unregister, no full-cycle fallback, parked.
: > "${TMPD}/unreg.t-amb-sync.calls" 2>/dev/null || : # pre-create so -f checks are simple
_run_sync_funnel "$FAKE_DC_AMBIG" "t-amb-sync" >/dev/null 2>&1

if [[ -s "${TMPD}/unreg.t-amb-sync.calls" ]]; then
  fail "sync funnel: leadv2_active_unregister fired despite dispatch_ambiguous_live_worker=1: $(cat "${TMPD}/unreg.t-amb-sync.calls")"
else
  pass "sync funnel: active.yaml reservation row NOT unregistered on the ambiguous shape"
fi

if [[ -s "${TMPD}/fullcycle.t-amb-sync.calls" ]]; then
  fail "sync funnel: _fanout_launch_full_cycle fired despite dispatch_ambiguous_live_worker=1 -- that is the 'second full cycle' half of the double-worker bug: $(cat "${TMPD}/fullcycle.t-amb-sync.calls")"
else
  pass "sync funnel: no full-cycle re-launch on the ambiguous shape (no second worker)"
fi

if grep -q 'parked' "${TMPD}/terminal.t-amb-sync.calls" 2>/dev/null \
   && grep -q 'dispatch_code_ambiguous_live_worker' "${TMPD}/terminal.t-amb-sync.calls" 2>/dev/null; then
  pass "sync funnel: parked dispatch_code_ambiguous_live_worker terminal written (lane not silently dropped)"
else
  fail "sync funnel: no parked dispatch_code_ambiguous_live_worker terminal row: $(cat "${TMPD}/terminal.t-amb-sync.calls" 2>/dev/null)"
fi

if grep -q 't-amb-sync' "${TMPD}/unclaim.t-amb-sync.calls" 2>/dev/null; then
  pass "sync funnel: claim released on the ambiguous shape (task returns to pending)"
else
  fail "sync funnel: claim NOT released on the ambiguous shape (task would be stuck claimed)"
fi

# C2: control — marker-less crash keeps unregister + full-cycle fallback.
_run_sync_funnel "$FAKE_DC_CRASH" "t-ctl-sync" >/dev/null 2>&1

if [[ -s "${TMPD}/unreg.t-ctl-sync.calls" ]]; then
  pass "control: sync funnel still unregisters the reservation row on a marker-less crash"
else
  fail "control: sync funnel did NOT unregister on a marker-less crash -- the load-bearing cleanup path regressed"
fi

if [[ -s "${TMPD}/fullcycle.t-ctl-sync.calls" ]]; then
  pass "control: sync funnel still falls back to full-cycle on a marker-less crash"
else
  fail "control: sync funnel no longer falls back to full-cycle on a marker-less crash -- the founder-picked task would be silently dropped"
fi

# ── Part D: backlog-pump.sh cmd_async_dispatch catch-all (extracted + counters)
# The pump's catch-all `*)` branch is the THIRD caller of the same contract:
# it bare-called _pump_release_lane (= leadv2_active_unregister) on ANY
# non-{0,2,3,6} rc, deleting the row dispatch-code.sh deliberately left and
# letting the next pump tick re-dispatch onto the possibly-live worker.
PUMP_SH="${SCRIPTS_DIR}/leadv2-backlog-pump.sh"
PUMP_FUNCS="${TMPD}/pump-funcs.sh"
sed -n '/^_pump_release_lane() {/,/^}$/p' "$PUMP_SH" > "$PUMP_FUNCS"
sed -n '/^cmd_async_dispatch() {/,/^}$/p' "$PUMP_SH" >> "$PUMP_FUNCS"
if grep -q '^_pump_release_lane() {' "$PUMP_FUNCS" \
   && grep -q '^cmd_async_dispatch() {' "$PUMP_FUNCS"; then
  pass "extracted _pump_release_lane + cmd_async_dispatch from leadv2-backlog-pump.sh ($(wc -l < "$PUMP_FUNCS") lines)"
else
  fail "could not extract _pump_release_lane/cmd_async_dispatch from leadv2-backlog-pump.sh -- has it been renamed/removed?"
fi

# _run_pump_dispatch <dispatch-bin> <tid> -- runs the extracted function in a
# subshell with every collaborator stubbed; each stub appends to a call file
# (same shape as Part C). Prints the function's rc on stdout.
_run_pump_dispatch() {
  local dc_bin="$1" tid="$2"
  (
    set -uo pipefail
    DISPATCH_BIN="$dc_bin"
    SCRIPT_DIR="$SCRIPTS_DIR"
    log()   { :; }
    jemit() { printf '%s %s\n' "$1" "$2" >> "${TMPD}/journal.${tid}.calls"; return 0; }
    leadv2_tasks_unclaim()     { printf '%s\n' "$1" >> "${TMPD}/unclaim.${tid}.calls"; return 0; }
    leadv2_active_unregister() { printf '%s\n' "$1" >> "${TMPD}/unreg.${tid}.calls"; return 0; }
    # shellcheck disable=SC1090
    source "$PUMP_FUNCS"
    cmd_async_dispatch "$tid" "mission text" "lane-1" "P0" "0"
    printf 'rc=%s\n' "$?"
  )
}

# D1: ambiguous shape -> no lane release, claim released, ambiguity journaled.
: > "${TMPD}/unreg.t-amb-pump.calls" 2>/dev/null || :
_run_pump_dispatch "$FAKE_DC_AMBIG" "t-amb-pump" >"${TMPD}/pump-amb.out" 2>&1

if grep -q '^rc=1$' "${TMPD}/pump-amb.out"; then
  pass "pump: cmd_async_dispatch returns 1 on the ambiguous shape"
else
  fail "pump: expected rc=1 on the ambiguous shape, got: $(cat "${TMPD}/pump-amb.out" 2>/dev/null)"
fi

if [[ -s "${TMPD}/unreg.t-amb-pump.calls" ]]; then
  fail "pump: _pump_release_lane fired (leadv2_active_unregister) despite dispatch_ambiguous_live_worker=1 -- the third-caller half of the two-live-workers bug: $(cat "${TMPD}/unreg.t-amb-pump.calls")"
else
  pass "pump: _pump_release_lane NOT called on the marker path (active.yaml row stays for the stale-sweeper)"
fi

if grep -q 't-amb-pump' "${TMPD}/unclaim.t-amb-pump.calls" 2>/dev/null; then
  pass "pump: claim released on the ambiguous shape (task returns to pending)"
else
  fail "pump: claim NOT released on the ambiguous shape (task would be stuck claimed)"
fi

if grep -q 'dispatch_ambiguous_live_worker' "${TMPD}/journal.t-amb-pump.calls" 2>/dev/null; then
  pass "pump: journal surfaces the ambiguity (reason=dispatch_ambiguous_live_worker) instead of a generic spawn_failed"
else
  fail "pump: journal does not surface the ambiguity: $(cat "${TMPD}/journal.t-amb-pump.calls" 2>/dev/null)"
fi

if grep -q 'pump_skip' "${TMPD}/journal.t-amb-pump.calls" 2>/dev/null; then
  fail "pump: the generic pump_skip/spawn_failed path fired on the marker -- the ambiguity is being misreported as a dead spawn: $(cat "${TMPD}/journal.t-amb-pump.calls")"
else
  pass "pump: generic pump_skip/spawn_failed path NOT taken on the marker"
fi

# D2: control — marker-less crash keeps the unconditional lane release.
_run_pump_dispatch "$FAKE_DC_CRASH" "t-ctl-pump" >"${TMPD}/pump-ctl.out" 2>&1

if [[ -s "${TMPD}/unreg.t-ctl-pump.calls" ]]; then
  pass "control: pump still releases the lane row via _pump_release_lane on a marker-less crash"
else
  fail "control: pump did NOT release the lane row on a marker-less crash -- the load-bearing cleanup path regressed"
fi

if grep -q 't-ctl-pump' "${TMPD}/unclaim.t-ctl-pump.calls" 2>/dev/null; then
  pass "control: pump still releases the claim on a marker-less crash"
else
  fail "control: pump did NOT release the claim on a marker-less crash (task would be stuck claimed)"
fi

echo "----"
echo "PASS=${PASS} FAIL=${FAIL}"
[[ "$FAIL" -eq 0 ]]
