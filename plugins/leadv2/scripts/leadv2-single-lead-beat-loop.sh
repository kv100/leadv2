#!/usr/bin/env bash
# scripts/leadv2-single-lead-beat-loop.sh — MON-PULSE-01 part 2: single-lead
# pulse beat default-on.
#
# The BROAD_STATUS beat (leadv2-pulse-beat.sh -> leadv2-broad-status.sh) used
# to be driven by the supervise loop (retired 2026-08-17) and then only by the
# per-tool-call hook with a 1800s throttle. Founder order 2026-08-28: in
# single-lead mode the beat must be DEFAULT-ON whenever at least one lane is
# live — armed by DISPATCH itself at the first worker_spawned, not by any
# session-improvised Monitor.
#
# This loop is started detached (nohup) once per PROJECT ROOT by
# leadv2-dispatch-code.sh (pidfile guard: never armed twice — the pidfile is
# KEYED BY ROOT, fix-round H3: the state root is shared by the main checkout
# and every worktree, but founder-status.md is per-worktree, so a repo-global
# pidfile let the first worktree starve every other concurrent lane tree of
# its beat). Every
# LEADV2_SINGLE_LEAD_BEAT_LOOP_S (default 300s = 5 min) it counts live lanes
# (leadv2-lane-heartbeat.sh verdicts `running` AND `running_stale` — a stale
# heartbeat is a lane we still have something to report about, never a zero;
# fix-round H3) and, while >=1 lane is live, drives the beat via
# leadv2-pulse-beat.sh --check (which keeps its own flock/coalescing/transition
# machinery). Only ZERO_MAX (default 3) CONSECUTIVE real zeros stop the loop —
# a single transient zero (heartbeat blip, briefly unparsable started_at) must
# not silence the pulse; then it removes its pidfile and exits — the beat stops
# with the board. Reader errors do not stop the loop LIGHTLY (fix-round 3
# H-2): a heartbeat that fails or emits an error object means the monitor is
# blind, precisely when the founder still needs the beat — but that blindness
# is bounded at UNKNOWN_MAX consecutive passes (PLUGIN-PAPERCUTS-01, defect 1:
# an unbounded fail-open let suite-fixture loops beat blind for up to 24h).
#
# Kill-switches: LEADV2_PULSE_MODE=0 or LEADV2_SINGLE_LEAD_BEAT=0 make every
# invocation a no-op (rc=0, nothing armed). Hard lifetime cap
# LEADV2_SINGLE_LEAD_BEAT_LOOP_MAX_S (default 86400) so a wedged
# lane-heartbeat can never make the loop immortal.
#
# Hermetic seams (tests): LEADV2_LANE_HEARTBEAT_BIN, LEADV2_PULSE_BEAT_BIN,
# LEADV2_SINGLE_LEAD_BEAT_LOOP_PID, LEADV2_SINGLE_LEAD_BEAT_LOOP_PID_DIR,
# LEADV2_SINGLE_LEAD_BEAT_LOOP_S.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# kill-switches first — arming itself must be a no-op
[[ "${LEADV2_PULSE_MODE:-1}" == "1" ]] || exit 0
[[ "${LEADV2_SINGLE_LEAD_BEAT:-1}" == "0" ]] && exit 0

INTERVAL="${LEADV2_SINGLE_LEAD_BEAT_LOOP_S:-300}"
MAX_S="${LEADV2_SINGLE_LEAD_BEAT_LOOP_MAX_S:-86400}"
[[ "$INTERVAL" =~ ^[0-9]+$ ]] || INTERVAL=300
[[ "$MAX_S" =~ ^[0-9]+$ ]] || MAX_S=86400

PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)}"
[[ -n "$PROJECT_ROOT" ]] || { printf '[beat-loop] no project root\n' >&2; exit 0; }

STATE_DIR="$(PROJECT_ROOT="$PROJECT_ROOT" bash "${SCRIPT_DIR}/leadv2-state-path.sh" --no-link root 2>/dev/null || true)"
[[ -n "$STATE_DIR" ]] || STATE_DIR="${PROJECT_ROOT}/docs/leadv2"
# H3: the state root is shared by the main checkout AND every worktree
# (leadv2-state-path.sh resolves it from git-common-dir), while the beat's
# output (founder-status.md) is per-project-root. A repo-global pidfile let
# the first worktree to dispatch starve every other concurrent lane tree —
# so the pidfile is KEYED BY ROOT (cksum of the absolute path): each root
# gets its own loop and its own beat. The lane scan is already per-root
# (LEADV2_PROJECT_ROOT is passed to the heartbeat bin below).
_root_key="$(printf '%s' "$PROJECT_ROOT" | cksum 2>/dev/null || true)"
_root_key="${_root_key%% *}"
[[ "$_root_key" =~ ^[0-9]+$ ]] || _root_key="$(printf '%s' "$PROJECT_ROOT" | tr -cd '0-9A-Za-z' | cut -c1-40)"
PID_DIR="${LEADV2_SINGLE_LEAD_BEAT_LOOP_PID_DIR:-$STATE_DIR}"
PID_FILE="${LEADV2_SINGLE_LEAD_BEAT_LOOP_PID:-${PID_DIR}/.single-lead-beat-loop-${_root_key}.pid}"

