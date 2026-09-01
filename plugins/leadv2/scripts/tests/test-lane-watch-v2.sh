#!/usr/bin/env bash
# tests/test-lane-watch-v2.sh — ONE-LANE-WATCH-01 fixture suite.
#
# Fully isolated: every fixture lives under a throwaway mktemp -d root, and
# every env override this script relies on (LEADV2_LANE_WATCH_STATE_DIR,
# LEADV2_LANE_WATCH_RUN_ROOTS, LEADV2_LANE_WATCH_WORKTREES,
# LEADV2_LANE_WATCH_LANES, LANE_STALL_MIN, LANE_GRACE_MIN, LANE_BEAT_MIN,
# LEADV2_LANE_WATCH_POLL_SEC) points at fixture paths or shrunk thresholds.
# Never a real session, never a real worktree, never a real dispatch.
#
# Run: bash plugins/leadv2/scripts/tests/test-lane-watch-v2.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WATCH_SH="${PLUGIN_DIR}/scripts/leadv2-lane-watch-v2.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMPROOT=""
LEAKED_PIDS=()
cleanup() {
  local p
  for p in "${LEAKED_PIDS[@]:-}"; do
    [ -n "$p" ] && kill -9 "$p" 2>/dev/null
  done
  [[ -n "$TMPROOT" && -d "$TMPROOT" ]] && rm -rf "$TMPROOT"
  return 0
}
trap cleanup EXIT

# age_touch FILE MINUTES_AGO — set FILE's mtime MINUTES_AGO in the past.
age_touch() {
  touch -t "$(date -v-"${2}"M +%Y%m%d%H%M.%S)" "$1"
}

# set_birth PATH MINUTES_AGO — set PATH's st_birthtime MINUTES_AGO in the
# past. `touch` cannot do this on macOS (it only sets mtime); SetFile -d can
# — probed 2026-09-01: after `SetFile -d $(date -v-40M ...)` on a fresh dir,
# `stat -f "birth=%B mtime=%m"` reported birth=now-2400 mtime=now. This is
# the whole point of the round-2 acceptance-1 fixture (run dir born 40 minutes
# ago, touched one second ago): a hung worker's run dir gets mtime-pinged by
# its runner for hours after the worker died.
set_birth() {
  if [ ! -x /usr/bin/SetFile ]; then
    fail "set_birth: /usr/bin/SetFile not available (macOS CLT required for birth-time fixtures)"
    return 1
  fi
  /usr/bin/SetFile -d "$(date -v-"${2}"M '+%m/%d/%Y %H:%M:%S')" "$1"
}

# new_fixture — fresh project + worktrees root + state dir + run-cache root
# + codex state root. Sets globals: FIXTURE_ROOT, FIXTURE_WT, FIXTURE_STATE,
# FIXTURE_CACHE, FIXTURE_CODEX.
new_fixture() {
  TMPROOT="$(mktemp -d)"
  FIXTURE_ROOT="$TMPROOT/project"
  FIXTURE_WT="$FIXTURE_ROOT/.claude/worktrees"
  FIXTURE_STATE="$TMPROOT/state"
  FIXTURE_CACHE="$TMPROOT/cache"
  FIXTURE_CODEX="$TMPROOT/codex-state"
  mkdir -p "$FIXTURE_ROOT/docs/leadv2" "$FIXTURE_WT" "$FIXTURE_STATE" "$FIXTURE_CACHE" "$FIXTURE_CODEX"
}

# make_lane LANE [AGE_MIN] — a worktree dir with a `.git` FILE (not dir, the
# real shape of a git worktree checkout) and one work file aged AGE_MIN
# minutes (default: fresh / just touched).
make_lane() {
  local lane="$1" age="${2:-0}"
  mkdir -p "$FIXTURE_WT/$lane"
  : > "$FIXTURE_WT/$lane/.git"
  printf 'work\n' > "$FIXTURE_WT/$lane/file.txt"
  [ "$age" -gt 0 ] && age_touch "$FIXTURE_WT/$lane/file.txt" "$age"
}

