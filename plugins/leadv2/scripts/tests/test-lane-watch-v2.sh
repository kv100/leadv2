#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-lane-watch-v2 leadv2-lane-watch-v2.sh
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
  # A managed-shell sandbox can deny ps(1), in which case the production
  # argv-verification deliberately refuses to kill.  The normal host case
  # asserts the process is gone; the sandbox case records only the harmless
  # pidfile cleanup instead of pretending it exercised a kill.
  if ps -o command= -p "$armed_pid" >/dev/null 2>&1; then
    sleep 1
    if ! kill -0 "$armed_pid" 2>/dev/null && [[ ! -f "$pidfile" ]]; then
      disarm_ok=1
    fi
  elif [[ ! -f "$pidfile" ]]; then
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

# ── WATCHER-LEAK-IS-FAKE-LIVENESS-01: a loop dies with its session ──────────
# SessionEnd --disarm-from-hook never runs on an abnormal death (the dispatch
# supervisors SIGKILL timed-out `claude -p` workers), so the loop must exit
# BY ITSELF: watched root gone, transcript absent after a grace, or
# transcript quiet past SESSION_IDLE_MIN. The transcript fixture is a plain
# file under a fixture PROJECTS_DIR — $HOME/.claude/projects is never
# touched. Session ids here are fake, which is exactly the shape of the
# suite-spawned orphan watchers found in the 2026-09-02 census.
watch_projects() { printf '%s' "$FIXTURE_STATE/projects"; }

arm_loop() { # arm_loop SESSION [extra env via env]
  printf '{"session_id":"%s","cwd":"%s"}' "$1" "$FIXTURE_ROOT" \
    | LEADV2_LANE_WATCH_STATE_DIR="$FIXTURE_STATE" \
      LEADV2_LANE_WATCH_PROJECTS_DIR="$(watch_projects)" \
      LEADV2_LANE_WATCH_POLL_SEC="${LP_POLL:-1}" \
      LEADV2_LANE_WATCH_ABSENT_GRACE_SEC="${LP_GRACE:-2}" \
      LEADV2_LANE_WATCH_SESSION_IDLE_MIN="${LP_IDLE:-9999}" \
      bash "$WATCH_SH" --arm-from-hook
}