# pidfile guard: a live previous arming wins, this invocation is a no-op
if [[ -f "$PID_FILE" ]]; then
  _old_pid="$(cat "$PID_FILE" 2>/dev/null | tr -d ' ')"
  if [[ "${_old_pid}" =~ ^[0-9]+$ ]] && kill -0 "${_old_pid}" 2>/dev/null; then
    printf '[beat-loop] already armed by pid %s, no-op\n' "$_old_pid" >&2
    exit 0
  fi
fi
mkdir -p "$(dirname "$PID_FILE")" 2>/dev/null || true
printf '%s\n' "$$" > "${PID_FILE}.tmp.$$" 2>/dev/null \
  && mv -f "${PID_FILE}.tmp.$$" "$PID_FILE" 2>/dev/null || true
# PLUGIN-PAPERCUTS-01 (defect 1): only remove the pidfile if it still names
# US. A loop armed BEFORE us that exits late used to `rm -f $PID_FILE`
# unconditionally — deleting the NEWER loop's live claim and blinding the
# guard, so the next dispatch armed a second concurrent loop for the same
# root ("killed one, count did not drop — they respawn").
_cleanup_pid() {
  if [[ -f "$PID_FILE" ]] \
     && [[ "$(cat "$PID_FILE" 2>/dev/null | tr -d ' ')" == "$$" ]]; then
    rm -f "$PID_FILE" 2>/dev/null || true
  fi
}
# PLUGIN-PAPERCUTS-01 (defect 1): a trapped INT/TERM whose handler only cleans
# up RESUMES the loop afterwards (bash continues after the handler) — so
# `kill <loop>` left the loop beating forever, another face of "killing them
# did not reduce the count". The signal handlers must actually EXIT.
_stop_and_clean() { _cleanup_pid; trap - EXIT; exit 0; }
trap _cleanup_pid EXIT
trap _stop_and_clean INT TERM

HB_BIN="${LEADV2_LANE_HEARTBEAT_BIN:-${SCRIPT_DIR}/leadv2-lane-heartbeat.sh}"
BEAT_BIN="${LEADV2_PULSE_BEAT_BIN:-${SCRIPT_DIR}/leadv2-pulse-beat.sh}"

# _live_lane_count -> integer count of live verdicts (`running` plus
# `running_stale` — fix-round H3: a lane whose heartbeat aged past the stale
# threshold, or whose row briefly lacks a parseable last_pulse_at/started_at,
# is alive-but-slow, precisely when the founder most needs the pulse), or
# empty on any failure. Fail-open semantics (same as leadv2-pulse-beat.sh):
# callers treat empty as UNKNOWN, never as zero — a zero here must be a REAL
# zero (and even then it takes ZERO_MAX consecutive ones to stop, see below).
_live_lane_count() {
  [[ -x "$HB_BIN" || -f "$HB_BIN" ]] || return 0
  local json
  json="$( (LEADV2_PROJECT_ROOT="$PROJECT_ROOT" bash "$HB_BIN" status --all --json 2>/dev/null || true) )"
  [[ -n "$json" ]] || return 0
  python3 -c "
import sys, json
try:
    rows = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)
if not isinstance(rows, list):
    sys.exit(0)
print(sum(1 for r in rows if isinstance(r, dict) and r.get('status') in ('running', 'running_stale')))
" "$json" 2>/dev/null
}