# make_rundir ARM LANE BIRTH_MIN [NAME] — provider run directory born
# BIRTH_MIN minutes ago, in the ARM's state root (glm|freepool under the
# fixture cache, codex under the fixture codex-state root). Prints its path.
make_rundir() {
  local arm="$1" lane="$2" birth="$3" d
  case "$arm" in
    codex) d="$FIXTURE_CODEX/${lane}-14806a70f0cacf75" ;;
    *)     d="$FIXTURE_CACHE/$arm-runs/dispatch-$lane-abc" ;;
  esac
  mkdir -p "$d" || return 1
  set_birth "$d" "$birth" || return 1
  printf '%s' "$d"
}

# once SESSION [ROOT] — run one check cycle with the fixture env wired in.
once() {
  local session="$1" root="${2:-$FIXTURE_ROOT}"
  LEADV2_LANE_WATCH_STATE_DIR="$FIXTURE_STATE" \
  LEADV2_LANE_WATCH_RUN_ROOTS="$FIXTURE_CACHE" \
  LEADV2_LANE_WATCH_CODEX_STATE="$FIXTURE_CODEX" \
  LANE_STALL_MIN="${T_STALL:-20}" \
  LANE_GRACE_MIN="${T_GRACE:-15}" \
  LANE_BEAT_MIN="${T_BEAT:-12}" \
    bash "$WATCH_SH" --once "$session" "$root"
}

# write_tasks STATUS_COUNT_PAIRS... — docs/tasks.yaml with rows
# write_tasks queued:1 done:1 -> 1 queued row, 1 done row.
write_tasks() {
  {
    printf 'tasks:\n'
    local pair name n i
    for pair in "$@"; do
      name="${pair%%:*}"; n="${pair##*:}"
      for (( i=0; i<n; i++ )); do
        printf -- '- id: %s-%s\n  status: %s\n  title: row\n' "$name" "$i" "$name"
      done
    done
  } > "$FIXTURE_ROOT/docs/tasks.yaml"
}

# ── case 1: stalled worktree reported once, not repeatedly ──────────────────
{
  new_fixture
  make_lane "LANE-A" 25
  out1="$(once sessA)"
  out2="$(once sessA)"
  if [[ "$out1" == *"LANE-STALL: LANE-A"* && "$out2" != *"LANE-STALL"* ]]; then
    pass "case 1: stalled lane reported once, not on the following cycle"
  else
    fail "case 1: expected stall then silence, got out1=[$out1] out2=[$out2]"
  fi
}

# ── case 2: changing worktree never reported (false-alarm guard) ────────────
{
  new_fixture
  make_lane "LANE-B" 0
  out1="$(once sessB)"
  printf 'more work\n' > "$FIXTURE_WT/LANE-B/file2.txt"
  out2="$(once sessB)"
  if [[ "$out1" != *"LANE-STALL"* && "$out2" != *"LANE-STALL"* ]]; then
    pass "case 2: continuously-written lane never reported"
  else
    fail "case 2: expected no stall ever, got out1=[$out1] out2=[$out2]"
  fi
}

# ── case 3: worker process alive, worktree frozen -> still reported (hang) ──
{
  new_fixture
  make_lane "LANE-C" 25
  sleep 30 &
  worker_pid=$!
  LEAKED_PIDS+=("$worker_pid")
  out="$(once sessC)"
  kill -9 "$worker_pid" 2>/dev/null
  if [[ "$out" == *"LANE-STALL: LANE-C"* ]]; then
    pass "case 3: alive-but-hung worker (frozen worktree) still reported"
  else
    fail "case 3: expected LANE-STALL despite live worker pid, got out=[$out]"
  fi
}

