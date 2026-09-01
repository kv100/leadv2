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

# new_fixture — fresh project + worktrees root + state dir + run-cache root.
# Sets globals: FIXTURE_ROOT, FIXTURE_WT, FIXTURE_STATE, FIXTURE_CACHE.
new_fixture() {
  TMPROOT="$(mktemp -d)"
  FIXTURE_ROOT="$TMPROOT/project"
  FIXTURE_WT="$FIXTURE_ROOT/.claude/worktrees"
  FIXTURE_STATE="$TMPROOT/state"
  FIXTURE_CACHE="$TMPROOT/cache"
  mkdir -p "$FIXTURE_ROOT/docs/leadv2" "$FIXTURE_WT" "$FIXTURE_STATE" "$FIXTURE_CACHE"
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

# once SESSION [ROOT] — run one check cycle with the fixture env wired in.
once() {
  local session="$1" root="${2:-$FIXTURE_ROOT}"
  LEADV2_LANE_WATCH_STATE_DIR="$FIXTURE_STATE" \
  LEADV2_LANE_WATCH_RUN_ROOTS="$FIXTURE_CACHE" \
  LANE_STALL_MIN="${T_STALL:-20}" \
  LANE_GRACE_MIN="${T_GRACE:-15}" \
  LANE_BEAT_MIN="${T_BEAT:-12}" \
    bash "$WATCH_SH" --once "$session" "$root"
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

# ── case 4: non-GLM (codex) arm watched identically — no provider special-case ──
{
  new_fixture
  make_lane "LANE-D" 25
  mkdir -p "$FIXTURE_CACHE/codex-runs/dispatch-LANE-D-abc"
  age_touch "$FIXTURE_CACHE/codex-runs/dispatch-LANE-D-abc" 25   # stale dispatch too -> past grace
  out="$(once sessD)"
  if [[ "$out" == *"LANE-STALL: LANE-D"* ]]; then
    pass "case 4a: codex-arm lane (codex-runs, not glm-runs) reported when stale"
  else
    fail "case 4a: codex lane not reported, got out=[$out]"
  fi
}
{
  new_fixture
  make_lane "LANE-E" 25
  mkdir -p "$FIXTURE_CACHE/codex-runs/dispatch-LANE-E-abc"
  age_touch "$FIXTURE_CACHE/codex-runs/dispatch-LANE-E-abc" 5    # fresh dispatch -> inside grace
  out="$(once sessE)"
  if [[ "$out" != *"LANE-STALL"* ]]; then
    pass "case 4b: codex-arm lane honours the grace period identically to a glm-arm lane"
  else
    fail "case 4b: expected grace to suppress, got out=[$out]"
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

# ── summary ──────────────────────────────────────────────────────────────────
printf -- '\n[TEST] lane-watch-v2: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
for e in "${ERRORS[@]:-}"; do printf -- '[TEST] %s\n' "$e"; done
(( FAIL == 0 ))