_started="$(date +%s)"
# Liveness: fail-open must not mean run-forever, but a reader error is NOT a
# stop signal (fix-round 3 H-2): a heartbeat that is missing, prints garbage,
# or emits an error OBJECT (registry unreadable) is the monitor being BLIND,
# not the board being empty — stopping the beat there is the exact
# founder-blindness failure this loop exists to kill. Reader-error passes keep
# beating and never count toward any stop condition; the retired
# LEADV2_SINGLE_LEAD_BEAT_LOOP_UNKNOWN_MAX stop (fix-round H4) is GONE. Only a
# registry that is genuinely readable and reports zero live lanes may stop the
# loop — and even then only after ZERO_MAX consecutive real zeros (fix-round
# H3: one zero is a blip). The hard lifetime cap below bounds the blind case.
ZERO_MAX="${LEADV2_SINGLE_LEAD_BEAT_LOOP_ZERO_MAX:-3}"
[[ "$ZERO_MAX" =~ ^[0-9]+$ ]] || ZERO_MAX=3
_unknown_streak=0
# PLUGIN-PAPERCUTS-01 (defect 1): the reader-error fail-open above is bounded.
# A beat loop armed by a TEST suite (or by a lane whose tree was torn down)
# finds a heartbeat that errors EVERY pass — and the H-2 "unknown keeps the
# beat" rule made that loop beat blind for the full 24h lifetime cap, emitting
# an unrelated repo's pulse the whole time (measured 2026-08-31: loops 6h44m
# old inside /var/folders fixture trees). UNKNOWN_MAX consecutive UNKNOWN
# passes now stop the loop: 12 x 300s = one hour of blindness, generous
# against a transient monitor outage but finite against a dead environment.
# 0 restores the unbounded pre-fix behaviour; the old suite's B8 (5+ unknown
# passes stay alive) stays green under the default.
UNKNOWN_MAX="${LEADV2_SINGLE_LEAD_BEAT_LOOP_UNKNOWN_MAX:-12}"
[[ "$UNKNOWN_MAX" =~ ^[0-9]+$ ]] || UNKNOWN_MAX=12
_zero_streak=0
while :; do
  if [[ ! -d "$PROJECT_ROOT" ]]; then
    printf '[beat-loop] project root gone (%s), stopping\n' "$PROJECT_ROOT" >&2
    exit 0
  fi
  n="$(_live_lane_count)"
  if [[ "$n" =~ ^[0-9]+$ ]]; then
    _unknown_streak=0
    if (( n == 0 )); then
      # fix-round H3: a single zero can be a heartbeat blip (a running_stale
      # row, a briefly unparsable started_at) — only ZERO_MAX consecutive
      # real zeros stop the beat (pidfile removed by trap on exit).
      _zero_streak=$(( _zero_streak + 1 ))
      if (( _zero_streak >= ZERO_MAX )); then
        printf '[beat-loop] no live lanes for %d passes in a row, stopping\n' "$_zero_streak" >&2
        exit 0
      fi
    else
      _zero_streak=0
    fi
  else
    # fix-round 3 H-2: an UNKNOWN pass is a READER error (heartbeat bin
    # missing, output unparseable, or an error OBJECT from the heartbeat
    # bin). Keep beating — the beat is fail-open exactly when the founder
    # cannot see the board themselves — and do NOT count it toward any stop
    # condition (the old UNKNOWN_MAX stop died here). Throttled log only.
    _zero_streak=0
    _unknown_streak=$(( _unknown_streak + 1 ))
    if (( _unknown_streak == 1 || _unknown_streak % 10 == 0 )); then
      printf '[beat-loop] lane count unknown (reader error, pass %d): keeping the beat\n' "$_unknown_streak" >&2
    fi
    # PLUGIN-PAPERCUTS-01 (defect 1): bounded blindness. After UNKNOWN_MAX
    # consecutive reader-error passes the environment this loop was armed for
    # is gone (torn-down fixture, removed tree) — stop instead of beating
    # blind until the 24h lifetime cap.
    if (( UNKNOWN_MAX > 0 && _unknown_streak >= UNKNOWN_MAX )); then
      printf '[beat-loop] lane count unknown for %d passes in a row (reader error), stopping\n' "$_unknown_streak" >&2
      exit 0
    fi
  fi
  # >=1 live lane (or unknown — fail-open): drive the beat. --check keeps the
  # beat script's own throttle/flock/transition machinery; align its clock to
  # this loop's interval unless the caller pinned a tighter one.
  if [[ -f "$BEAT_BIN" ]]; then
    LEADV2_SINGLE_LEAD_BEAT_S="${LEADV2_SINGLE_LEAD_BEAT_S:-$INTERVAL}" \
      LEADV2_PROJECT_ROOT="$PROJECT_ROOT" \
      bash "$BEAT_BIN" --check >/dev/null 2>&1 || true
  fi
  sleep "$INTERVAL"
  _now="$(date +%s)"
  if (( _now - _started >= MAX_S )); then
    printf '[beat-loop] lifetime cap %ss reached, exiting\n' "$MAX_S" >&2
    exit 0
  fi
done