# ── case 4: codex arm watched identically — its state lives in a DIFFERENT
#    root than the *-runs cache, and the round-1 "*-runs" glob matched
#    nothing there: probed 2026-09-01, a codex lane's state dir is
#    ~/.claude/plugins/data/codex-openai-codex/state/<LANE>-<hash> (e.g.
#    TESTS-POLLUTE-REAL-JOURNAL-01-14806a70f0cacf75), so a codex lane had no
#    dispatch age and was "stalled" seconds after a healthy dispatch
#    (measured on TESTS-POLLUTE-REAL-JOURNAL-01: alarm 2 min after dispatch).
{
  new_fixture
  make_lane "LANE-D" 25
  make_rundir codex LANE-D 40 >/dev/null          # dispatched 40m ago -> past grace
  out="$(once sessD)"
  if [[ "$out" == *"LANE-STALL: LANE-D"* ]]; then
    pass "case 4a: codex-arm lane (codex state root, not *-runs) reported when stale"
  else
    fail "case 4a: codex lane not reported, got out=[$out]"
  fi
}
{
  new_fixture
  make_lane "LANE-E" 999                          # ancient worktree
  make_rundir codex LANE-E 1 >/dev/null           # dispatched 1m ago -> inside grace
  out="$(once sessE)"
  if [[ "$out" != *"LANE-STALL"* ]]; then
    pass "case 4b: codex lane dispatched 1m ago is NOT reported (round-2 acceptance 2)"
  else
    fail "case 4b: codex grace did not suppress, got out=[$out]"
  fi
}

# ── case r3-1: claude-arm lane inside grace must NOT be reported stalled ────
#    Round-2 review [Critical] 1: lane_dirs enumerated only glm-runs and
#    freepool-runs, dropping claude-runs (and kimi-runs) from the arm
#    enumeration entirely. A claude-arm lane then matched nothing -> both
#    d_age and prov_age returned 999999 -> no grace, no output suppression,
#    reported stalled seconds after a healthy dispatch.
{
  new_fixture
  make_lane "LANE-CLAUDE" 999                     # ancient worktree
  make_rundir claude LANE-CLAUDE 1 >/dev/null      # dispatched 1m ago -> inside grace
  out="$(once sessClaude)"
  if [[ "$out" != *"LANE-STALL"* ]]; then
    pass "case r3-1: claude-arm lane dispatched 1m ago is NOT reported (grace applies)"
  else
    fail "case r3-1: claude-arm grace did not suppress, got out=[$out]"
  fi
}

# ── case r3-2: codex worker output lives in jobs/, not top-level bookkeeping.
#    Round-2 review [High] H1: _lw_provider_output_age_min only looked at
#    plain files directly inside the run dir, so codex's real output
#    (jobs/task-*.json/.log) was invisible and stale top-level bookkeeping
#    (broker.json, state.json) was miscounted as "output" if touched.
{
  new_fixture
  make_lane "LANE-CX" 30
  d="$(make_rundir codex LANE-CX 30)"              # born 30m ago
  printf '{}' > "$d/broker.json"
  age_touch "$d/broker.json" 30                    # runner bookkeeping, stale
  printf '{}' > "$d/state.json"
  age_touch "$d/state.json" 1                      # runner bookkeeping touched 1m ago
  mkdir -p "$d/jobs"
  printf '{}' > "$d/jobs/task-abc.json"
  age_touch "$d/jobs/task-abc.json" 30              # worker output, still 30m old
  out="$(once sessCX)"
  if [[ "$out" == *"LANE-STALL: LANE-CX"* ]]; then
    pass "case r3-2a: fresh state.json (bookkeeping) does not suppress a stall"
  else
    fail "case r3-2a: expected stall despite fresh bookkeeping, got out=[$out]"
  fi

  new_fixture
  make_lane "LANE-CY" 30
  d="$(make_rundir codex LANE-CY 30)"
  printf '{}' > "$d/broker.json"
  age_touch "$d/broker.json" 30
  mkdir -p "$d/jobs"
  printf '{}' > "$d/jobs/task-fresh.json"
  age_touch "$d/jobs/task-fresh.json" 1             # real worker output, 1m ago
  out="$(once sessCY)"
  if [[ "$out" != *"LANE-STALL"* ]]; then
    pass "case r3-2b: fresh jobs/ output suppresses the stall (codex worker output is read)"
  else
    fail "case r3-2b: expected silence, jobs/ output was ignored, got out=[$out]"
  fi
}

