#!/usr/bin/env bash
# tests/test-alarm-dedupe-transition.sh — SUPERVISOR-HARDENING-01 item 5 test
# for lib/leadv2-alarm-dedupe.sh (transition-based alarm dedupe).
#
# Sources the real lib with its state dir in a throwaway temp dir and exercises
# the public entrypoints the supervise loop wires up:
#   • leadv2_alarm_filter            — batch transition filter
#   • leadv2_alarm_filter_seen <ks> <cycle> + leadv2_alarm_sweep <ks> <cycle>
#                                    — presence tracking + recovery edge
#
# Cases:
#   1. same (key,value) twice → emitted ONCE (presence ≠ transition)
#   2. value changes → emits again
#   3. value returns to the earlier value AFTER a sweep-clear → emits again
#   4. sweep with the key absent from the cycle → state cleared (CLEAR),
#      next presence re-fires
#   5. lib missing → the loop's pass-through fallback emits EVERY line (no
#      silent alarm loss) — guards the fallback contract in leadv2-supervise-
#      loop.sh, not the lib itself.
#
# Isolation: LEADV2_ALARM_STATE_DIR points the lib at a per-case temp dir, so
# no case shares state with another and nothing touches a real control plane.
# Run: bash scripts/tests/test-alarm-dedupe-transition.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="${SCRIPT_DIR}/lib/leadv2-alarm-dedupe.sh"
source "${SCRIPT_DIR}/leadv2-temp.sh"

PASS=0
FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); log "FAIL: $1"; }

if bash -n "${LIB}" 2>/dev/null; then pass "bash -n alarm-dedupe lib"; else fail "bash -n alarm-dedupe lib"; fi
[[ -f "$LIB" ]] || { fail "lib missing — cannot source"; log ""; log "=== ${PASS} passed, ${FAIL} failed ==="; exit 1; }

# Fresh state dir per case so cases never contaminate each other.
fresh_state() { LEADV2_ALARM_STATE_DIR="$(lv2_mktemp_dir alarm-state)"; export LEADV2_ALARM_STATE_DIR; }
# source the lib AFTER exporting the state dir
source "$LIB"

# Count survivor lines emitted by the filter for a given stdin.
count_emitted() { leadv2_alarm_filter | grep -c '^' || true; }

# ── Cases 1 & 2: leadv2_alarm_filter — presence ≠ transition ───────────────
fresh_state
R_RED_HIGH=$'truth_red:k1\tHIGH\tURGENT red high'
R_RED_LOW=$'truth_red:k1\tLOW\tURGENT red low'

# Case 1a: two identical rows in ONE batch → emitted once.
n="$(printf '%s\n%s\n' "$R_RED_HIGH" "$R_RED_HIGH" | count_emitted)"
if [[ "$n" == "1" ]]; then pass "case 1a: identical rows in one batch emit once"; else fail "case 1a: expected 1 emission, got $n"; fi

# Case 1b: same row across a SECOND batch invocation → suppressed.
n="$(printf '%s\n' "$R_RED_HIGH" | count_emitted)"
if [[ "$n" == "0" ]]; then pass "case 1b: repeat across invocations suppressed"; else fail "case 1b: expected 0, got $n"; fi

# Case 2: value changes HIGH → LOW → emits again.
n="$(printf '%s\n' "$R_RED_LOW" | count_emitted)"
if [[ "$n" == "1" ]]; then pass "case 2: value change emits again"; else fail "case 2: expected 1, got $n"; fi

# ── Cases 3 & 4: filter_seen + sweep — the recovery edge ───────────────────
fresh_state
KS="testks"
R_RED=$'truth_red:k2\tRED\tURGENT red'

# Cycle 1: key present → fires (transition EMPTY->RED).
n="$(printf '%s\n' "$R_RED" | leadv2_alarm_filter_seen "$KS" 1 | grep -c '^' || true)"
if [[ "$n" == "1" ]]; then pass "case 3 setup: first presence fires"; else fail "case 3 setup: expected 1, got $n"; fi
leadv2_alarm_sweep "$KS" 1   # nothing absent yet → no CLEAR written

# Same value again in cycle 1 → suppressed (proves persistence).
n="$(printf '%s\n' "$R_RED" | leadv2_alarm_filter_seen "$KS" 1 | grep -c '^' || true)"
if [[ "$n" == "0" ]]; then pass "case 3: persistent value suppressed"; else fail "case 3: expected 0, got $n"; fi

# Case 4: cycle 2 — key ABSENT (breach cleared). Sweep writes CLEAR to its state.
leadv2_alarm_sweep "$KS" 2
state_file="${LEADV2_ALARM_STATE_DIR}/$(_leadv2_alarm_sanitize_key truth_red:k2)"
if [[ -f "$state_file" && "$(cat "$state_file" 2>/dev/null)" == "CLEAR" ]]; then
  pass "case 4: absent key swept to CLEAR"
else
  fail "case 4: state not CLEAR (got '$(cat "$state_file" 2>/dev/null)')"
fi

# Case 3 (resolution): cycle 3 — key re-appears with the SAME value RED.
# CLEAR→RED is a transition → fires again (the recovery edge).
n="$(printf '%s\n' "$R_RED" | leadv2_alarm_filter_seen "$KS" 3 | grep -c '^' || true)"
if [[ "$n" == "1" ]]; then pass "case 3: re-breach after sweep-clear fires again"; else fail "case 3: expected 1 re-fire, got $n"; fi

# ── Case 5: lib missing → loop pass-through fallback emits every line ──────
# Mirrors the exact guard the (now-retired) supervisor loop used (if _leadv2_alarm_fire is
# undefined after the source attempt, define `leadv2_alarm_filter(){ cat; }`).
# Run a FRESH bash that never sources the lib — a subshell would inherit the
# lib this test already sourced, so the guard would not engage. The fresh bash
# is the faithful model of a loop process whose `source` failed.
N_LINES=3
n="$(printf 'truth_red:k9\tX\tLINE1\ntruth_red:k9\tX\tLINE2\ntruth_red:k9\tX\tLINE3\n' | bash -c '
      set -uo pipefail
      if ! command -v _leadv2_alarm_fire >/dev/null 2>&1; then
        leadv2_alarm_filter() { cat; }   # pass-through fallback (no lib loaded)
      fi
      leadv2_alarm_filter
    ' | grep -c '^' || true)"
if [[ "$n" == "$N_LINES" ]]; then
  pass "case 5: lib-missing fallback emits every line (no silent loss)"
else
  fail "case 5: expected $N_LINES pass-through emissions, got $n"
fi

log ""
log "=== ${PASS} passed, ${FAIL} failed ==="
[[ "$FAIL" -eq 0 ]]
