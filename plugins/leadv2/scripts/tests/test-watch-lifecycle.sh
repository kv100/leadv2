#!/usr/bin/env bash
# tests/test-watch-lifecycle.sh — WATCHER-LIFECYCLE-LEAK-01: watcher singleton
# + owner-bound self-reap + lifecycle events.
#
# Locks lib/leadv2-watch-lifecycle.sh as wired into the two detached watchers
# (leadv2-single-lead-beat-loop.sh, leadv2-lane-pulse-watch.sh):
#
#   L1  double-spawn of the beat loop with the same owner -> exactly ONE live
#       loop; the refused copy exits fast, leaves the pidfile to the first,
#       and logs event=dedup_refused; the survivor keeps beating (no
#       behavior change when exactly one healthy loop exists).
#   L2  CONCURRENT arm storm — the 2026-09-01 leak shape: 5 simultaneous
#       spawns against one root -> exactly one survivor (the pre-fix
#       check-then-write guard let racing arms through; 17 duplicates were
#       measured live).
#   L3  owner-bound self-reap: killing LEADV2_WATCHER_OWNER_PID stops the
#       beat loop within one interval, removes the pidfile, logs self_reap.
#   L4  lane-pulse-watch: double-spawn -> one watcher, dedup_refused logged,
#       pidfile ownership unchanged.
#   L5  lane-pulse-watch: owner kill -> exits within one interval, pidfile
#       removed, self_reap logged.
#   L6  no residual growth: 3 spawn/kill cycles -> live-copy count returns to
#       the pre-test baseline between cycles (the ticket's monotonic-growth
#       acceptance, miniatured).
#   L7  NEGATIVE CONTROL (RUN RED): a scratch copy of the beat loop with the
#       singleton claim reverted to the pre-fix blind pidfile write arms TWO
#       loops under the L1 scenario — proving L1/L2 lock the dedup mechanism,
#       not an incidental pass.
#
# Fix-r2 scoping: live-copy counts are SCENARIO-scoped — this harness only
# counts PIDs it started (and verifies its pidfile holder), so machine-global
# residue from another worktree or an earlier run cannot poison L1/L2.
# Teardown additionally asserts ZERO tracked-scenario residue at suite end
# and FAILs the suite otherwise (fix-r2 #3).
# Still serial-conservative with test-single-lead-beat-loop.sh /
# test-lane-pulse-watch.sh (the repo's changed-scope runner is serial).
# Hermetic: scratch roots, fake heartbeat/beat/pulse bins, scratch pid dir +
# lifecycle log, interval 1s. Run: bash scripts/tests/test-watch-lifecycle.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
LOOP="$SCRIPT_DIR/leadv2-single-lead-beat-loop.sh"
WATCH="$SCRIPT_DIR/leadv2-lane-pulse-watch.sh"

PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d /tmp/leadv2-watch-lifecycle-XXXXXX)"
WL_LOG="$TMP/watch-lifecycle.log"
# reap <pid>... — TERM, wait, KILL. A scenario teardown must never leak a
# spawn into later scenarios or a later run of this suite: the 02:45Z
# `live=4` L1 failure was exactly such residue (3 strays from the previous
# run + the current loop). kill-without-wait also raced the loop's (previously
# deferred, now prompt) TERM handling.
reap() {
  local p i
  for p in "$@"; do
    [[ -n "$p" ]] || continue
    kill "$p" 2>/dev/null || true
  done
  for p in "$@"; do
    [[ -n "$p" ]] || continue
    for ((i = 0; i < 30; i++)); do kill -0 "$p" 2>/dev/null || break; sleep 0.1; done
    kill -0 "$p" 2>/dev/null && kill -KILL "$p" 2>/dev/null || true
  done
  return 0
}
cleanup() {
  local p q residue
  reap "${PIDS[@]:-}"
  # reap pidfile owners too — $! can be a dead wrapper while the real loop
  # (owner of the pid) runs on as an orphan (fix-round 3 H-1 idiom)
  for p in "$PID_DIR"/*.pid "$STATE"/lane-pulse-watch/*.pid; do
    [[ -f "$p" ]] || continue
    q="$(cat "$p" 2>/dev/null | tr -d ' ')"
    [[ "$q" =~ ^[0-9]+$ ]] && reap "$q"
  done
  # fix-r2 #3: final sweep of every scenario process this suite spawned
  # (pidfile-less orphans included), then a ZERO-residue assertion — a
  # watcher that survives its own teardown (TERM then KILL) is a suite
  # FAILURE even if every scenario assertion above passed.
  for p in $(tracked_live_pids); do
    reap "$p"
  done
  residue="$(tracked_live_pids | wc -l | tr -d ' ')"
  rm -rf "$TMP"
  if [[ "$residue" -ne 0 ]]; then
    printf '[TEST] FAIL: suite teardown residue: %d scenario process(es) still live after TERM+KILL\n' "$residue" >&2
    exit 1
  fi
}
trap cleanup EXIT

REPO="$TMP/repo"
mkdir -p "$REPO"
PID_DIR="$TMP/piddir-loop"
mkdir -p "$PID_DIR"
PID_FILE="$PID_DIR/beat.pid"
BEATS="$TMP/beats.log"
HB_STATE="$TMP/hb-state.json"
STATE="$TMP/state"   # lane-pulse-watch --state-dir
export FAKE_BEATS_LOG="$BEATS"

# The restricted test sandbox does not permit process-table reads. The
# lifecycle library uses `ps -p <pid> -o command=` only to reject recycled
# pidfiles; this shim exposes the command form for PIDs this test owns while
# keeping the production implementation unchanged. Its command contains both
# watcher basenames, so each real singleton claim still validates its holder.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/ps" <<'EOF'
#!/usr/bin/env bash
pid=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p) pid="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null || exit 1
printf 'bash leadv2-single-lead-beat-loop.sh leadv2-lane-pulse-watch.sh bad-loop.sh\n'
EOF
chmod +x "$TMP/bin/ps"
export PATH="$TMP/bin:$PATH"

PIDS=()
printf '[{"task":"dispatch-lc1","status":"running"}]' > "$HB_STATE"

cat > "$TMP/fake-hb.sh" <<'EOF'
#!/usr/bin/env bash
cat "${FAKE_HB_STATE:?}" 2>/dev/null || echo '[]'
EOF
chmod +x "$TMP/fake-hb.sh"

cat > "$TMP/fake-beat.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$(date +%s)" >> "${FAKE_BEATS_LOG:?}"
exit 0
EOF
chmod +x "$TMP/fake-beat.sh"

cat > "$TMP/fake-pulse.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s %s %s\n' "$(date +%s)" "$1" "$2" >> "${FAKE_PULSE_LOG:?}"
exit 0
EOF
chmod +x "$TMP/fake-pulse.sh"
FAKE_PULSE_LOG="$TMP/pulse.log"
export FAKE_PULSE_LOG

run_loop() {  # <script> <owner-pid|""> — arm a beat-loop copy in the background
  local script="$1" owner="$2"
  if [[ -n "$owner" ]]; then
    LEADV2_PROJECT_ROOT="$REPO" \
    LEADV2_SINGLE_LEAD_BEAT_LOOP_PID="$PID_FILE" \
    LEADV2_SINGLE_LEAD_BEAT_LOOP_S=1 \
    LEADV2_SINGLE_LEAD_BEAT_LOOP_MAX_S=120 \
    LEADV2_LANE_HEARTBEAT_BIN="$TMP/fake-hb.sh" \
    LEADV2_PULSE_BEAT_BIN="$TMP/fake-beat.sh" \
    LEADV2_WATCH_LIFECYCLE_LOG="$WL_LOG" \
    LEADV2_WATCHER_OWNER_PID="$owner" \
      bash "$script" >/dev/null 2>&1 &
  else
    LEADV2_PROJECT_ROOT="$REPO" \
    LEADV2_SINGLE_LEAD_BEAT_LOOP_PID="$PID_FILE" \
    LEADV2_SINGLE_LEAD_BEAT_LOOP_S=1 \
    LEADV2_SINGLE_LEAD_BEAT_LOOP_MAX_S=120 \
    LEADV2_LANE_HEARTBEAT_BIN="$TMP/fake-hb.sh" \
    LEADV2_PULSE_BEAT_BIN="$TMP/fake-beat.sh" \
    LEADV2_WATCH_LIFECYCLE_LOG="$WL_LOG" \
      bash "$script" >/dev/null 2>&1 &
  fi
  PIDS+=("$!")
}

beats_n() {
  if [[ -f "$BEATS" ]]; then wc -l < "$BEATS" | tr -d ' '; else printf '0'; fi
}

# PIDs started by THIS harness are the scope. This avoids machine-global
# process enumeration and remains exact for the scenario: every arm goes
# through run_loop/run_watch and enters PIDS before an assertion is made.
tracked_live_pids() {
  local p
  for p in "${PIDS[@]:-}"; do
    [[ -n "$p" ]] && kill -0 "$p" 2>/dev/null && printf '%s\n' "$p"
  done
}
count_scenario() {
  tracked_live_pids | wc -l | tr -d ' '
}

pidfile_alive() {
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

wait_pidfile_gone() {  # <max_s>
  local max="$1" i
  for ((i = 0; i < max * 10; i++)); do
    [[ -f "$PID_FILE" ]] || return 0
    sleep 0.1
  done
  return 1
}

# ── L1: double-spawn -> exactly one live loop, dedup_refused logged ─────────
run_loop "$LOOP" ""
FIRST=$!
for ((i = 0; i < 30; i++)); do pidfile_alive && break; sleep 0.1; done
first_pid="$(cat "$PID_FILE" 2>/dev/null | tr -d ' ')"
b_before="$(beats_n)"
run_loop "$LOOP" ""
SECOND=$!
if wait_exit "$SECOND" 3 \
   && [[ "$(count_scenario "$LOOP")" -eq 1 ]] \
   && [[ "$(cat "$PID_FILE" 2>/dev/null | tr -d ' ')" == "$first_pid" ]] \
   && grep -q "dedup_refused" "$WL_LOG" 2>/dev/null; then
  ok "L1 singleton: second arm refused, exactly 1 live loop, dedup_refused logged"
else
  bad "L1 singleton: live=$(count_scenario "$LOOP") second_exited=$(wait_exit "$SECOND" 0 && echo yes || echo no) log=$(cat "$WL_LOG" 2>/dev/null | tr '\n' ';')"
fi
sleep 2
if pidfile_alive && [[ "$(beats_n)" -gt "$b_before" ]]; then
  ok "L1 beat intact: survivor still beating after the refused arm"
else
  bad "L1 beat intact: beats=$(beats_n) before=$b_before (dedup changed cadence)"
fi
kill "$FIRST" 2>/dev/null || true
reap "${PIDS[@]}"
wait_pidfile_gone 5 || bad "L1 teardown: pidfile not cleaned"
[[ "$(count_scenario "$LOOP")" -eq 0 ]] || bad "L1 teardown: $(count_scenario "$LOOP") scenario loop(s) leaked toward later scenarios"
PIDS=()

# ── L2: concurrent arm storm -> exactly one survivor ────────────────────────
for i in 1 2 3 4 5; do run_loop "$LOOP" ""; done
sleep 3
if [[ "$(count_scenario "$LOOP")" -eq 1 ]] && pidfile_alive; then
  ok "L2 arm storm: 5 concurrent spawns -> exactly 1 survivor holding the pidfile"
else
  bad "L2 arm storm: live=$(count_scenario "$LOOP") pidfile_alive=$(pidfile_alive && echo yes || echo no)"
fi
STORM_PID="$(cat "$PID_FILE" 2>/dev/null | tr -d ' ')"
kill "$STORM_PID" 2>/dev/null || true
reap "${PIDS[@]}"
wait_pidfile_gone 5 || bad "L2 teardown: pidfile not cleaned"
[[ "$(count_scenario "$LOOP")" -eq 0 ]] || bad "L2 teardown: $(count_scenario "$LOOP") scenario loop(s) leaked toward later scenarios"
PIDS=()

# ── L3: owner kill -> self-reap within one interval ─────────────────────────
sleep 300 & OWNER=$!
PIDS+=("$OWNER")
run_loop "$LOOP" "$OWNER"
for ((i = 0; i < 30; i++)); do pidfile_alive && break; sleep 0.1; done
pidfile_alive || bad "L3 preflight: loop never armed"
LOOP_PID="$(cat "$PID_FILE" 2>/dev/null | tr -d ' ')"
kill "$OWNER" 2>/dev/null || true
if wait_exit "$LOOP_PID" 4 && wait_pidfile_gone 2 \
   && grep -q "self_reap" "$WL_LOG" 2>/dev/null; then
  ok "L3 owner self-reap: beat loop exited within one interval of owner death, pidfile cleaned, self_reap logged"
else
  bad "L3 owner self-reap: loop survived owner death (alive=$(kill -0 "$LOOP_PID" 2>/dev/null && echo yes || echo no))"
fi
reap "${PIDS[@]}"
PIDS=()

# ── L4/L5: lane-pulse-watch singleton + owner self-reap ─────────────────────
SIG="1cfe0001"
LANE_DIR="$REPO/docs/leadv2/tasks/dispatch-$SIG"
mkdir -p "$LANE_DIR"
JOURNAL="$LANE_DIR/journal.md"
printf -- '- 2026-09-01T10:00:00Z [decision] worker_spawned by=router model=glm task=%s handle=lc1\n' "$SIG" > "$JOURNAL"

run_watch() {  # <owner-pid|"">
  if [[ -n "$1" ]]; then
    LEADV2_LANE_PULSE_BIN="$TMP/fake-pulse.sh" \
    LEADV2_WATCH_LIFECYCLE_LOG="$WL_LOG" \
    LEADV2_WATCHER_OWNER_PID="$1" \
      bash "$WATCH" --sig "$SIG" --root "$REPO" --state-dir "$STATE" --interval 1 --timeout 120 >/dev/null 2>&1 &
  else
    LEADV2_LANE_PULSE_BIN="$TMP/fake-pulse.sh" \
    LEADV2_WATCH_LIFECYCLE_LOG="$WL_LOG" \
      bash "$WATCH" --sig "$SIG" --root "$REPO" --state-dir "$STATE" --interval 1 --timeout 120 >/dev/null 2>&1 &
  fi
  PIDS+=("$!")
}

WPID_FILE="$STATE/lane-pulse-watch/${SIG}.pid"
watch_alive() {
  [[ -f "$WPID_FILE" ]] || return 1
  local p; p="$(cat "$WPID_FILE" 2>/dev/null | tr -d ' ')"
  [[ "$p" =~ ^[0-9]+$ ]] && kill -0 "$p" 2>/dev/null
}

run_watch ""
W1=$!
for ((i = 0; i < 30; i++)); do watch_alive && break; sleep 0.1; done
w_first="$(cat "$WPID_FILE" 2>/dev/null | tr -d ' ')"
run_watch ""
W2=$!
if wait_exit "$W2" 3 \
   && [[ "$(count_scenario "$WATCH")" -eq 1 ]] \
   && [[ "$(cat "$WPID_FILE" 2>/dev/null | tr -d ' ')" == "$w_first" ]] \
   && grep -q "lane-pulse-watch.*dedup_refused" "$WL_LOG" 2>/dev/null; then
  ok "L4 lane-pulse singleton: second arm refused, 1 live watcher, dedup_refused logged"
else
  bad "L4 lane-pulse singleton: second_exited=$(wait_exit "$W2" 0 && echo yes || echo no) count=$(count_scenario "$WATCH") pf=$(cat "$WPID_FILE" 2>/dev/null) w_first=$w_first log=$(grep lane-pulse-watch "$WL_LOG" 2>/dev/null | tr '\n' ';')"
fi

# L5: owner kill — the LIVE watcher (pidfile owner) must self-reap in <=1 interval
sleep 300 & WOWNER=$!
PIDS+=("$WOWNER")
kill "$w_first" 2>/dev/null || true
for ((i = 0; i < 30; i++)); do watch_alive || break; sleep 0.1; done
run_watch "$WOWNER"
W3=$!
for ((i = 0; i < 30; i++)); do watch_alive && break; sleep 0.1; done
watch_alive || bad "L5 preflight: watcher never armed"
w_pid="$(cat "$WPID_FILE" 2>/dev/null | tr -d ' ')"
kill "$WOWNER" 2>/dev/null || true
if wait_exit "$w_pid" 4 && [[ ! -f "$WPID_FILE" ]] \
   && grep -q "lane-pulse-watch.*self_reap" "$WL_LOG" 2>/dev/null; then
  ok "L5 lane-pulse owner self-reap: exited within one interval of owner death, pidfile cleaned, self_reap logged"
else
  bad "L5 lane-pulse owner self-reap: watcher survived owner death (alive=$(kill -0 "$w_pid" 2>/dev/null && echo yes || echo no))"
fi
reap "${PIDS[@]}"
PIDS=()

# ── L6: 3 spawn/kill cycles -> no residual growth ───────────────────────────
baseline="$(count_scenario "$LOOP")"
for cycle in 1 2 3; do
  run_loop "$LOOP" ""
  CPID=$!
  for ((i = 0; i < 30; i++)); do pidfile_alive && break; sleep 0.1; done
  c_owner="$(cat "$PID_FILE" 2>/dev/null | tr -d ' ')"
  kill "$c_owner" 2>/dev/null || true
  wait_exit "$c_owner" 5 || bad "L6 cycle ${cycle}: loop did not exit after TERM"
  wait_pidfile_gone 5 || bad "L6 cycle ${cycle}: pidfile leaked"
  now="$(count_scenario "$LOOP")"
  if [[ "$now" -gt "$baseline" ]]; then
    bad "L6 no-growth: live copies grew after cycle ${cycle} (baseline=${baseline} now=${now})"
  fi
done
if [[ "$(count_scenario "$LOOP")" -eq "$baseline" ]]; then
  ok "L6 no-growth: 3 spawn/kill cycles, live count back at baseline (${baseline})"
else
  bad "L6 no-growth: final count $(count_scenario "$LOOP") != baseline ${baseline}"
fi
reap "${PIDS[@]}"
PIDS=()

# ── L7: NEGATIVE CONTROL (RUN RED) — claim reverted to blind write ──────────
# Patch a scratch copy: wl_singleton_claim -> the pre-fix blind pidfile write.
# Same L1 double-spawn scenario MUST arm TWO loops — if it still arms one,
# L1/L2 lock nothing. The copy keeps the guarded lib source (its SCRIPT_DIR
# has no lib/, so the canonical fallback or the equally-blind stub applies).
BAD_LOOP="$TMP/bad-loop.sh"
python3 - "$LOOP" "$BAD_LOOP" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
with open(src, encoding='utf-8') as fh:
    text = fh.read()
needle = 'wl_singleton_claim "$PID_FILE"'
repl = 'printf \'%s\\n\' "$$" > "$PID_FILE" 2>/dev/null || true'
if needle not in text:
    print('NEGATIVE-CONTROL-PATCH-FAILED: needle not found', file=sys.stderr)
    sys.exit(1)
with open(dst, 'w', encoding='utf-8') as fh:
    fh.write(text.replace(needle, repl, 1))
PY
patch_rc=$?
rm -f "$PID_FILE"
run_loop "$BAD_LOOP" ""
B1=$!
run_loop "$BAD_LOOP" ""
B2=$!
sleep 2
neg_live="$(count_scenario "$BAD_LOOP")"
kill "$B1" 2>/dev/null || true; kill "$B2" 2>/dev/null || true
reap "${PIDS[@]}"
for ((i = 0; i < 30; i++)); do [[ "$(count_scenario "$BAD_LOOP")" -eq 0 ]] && break; sleep 0.1; done
if [[ $patch_rc -eq 0 && "$neg_live" -eq 2 ]]; then
  ok "L7 negative control RED: blind-write revert arms TWO loops under the L1 scenario (as it must)"
else
  bad "L7 negative control: patched copy armed ${neg_live} loops (patch_rc=$patch_rc) — L1 locks nothing"
fi
PIDS=()

printf 'test-watch-lifecycle: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