# ── case 5: dispatched within grace, whatever the worktree age ──────────────
{
  new_fixture
  make_lane "LANE-F" 999          # ancient worktree
  mkdir -p "$FIXTURE_CACHE/glm-runs/LANE-F-run1"
  age_touch "$FIXTURE_CACHE/glm-runs/LANE-F-run1" 2   # dispatched 2m ago
  out="$(once sessF)"
  if [[ "$out" != *"LANE-STALL"* ]]; then
    pass "case 5: freshly re-dispatched lane not reported despite ancient worktree"
  else
    fail "case 5: grace period did not suppress, got out=[$out]"
  fi
}

# ── case 6: heartbeat fires on schedule, names every active lane + age ──────
{
  new_fixture
  make_lane "LANE-G" 3
  make_lane "LANE-H" 7
  out1="$(once sessG)"
  out2="$(T_BEAT=12 once sessG)"   # same cycle window -> no second beat
  if [[ "$out1" == *"LANE-BEAT:"* && "$out1" == *"LANE-G:"* && "$out1" == *"LANE-H:"* && "$out2" != *"LANE-BEAT"* ]]; then
    pass "case 6a: first cycle beats and names every lane; immediate re-check does not re-beat"
  else
    fail "case 6a: out1=[$out1] out2=[$out2]"
  fi
  # force the beat file stale, then confirm a third cycle beats again
  printf '0' > "$FIXTURE_STATE/sessG/last_beat"
  out3="$(once sessG)"
  if [[ "$out3" == *"LANE-BEAT:"* ]]; then
    pass "case 6b: heartbeat fires again once its interval has elapsed"
  else
    fail "case 6b: expected a beat after the interval elapsed, got out3=[$out3]"
  fi
}

# ── case 7: two concurrent sessions watch independently, no duplicate reports ──
{
  new_fixture
  make_lane "LANE-I" 25
  out_s1="$(once sess1)"
  out_s2="$(once sess2)"
  out_s1_again="$(once sess1)"
  out_s2_again="$(once sess2)"
  if [[ "$out_s1" == *"LANE-STALL: LANE-I"* && "$out_s2" == *"LANE-STALL: LANE-I"* \
        && "$out_s1_again" != *"LANE-STALL"* && "$out_s2_again" != *"LANE-STALL"* ]]; then
    pass "case 7: each session reports the same stalled lane exactly once, independently"
  else
    fail "case 7: out_s1=[$out_s1] out_s2=[$out_s2] again1=[$out_s1_again] again2=[$out_s2_again]"
  fi
}