# L1: transcript never appears -> loop self-exits after the absent grace.
{
  new_fixture
  mkdir -p "$(watch_projects)"
  arm_loop sessGhost
  sleep 0.3
  pid="$(cat "$FIXTURE_STATE/sessGhost/loop.pid" 2>/dev/null || true)"
  LEAKED_PIDS+=("$pid")
  armed=0; [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && armed=1
  sleep 4
  gone=1; kill -0 "$pid" 2>/dev/null && gone=0
  [[ -d "$FIXTURE_STATE/sessGhost.live" ]] && gone=0
  if [[ "$armed" == 1 && "$gone" == 1 ]]; then
    pass "case L1: loop armed for a session with no transcript self-exits after the grace"
  else
    fail "case L1: armed=$armed gone=$gone pid=$pid"
  fi
}

# L2: transcript gone quiet past SESSION_IDLE_MIN -> loop self-exits. This
# is the SIGKILLed-session case: the transcript simply stops growing.
{
  new_fixture
  mkdir -p "$(watch_projects)"
  : > "$(watch_projects)/sessKilled.jsonl"
  age_touch "$(watch_projects)/sessKilled.jsonl" 40
  LP_IDLE=30 arm_loop sessKilled
  sleep 2
  pid="$(cat "$FIXTURE_STATE/sessKilled/loop.pid" 2>/dev/null || true)"
  LEAKED_PIDS+=("$pid")
  gone=1; [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && gone=0
  if [[ "$gone" == 1 ]]; then
    pass "case L2: loop whose session transcript went quiet past SESSION_IDLE_MIN self-exits"
  else
    fail "case L2: loop still alive with 40m-quiet transcript (idle min=30) pid=$pid"
  fi
}

# L3 (control for L2): a FRESH transcript keeps the loop alive, and the
# beat names worker liveness explicitly instead of process counts.
{
  new_fixture
  mkdir -p "$(watch_projects)"
  : > "$(watch_projects)/sessLive.jsonl"          # touched now = session alive
  make_lane "LANE-L3" 1                           # a lane written 1m ago = worker live
  LP_IDLE=30 arm_loop sessLive
  sleep 2.5
  pid="$(cat "$FIXTURE_STATE/sessLive/loop.pid" 2>/dev/null || true)"
  LEAKED_PIDS+=("$pid")
  alive=0; [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && alive=1
  T_BEAT=0 once sessLive > "$TMPROOT/beat.out" 2>&1 || true
  beat="$(cat "$TMPROOT/beat.out" 2>/dev/null || true)"
  if [[ "$alive" == 1 && "$beat" == *"worker=LIVE"* && "$beat" == *"watcher pid="* ]]; then
    pass "case L3: fresh transcript keeps the loop alive; beat reports worker= verdicts, not process counts"
  else
    fail "case L3: alive=$alive beat=[$beat]"
  fi
}

# L4: watched project root deleted -> loop self-exits even with a fresh
# transcript (the deleted /tmp suite-fixture census class).
{
  new_fixture
  mkdir -p "$(watch_projects)"
  : > "$(watch_projects)/sessRootGone.jsonl"
  arm_loop sessRootGone
  sleep 0.3
  pid="$(cat "$FIXTURE_STATE/sessRootGone/loop.pid" 2>/dev/null || true)"
  LEAKED_PIDS+=("$pid")
  armed=0; [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && armed=1
  rm -rf "$FIXTURE_ROOT"
  sleep 2.5
  gone=1; kill -0 "$pid" 2>/dev/null && gone=0
  if [[ "$armed" == 1 && "$gone" == 1 ]]; then
    pass "case L4: deleted watched project root self-terminates the loop"
  else
    fail "case L4: armed=$armed gone=$gone pid=$pid"
  fi
}

# L5: never two loops for one session — the second registration adopts the
# first (pidfile repointed at it) instead of spawning a duplicate. The
# census found two b1efef2c loops 14 hours apart through exactly this hole.
{
  new_fixture
  mkdir -p "$(watch_projects)"
  # Session ids are process-table global to the watcher. Make this fixture
  # unique across overlapping suite invocations so an unrelated prior run
  # cannot be adopted as the "first" registration.
  dup_session="sessDup$$"
  : > "$(watch_projects)/${dup_session}.jsonl"
  arm_loop "$dup_session"
  sleep 0.3
  first_pid="$(cat "$FIXTURE_STATE/${dup_session}/loop.pid" 2>/dev/null || true)"
  arm_loop "$dup_session"
  sleep 0.3
  pid="$(cat "$FIXTURE_STATE/${dup_session}/loop.pid" 2>/dev/null || true)"
  LEAKED_PIDS+=("$pid")
  # The first arm creates the only pidfile; the second must leave that exact
  # registration intact. The loop itself also owns an exclusive mkdir claim,
  # covering simultaneous direct --loop starts without process-table access.
  if [[ -n "$first_pid" && "$pid" == "$first_pid" ]] && kill -0 "$pid" 2>/dev/null; then
    pass "case L5: double arm -> exactly one live loop survives and the pidfile names it"
  else
    fail "case L5: second arm replaced or lost the original pidfile (first=$first_pid second=$pid)"
  fi
  printf '{"session_id":"%s"}' "$dup_session" | LEADV2_LANE_WATCH_STATE_DIR="$FIXTURE_STATE" bash "$WATCH_SH" --disarm-from-hook
}

# L6: LEADV2_LANE_WATCH_DISABLE=1 makes arming a no-op — the suite escape
# hatch for runs that must spawn zero real watchers.
{
  new_fixture
  mkdir -p "$(watch_projects)"
  LEADV2_LANE_WATCH_DISABLE=1 arm_loop sessDisabled
  sleep 0.3
  if [[ ! -f "$FIXTURE_STATE/sessDisabled/loop.pid" ]] \
     && [[ "$(pgrep -f "leadv2-lane-watch-v2.sh --loop sessDisabled" | wc -l | tr -d ' ')" == "0" ]]; then
    pass "case L6: LEADV2_LANE_WATCH_DISABLE=1 arms nothing"
  else
    fail "case L6: a loop was spawned despite LEADV2_LANE_WATCH_DISABLE=1"
  fi
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
  # REAP_SWEEP scoped to the fixture: an unscoped sweep with this suite's
  # fixture PROJECTS_DIR would kill REAL live sessions' watchers.
  LEADV2_LANE_WATCH_REAP_SWEEP="$FIXTURE_ROOT" \
    LEADV2_LANE_WATCH_STATE_DIR="$FIXTURE_STATE" bash "$WATCH_SH" --reap-stale
  if [[ ! -f "$FIXTURE_STATE/sessDead/loop.pid" && -f "$FIXTURE_STATE/sessAlive/loop.pid" ]]; then
    pass "reap-stale: dead session's pidfile removed, live session's pidfile kept"
  else
    fail "reap-stale: dead=$( [[ -f "$FIXTURE_STATE/sessDead/loop.pid" ]] && echo present || echo gone ) alive=$( [[ -f "$FIXTURE_STATE/sessAlive/loop.pid" ]] && echo present || echo gone )"
  fi
  kill -9 "$alive_pid" 2>/dev/null || true
}

# ── L7/L8: the reap sweep TERM-kills a live loop whose session is provably
# gone and spares one whose session is alive. The pidfile sweep above cannot
# see the census b1efef2c orphan — its pidfile was reaped while the loop
# lived; only the process-table sweep does (WATCHER-LEAK-IS-FAKE-LIVENESS-01).
{
  new_fixture
  mkdir -p "$(watch_projects)"
  : > "$(watch_projects)/sessFresh2.jsonl"
  arm_loop sessOrphan    # no transcript anywhere for this session
  arm_loop sessFresh2    # transcript touched right now
  sleep 1
  orphan_pid="$(cat "$FIXTURE_STATE/sessOrphan/loop.pid" 2>/dev/null || true)"
  fresh_pid="$(cat "$FIXTURE_STATE/sessFresh2/loop.pid" 2>/dev/null || true)"
  LEAKED_PIDS+=("$orphan_pid" "$fresh_pid")
  # grace 0: the just-spawned absent-transcript loop already qualifies; sweep
  # scoped to the fixture so real sessions' watchers are not collateral
  LEADV2_LANE_WATCH_ABSENT_GRACE_SEC=0 \
    LEADV2_LANE_WATCH_REAP_SWEEP="$FIXTURE_ROOT" \
    LEADV2_LANE_WATCH_STATE_DIR="$FIXTURE_STATE" \
    LEADV2_LANE_WATCH_PROJECTS_DIR="$(watch_projects)" \
    bash "$WATCH_SH" --reap-stale
  sleep 1
  orphan_gone=1; kill -0 "$orphan_pid" 2>/dev/null && orphan_gone=0
  fresh_gone=1; kill -0 "$fresh_pid" 2>/dev/null && fresh_gone=0
  if [[ "$orphan_gone" == 1 && "$fresh_gone" == 0 ]]; then
    pass "case L7/L8: reap kills the dead-session loop, spares the live-session loop"
  else
    fail "case L7/L8: orphan_gone=$orphan_gone fresh_gone=$fresh_gone (orphan=$orphan_pid fresh=$fresh_pid)"
  fi
  printf '{"session_id":"sessFresh2"}' | LEADV2_LANE_WATCH_STATE_DIR="$FIXTURE_STATE" bash "$WATCH_SH" --disarm-from-hook
}

# ── L9: an overridden PROJECTS_DIR and no explicit sweep scope = NO sweep.
# The transcript probe cannot see real sessions through an override dir, so
# an unscoped sweep there reads every live session as absent (collateral
# observed live on 2026-09-03: a live lane's watcher was TERM-killed by a
# suite arm). The absent-transcript loop below must SURVIVE this reap.
{
  new_fixture
  mkdir -p "$(watch_projects)"
  # LP_GRACE=60: the loop must not self-exit on its own absent-grace during
  # the case (under load the 1.5s of sleeps below can stretch past a 2s
  # grace and the loop dies of self-termination, not of the sweep) — the
  # assertion is that the REAP spares it, so give it survival headroom.
  LP_GRACE=60 arm_loop sessNoSweep    # no transcript, but probe dir is overridden
  sleep 0.5
  nosweep_pid="$(cat "$FIXTURE_STATE/sessNoSweep/loop.pid" 2>/dev/null || true)"
  LEAKED_PIDS+=("$nosweep_pid")
  LEADV2_LANE_WATCH_ABSENT_GRACE_SEC=0 \
    LEADV2_LANE_WATCH_STATE_DIR="$FIXTURE_STATE" \
    LEADV2_LANE_WATCH_PROJECTS_DIR="$(watch_projects)" \
    bash "$WATCH_SH" --reap-stale
  sleep 1
  survived=0; kill -0 "$nosweep_pid" 2>/dev/null && survived=1
  if [[ "$survived" == 1 ]]; then
    pass "case L9: overridden probe dir without REAP_SWEEP runs no sweep"
  else
    fail "case L9: unscoped sweep ran despite overridden PROJECTS_DIR"
  fi
  kill -9 "$nosweep_pid" 2>/dev/null || true
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

# ── round-4 regression (reviewer glm [High]): runner bookkeeping is NOT
#    worker output. The measured case: 53 min of silence on
#    260901-184335-PHASE-GATE-IS-INVERTED-01-7ddb never reported because
#    round 3 counted every top-level file except broker.json/state.json, and
#    progress.log/meta.yaml are written by the RUNNER (heartbeat, status
#    flips) even while the model is hung. Fixture: progress.log + meta.yaml
#    touched NOW, journal.jsonl (the model's stream-json transcript) 60m old,
#    worktree 30m → prov_age ≥ 30 → LANE-STALL fires.
{
  new_fixture
  make_lane "LANE-R8" 30
  d="$(make_rundir glm LANE-R8 61)"
  printf 'worker output\n' > "$d/journal.jsonl"
  age_touch "$d/journal.jsonl" 60                 # model went quiet 60m ago
  printf 'heartbeat\n' > "$d/progress.log"        # runner heartbeat NOW
  age_touch "$d/progress.log" 0
  printf 'status: running\n' > "$d/meta.yaml"     # runner status flip NOW
  age_touch "$d/meta.yaml" 0
  out="$(once sessR8)"
  if [[ "$out" == *"LANE-STALL: LANE-R8"* ]]; then
    pass "case r4-1: fresh runner bookkeeping (progress.log/meta.yaml) does not mask a 60m-quiet model stream"
  else
    fail "case r4-1: expected REPORT (stream 60m quiet, bookkeeping now), got out=[$out]"
  fi
}

# ── round-4 positive: the same dir with a FRESH journal.jsonl ⇒ silence.
#    The model is the thing that must be fresh; when it is, the runner's
#    timers are irrelevant and the both-signal rule suppresses the stall.
{
  new_fixture
  make_lane "LANE-R9" 30
  d="$(make_rundir glm LANE-R9 30)"
  printf 'worker output\n' > "$d/journal.jsonl"
  age_touch "$d/journal.jsonl" 1                  # model produced 1m ago
  printf 'heartbeat\n' > "$d/progress.log"        # runner bookkeeping NOW
  age_touch "$d/progress.log" 0
  out="$(once sessR9)"
  if [[ "$out" != *"LANE-STALL"* ]]; then
    pass "case r4-2: fresh model stream suppresses the stall regardless of runner bookkeeping"
  else
    fail "case r4-2: expected silence (journal 1m old), got out=[$out]"
  fi
}

# ── round-4 codex arm: top-level runner bookkeeping fresh, jobs/* quiet
#    ⇒ stall fires; worker job output is the only counted thing.
{
  new_fixture
  make_lane "LANE-R10" 30
  d="$(make_rundir codex LANE-R10 61)"
  mkdir -p "$d/jobs"
  printf '{}\n' > "$d/jobs/task-x.json"
  age_touch "$d/jobs/task-x.json" 60              # worker quiet 60m
  printf 'bookkeeping\n' > "$d/state.json"        # runner rewrite NOW
  age_touch "$d/state.json" 0
  out="$(once sessR10)"
  if [[ "$out" == *"LANE-STALL: LANE-R10"* ]]; then
    pass "case r4-3: codex stall fires on quiet jobs/ despite fresh top-level state.json"
  else
    fail "case r4-3: expected REPORT (jobs/ 60m quiet, state.json now), got out=[$out]"
  fi
}

# ── round-4 claude arm: claude-runs dirs hold ONLY runner bookkeeping
#    (.finalized/.outcome/meta.yaml/pid — probed 2026-09-01), so nothing in
#    the dir may ever read as model output; a >20m-old claude dir with a
#    stale worktree must stall (worktree mtime is that arm's only signal).
{
  new_fixture
  make_lane "LANE-R11" 30
  d="$(make_rundir claude LANE-R11 30)"
  printf 'bookkeeping\n' > "$d/meta.yaml"         # runner status flip NOW
  age_touch "$d/meta.yaml" 0
  printf 'done\n' > "$d/.outcome"
  age_touch "$d/.outcome" 0
  out="$(once sessR11)"
  if [[ "$out" == *"LANE-STALL: LANE-R11"* ]]; then
    pass "case r4-4: claude-arm runner bookkeeping never counts as output; worktree-only stall fires"
  else
    fail "case r4-4: expected REPORT (claude dir bookkeeping now, worktree 30m), got out=[$out]"
  fi
}

# ── summary ──────────────────────────────────────────────────────────────────
printf -- '\n[TEST] lane-watch-v2: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
for e in "${ERRORS[@]:-}"; do printf -- '[TEST] %s\n' "$e"; done
(( FAIL == 0 ))
