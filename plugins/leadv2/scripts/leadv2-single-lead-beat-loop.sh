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
# with the board.
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
_cleanup_pid() { rm -f "$PID_FILE" 2>/dev/null || true; }
trap _cleanup_pid EXIT INT TERM

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
# Liveness: fail-open must not mean run-forever. An UNKNOWN count (heartbeat
# missing/unparseable) is not a zero, but N consecutive unknowns (default 3)
# means the board is unreadable — exit instead of beating into the void for
# the full lifetime cap. Defensive bound, not an observation (fix-round H4):
# no live orphan count was ever taken — tune via
# LEADV2_SINGLE_LEAD_BEAT_LOOP_UNKNOWN_MAX. Zeros get the same asymmetry fix
# (H3): one zero is a blip, ZERO_MAX consecutive zeros are a stopped board.
UNKNOWN_MAX="${LEADV2_SINGLE_LEAD_BEAT_LOOP_UNKNOWN_MAX:-3}"
[[ "$UNKNOWN_MAX" =~ ^[0-9]+$ ]] || UNKNOWN_MAX=3
ZERO_MAX="${LEADV2_SINGLE_LEAD_BEAT_LOOP_ZERO_MAX:-3}"
[[ "$ZERO_MAX" =~ ^[0-9]+$ ]] || ZERO_MAX=3
_unknown_streak=0
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
    _zero_streak=0   # an unknown pass is not a zero
    _unknown_streak=$(( _unknown_streak + 1 ))
    if (( _unknown_streak >= UNKNOWN_MAX )); then
      printf '[beat-loop] lane count unknown %d passes in a row, stopping\n' "$_unknown_streak" >&2
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