# ── case 8: arm on session start / disarm on session end, no orphan process ──
{
  new_fixture
  PAYLOAD_ARM="$(printf '{"session_id":"sessArm","cwd":"%s"}' "$FIXTURE_ROOT")"
  out_arm="$(printf '%s' "$PAYLOAD_ARM" | LEADV2_LANE_WATCH_STATE_DIR="$FIXTURE_STATE" LEADV2_LANE_WATCH_POLL_SEC=1 bash "$WATCH_SH" --arm-from-hook)"
  sleep 0.3
  pidfile="$FIXTURE_STATE/sessArm/loop.pid"
  armed_pid="$(cat "$pidfile" 2>/dev/null || true)"
  arm_ok=0
  if [[ -n "$armed_pid" ]] && kill -0 "$armed_pid" 2>/dev/null; then
    arm_ok=1
  fi
  LEAKED_PIDS+=("$armed_pid")

  PAYLOAD_DISARM='{"session_id":"sessArm"}'
  printf '%s' "$PAYLOAD_DISARM" | LEADV2_LANE_WATCH_STATE_DIR="$FIXTURE_STATE" bash "$WATCH_SH" --disarm-from-hook
  sleep 0.3
  disarm_ok=0
  if ! kill -0 "$armed_pid" 2>/dev/null && [[ ! -f "$pidfile" ]]; then
    disarm_ok=1
  fi

  if [[ "$arm_ok" == 1 && "$disarm_ok" == 1 ]]; then
    pass "case 8a: arm starts a live loop, disarm stops it and removes the pidfile"
  else
    fail "case 8a: arm_ok=$arm_ok disarm_ok=$disarm_ok armed_pid=$armed_pid"
  fi

  # Safety: disarm must NEVER kill a process it did not identify as its own
  # loop by argv, even if a pidfile happens to point at one (PID reuse /
  # foreign lock) — this is the exact incident class named in the mission
  # ("the lead killed his own watchdog because its filter matched the lane
  # name inside its own command line").
  sleep 60 &
  foreign_pid=$!
  LEAKED_PIDS+=("$foreign_pid")
  mkdir -p "$FIXTURE_STATE/sessForeign"
  printf '%s' "$foreign_pid" > "$FIXTURE_STATE/sessForeign/loop.pid"
  printf '{"session_id":"sessForeign"}' | LEADV2_LANE_WATCH_STATE_DIR="$FIXTURE_STATE" bash "$WATCH_SH" --disarm-from-hook
  if kill -0 "$foreign_pid" 2>/dev/null; then
    pass "case 8b: disarm never kills a process it cannot identify as its own loop by argv"
  else
    fail "case 8b: an unrelated process was killed by disarm — argv identification is not safe"
  fi
  kill -9 "$foreign_pid" 2>/dev/null || true
}

# ── reap-stale: dead sessions' pidfiles are cleared, live ones are untouched ──
{
  new_fixture
  mkdir -p "$FIXTURE_STATE/sessDead" "$FIXTURE_STATE/sessAlive"
  printf '999999' > "$FIXTURE_STATE/sessDead/loop.pid"   # near-certainly not a live pid
  sleep 30 &
  alive_pid=$!
  LEAKED_PIDS+=("$alive_pid")
  printf '%s' "$alive_pid" > "$FIXTURE_STATE/sessAlive/loop.pid"
  LEADV2_LANE_WATCH_STATE_DIR="$FIXTURE_STATE" bash "$WATCH_SH" --reap-stale
  if [[ ! -f "$FIXTURE_STATE/sessDead/loop.pid" && -f "$FIXTURE_STATE/sessAlive/loop.pid" ]]; then
    pass "reap-stale: dead session's pidfile removed, live session's pidfile kept"
  else
    fail "reap-stale: dead=$( [[ -f "$FIXTURE_STATE/sessDead/loop.pid" ]] && echo present || echo gone ) alive=$( [[ -f "$FIXTURE_STATE/sessAlive/loop.pid" ]] && echo present || echo gone )"
  fi
  kill -9 "$alive_pid" 2>/dev/null || true
}

# ── EXTRA_SUITE_MAP selection proof: --scope changed must select this suite ──
{
  ROOT="$(cd "${PLUGIN_DIR}/../.." && pwd)"
  if grep -q 'leadv2-lane-watch-v2' "${ROOT}/tests/run-all.sh" 2>/dev/null; then
    pass "run-all.sh: EXTRA_SUITE_MAP carries a row for leadv2-lane-watch-v2"
  else
    fail "run-all.sh: no EXTRA_SUITE_MAP row found for leadv2-lane-watch-v2"
  fi
}

