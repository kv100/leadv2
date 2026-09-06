#!/usr/bin/env bash
# run-all-triggers: leadv2-lane-liveness.sh
# test-lane-verdict-pid-is-a-worker.sh — D2-M2-EPERM-IS-READ-AS-DEAD-01
# (D2-SINGLE-LIVENESS-VERDICT brief.md M2, mutation-control pairs C1/C3).
#
# C1 (mandatory, brief #14): a recorded pid that is alive and birth-matching
#   but whose `ps -o args=` is an INTERACTIVE claude session (no -p/--print)
#   must not be reported alive — kill(0)==0 only proves SOME process owns
#   the pid, not that it is this lane's worker. Fixture: a real background
#   process invoked as "<repo>/claude 600" (symlink to sleep — ps args=
#   shows the invoked path, matching the "claude" substring the subject
#   scans for, same trick as test-lanes-snapshot.sh Test 3b) with its
#   REAL recorded ps lstart= as pid_birth, so pid_state reaches the kind
#   check instead of degrading to alive_unverified on a missing birth.
#
# C3: an EPERM pid (1 — kill(1,0) raises EPERM for a non-root caller on both
#   macOS and Linux, the same fixture leadv2-orphan-reaper.sh's own comment
#   and test-stale-sweeper-wiring.sh use) must report alive, never dead —
#   EPERM proves the pid EXISTS, owned by someone else, not that it is gone.
#
# Both against the REAL leadv2-lane-liveness.sh binary (--project-root +
# --lane + --json), never a helper called in isolation, per lane-mission.md
# acceptance #1 ("real production function under claim REAL").
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HELPER="${PLUGIN_DIR}/scripts/leadv2-lane-liveness.sh"
STATE_PATH_SH="${PLUGIN_DIR}/scripts/leadv2-state-path.sh"

PASS=0; FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1"; }

json_get() {
  python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
print($1)
"
}

CLEANUP_PIDS=()
CLEANUP_DIRS=()
cleanup() {
  local p
  for p in "${CLEANUP_PIDS[@]:-}"; do
    [[ -n "$p" ]] && kill "$p" 2>/dev/null || true
  done
  for p in "${CLEANUP_PIDS[@]:-}"; do
    [[ -n "$p" ]] && wait "$p" 2>/dev/null || true
  done
  local d
  for d in "${CLEANUP_DIRS[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
  done
}
trap cleanup EXIT

repo="$(lv2_mktemp_dir "lv-pid-worker-repo")"
state="$(lv2_mktemp_dir "lv-pid-worker-state")"
CLEANUP_DIRS+=("$repo" "$state")
(cd "$repo" && git init -q)
lv2_assert_scratch_repo "$repo"
mkdir -p "$repo/docs/leadv2" "$repo/docs/handoff"
active="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" PROJECT_ROOT="$repo" bash "$STATE_PATH_SH" active.yaml)"
mkdir -p "$(dirname "$active")"

_norm_lstart() {
  # Same normalizer pid_state itself applies (leadv2-lane-liveness.sh:_norm_birth).
  python3 -c "import sys; print(' '.join(sys.argv[1].split()))" "$1"
}

section() { printf -- '\n== %s ==\n' "$1"; }

# ── C1: alive + birth-matching + interactive-shaped ps args= -> not alive ──
section "C1 — process-kind mismatch (interactive claude, no -p/--print)"
mkdir -p "$repo/docs/handoff/PID-KIND-MISMATCH"
printf 'old worker output\n' > "$repo/docs/handoff/PID-KIND-MISMATCH/session.log"
ln -sf "$(command -v sleep)" "$repo/claude"
"$repo/claude" 600 &
C1_PID=$!
CLEANUP_PIDS+=("$C1_PID")
sleep 0.3
c1_args="$(ps -p "$C1_PID" -o args= 2>/dev/null)"
c1_birth_raw="$(ps -p "$C1_PID" -o lstart= 2>/dev/null)"
c1_birth="$(_norm_lstart "$c1_birth_raw")"
if [[ "$c1_args" != *claude* || "$c1_args" == *" -p"* || "$c1_args" == *"--print"* ]]; then
  fail "C1 setup: fixture ps args= '$c1_args' does not match the intended interactive shape"
else
  printf 'sessions:\n  - task_id: PID-KIND-MISMATCH\n    pid: %s\n    pid_birth: "%s"\n    started_at: "2020-01-01T00:00:00Z"\n' \
    "$C1_PID" "$c1_birth" > "$active"
  c1_out="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$HELPER" --project-root "$repo" --lane PID-KIND-MISMATCH --json)"
  c1_alive="$(printf -- '%s' "$c1_out" | json_get "d.get('pid_alive')")"
  if [[ "$c1_alive" == "False" ]]; then
    pass "C1 live+birth-matching interactive-shaped pid is reported not alive"
  else
    fail "C1 pid_alive=$c1_alive out=$c1_out"
  fi
fi
kill "$C1_PID" 2>/dev/null || true
wait "$C1_PID" 2>/dev/null || true

# ── C3: EPERM pid (1) -> alive, never dead ─────────────────────────────────
section "C3 — EPERM pid (1) must not be read as dead"
mkdir -p "$repo/docs/handoff/PID-EPERM"
printf 'old worker output\n' > "$repo/docs/handoff/PID-EPERM/session.log"
if [[ "$(id -u)" == "0" ]]; then
  log "SKIP C3: running as root, kill(1,0) would not raise EPERM here"
else
  printf 'sessions:\n  - task_id: PID-EPERM\n    pid: 1\n    started_at: "2020-01-01T00:00:00Z"\n' > "$active"
  c3_out="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" bash "$HELPER" --project-root "$repo" --lane PID-EPERM --json)"
  c3_alive="$(printf -- '%s' "$c3_out" | json_get "d.get('pid_alive')")"
  if [[ "$c3_alive" == "True" ]]; then
    pass "C3 EPERM pid 1 is reported alive, not dead"
  else
    fail "C3 pid_alive=$c3_alive out=$c3_out"
  fi
fi

printf -- '\n=== test-lane-verdict-pid-is-a-worker.sh: %s passed, %s failed ===\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