# ── round-2 acceptance 1: run dir BORN 40m ago, TOUCHED 1s ago, worktree
#    quiet 30m ⇒ REPORTED. Round 1 read the grace window from mtime, and a
#    runner mtime-pings its run dir for hours after the worker died, so the
#    grace never expired and this exact case was silent (lead measured a lane
#    23 min past STALE_MIN before a human noticed via the heartbeat).
#    touch sets only mtime — birth stays at mkdir — so the fixture needs
#    SetFile -d to backdate the birth (see set_birth).
{
  new_fixture
  make_lane "LANE-R1" 30
  d="$(make_rundir glm LANE-R1 40)"
  touch "$d"                                      # mtime NOW, birth still 40m ago
  out="$(once sessR1)"
  if [[ "$out" == *"LANE-STALL: LANE-R1"* ]]; then
    pass "case r2-1: mtime-pinged run dir does not keep grace alive (birth-based dispatch age)"
  else
    fail "case r2-1: expected REPORT (born 40m, touched 1s, worktree 30m), got out=[$out]"
  fi
}

# ── round-2 acceptance 3: worktree quiet 30m, provider dir producing 1m ago
#    ⇒ NOT reported. A worker reading and planning writes its provider run
#    dir while touching no worktree file — reporting that is the false alarm
#    that makes a watcher get ignored.
{
  new_fixture
  make_lane "LANE-R3" 30
  d="$(make_rundir glm LANE-R3 30)"
  printf 'worker output\n' > "$d/journal.jsonl"
  age_touch "$d/journal.jsonl" 1                  # produced 1m ago
  out="$(once sessR3)"
  if [[ "$out" != *"LANE-STALL"* ]]; then
    pass "case r2-3: fresh provider output suppresses the stall (both-signal rule)"
  else
    fail "case r2-3: expected silence (provider produced 1m ago), got out=[$out]"
  fi
}

# ── round-2 acceptance 4: both signals quiet 30m ⇒ reported, with BOTH
#    numbers in the text — that is what makes it actionable.
{
  new_fixture
  make_lane "LANE-R4" 30
  make_rundir glm LANE-R4 30 >/dev/null           # born 30m, empty -> output = birth
  out="$(once sessR4)"
  if [[ "$out" == *"LANE-STALL: LANE-R4 — worktree untouched 30m, provider output 30m"* ]]; then
    pass "case r2-4: both-quiet stall reported with both numbers"
  else
    fail "case r2-4: expected both-numbers stall text, got out=[$out]"
  fi
}

# ── round-2 acceptance 5/6 + dedup: zero live lanes + open tasks ⇒ LANE-IDLE;
#    no open tasks ⇒ silent; count change ⇒ re-report; live lane ⇒ clear.
{
  new_fixture
  write_tasks queued:1
  out1="$(once sessR5)"
  out2="$(once sessR5)"
  write_tasks queued:2
  out3="$(once sessR5)"
  if [[ "$out1" == *"LANE-IDLE: no live lane, 1 task(s) queued"* \
        && "$out2" != *"LANE-IDLE"* \
        && "$out3" == *"LANE-IDLE: no live lane, 2 task(s) queued"* ]]; then
    pass "case r2-5: LANE-IDLE emitted once per queued-count, re-emitted when it changes"
  else
    fail "case r2-5: out1=[$out1] out2=[$out2] out3=[$out3]"
  fi

  write_tasks done:2
  out4="$(once sessR5)"
  if [[ "$out4" != *"LANE-IDLE"* ]]; then
    pass "case r2-6: zero live lanes but zero open tasks stays silent"
  else
    fail "case r2-6: LANE-IDLE fired with no open rows, got out4=[$out4]"
  fi

  new_fixture
  write_tasks queued:1
  make_lane "LANE-R7" 3                           # a live lane is working
  out="$(once sessR7)"
  if [[ "$out" != *"LANE-IDLE"* ]]; then
    pass "case r2-7: queued work plus a live lane stays silent"
  else
    fail "case r2-7: LANE-IDLE fired despite a live lane, got out=[$out]"
  fi
}

# ── summary ──────────────────────────────────────────────────────────────────
printf -- '\n[TEST] lane-watch-v2: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
for e in "${ERRORS[@]:-}"; do printf -- '[TEST] %s\n' "$e"; done
(( FAIL == 0 ))
