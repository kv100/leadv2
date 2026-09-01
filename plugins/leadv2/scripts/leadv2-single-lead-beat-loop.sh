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
# with the board. Reader errors NEVER stop the loop (fix-round 3 H-2): a
# heartbeat that fails or emits an error object means the monitor is blind,
# precisely when the founder still needs the beat.
#
# Kill-switches: LEADV2_PULSE_MODE=0 or LEADV2_SINGLE_LEAD_BEAT=0 make every
# invocation a no-op (rc=0, nothing armed). Hard lifetime cap
# LEADV2_SINGLE_LEAD_BEAT_LOOP_MAX_S (default 86400) so a wedged
# lane-heartbeat can never make the loop immortal.
#
# Hermetic seams (tests): LEADV2_LANE_HEARTBEAT_BIN, LEADV2_PULSE_BEAT_BIN,
# LEADV2_SINGLE_LEAD_BEAT_LOOP_PID, LEADV2_SINGLE_LEAD_BEAT_LOOP_PID_DIR,
# LEADV2_SINGLE_LEAD_BEAT_LOOP_S. Lifecycle seams (WATCHER-LIFECYCLE-LEAK-01):
# LEADV2_WATCH_LIFECYCLE_LOG (event log path), LEADV2_WATCHER_OWNER_PID
# (optional explicit owner — unset in production, see the loop body).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# WATCHER-LIFECYCLE-LEAK-01: shared watcher lifecycle (race-safe singleton
# claim, self-reap, event log). Guarded + canonical-fallback source, same
# shape dispatch-ledger uses for its libs (a consumer-repo symlink farm may
# not carry a lib/ copy of a new file); the stubs reproduce the PRE-fix
# behavior so a missing lib can never stop the beat.
_WL_LIB="${SCRIPT_DIR}/lib/leadv2-watch-lifecycle.sh"
[[ -f "${_WL_LIB}" ]] || _WL_LIB="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/lib/leadv2-watch-lifecycle.sh"
if [[ -f "${_WL_LIB}" ]]; then
  # shellcheck source=lib/leadv2-watch-lifecycle.sh
  source "${_WL_LIB}"
else
  wl_event() { :; }
  wl_owner_gone() { return 1; }
  wl_singleton_claim() {  # pre-leak-fix fallback: kill -0 guard + blind write
    local _p
    if [[ -f "$1" ]]; then
      _p="$(cat "$1" 2>/dev/null | tr -d ' ')"
      [[ "${_p}" =~ ^[0-9]+$ ]] && kill -0 "${_p}" 2>/dev/null && return 3
    fi
    mkdir -p "$(dirname "$1")" 2>/dev/null || true
    printf '%s\n' "$$" > "${1}.tmp.$$" 2>/dev/null \
      && mv -f "${1}.tmp.$$" "$1" 2>/dev/null || true
    return 0
  }
fi

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

# ── WATCHER-LIFECYCLE-LEAK-01: race-safe singleton + lifecycle events ─────────
# The 2026-09-01 ticket measured 17 duplicate beat loops from ONE worktree:
# this guard used to be check-then-write with no cmdline validation, so two
# dispatches racing through the slow prelude (state-path resolution) both saw
# no pidfile and both armed; the pidfile loser was then invisible to every
# later arm and ran to the full 86400s cap. wl_singleton_claim (lib) makes
# check+write ATOMIC (mkdir lockdir), refuses only a LIVE process whose
# command line still contains this script's basename (a recycled pid never
# blocks re-arm), replaces a dead/foreign pidfile, and fails OPEN — an
# unwritable pidfile dir still arms, the pre-fix behavior (mission
# fail-open constraint).
WL_LOG_FILE="${LEADV2_WATCH_LIFECYCLE_LOG:-${PID_DIR}/watch-lifecycle.log}"
LEADV2_WATCH_LIFECYCLE_LOG="$WL_LOG_FILE"
# WATCHER-LIFECYCLE-LEAK-01: traps are armed BEFORE the claim — a TERM
# landing inside the claim's settle window used to hit the default death
# action and leak the pidfile. Cleanup removes the pidfile ONLY when it
# still names THIS pid, so it is safe at any point of the claim: a
# dedup-refused copy (pidfile names the winner) can never delete the
# winner's claim, and a TERM between our noclobber-create and the loop
# proper still cleans up.
_cleanup_pid() {
  local _p
  _p="$(cat "$PID_FILE" 2>/dev/null | tr -d '[:space:]')"
  if [[ "$_p" == "$$" ]]; then
    rm -f "$PID_FILE" 2>/dev/null || true
    wl_event "beat-loop" "$PROJECT_ROOT" "$$" "self_reap"
  fi
  return 0
}
# A trapped TERM/INT runs the handler and then RESUMES the script (bash
# replaces the default death with the trap) — the loop survived its own
# kill, pidfile already removed, so every later arm spawned a fresh
# duplicate (the 17-copies leak). The signal handler must EXIT; the EXIT
# trap is disarmed first so self_reap logs exactly once.
# Fix-r1: on macOS bash 3.2 a trapped TERM also DEFERS behind a foreground
# child for that child's full runtime (measured: handler ran 29.5s into a
# 30s sleep) — a killed loop then "survived" its kill for a whole 300s
# production interval and took SIGKILL (the 2026-09-01 strays). Every long
# wait below is therefore a background child under the wait builtin, which
# IS interruptible (0.015s measured), and the handler kills that child.
WL_CHILD=""
_on_term() {
  trap - EXIT
  [[ -n "$WL_CHILD" ]] && kill "$WL_CHILD" 2>/dev/null || true
  _cleanup_pid
  exit 0
}
trap _cleanup_pid EXIT
trap _on_term INT TERM
wl_singleton_claim "$PID_FILE"
case $? in
  3)
    printf '[beat-loop] already armed by pid %s, no-op\n' "$(cat "$PID_FILE" 2>/dev/null | tr -d ' ')" >&2
    wl_event "beat-loop" "$PROJECT_ROOT" "$$" "dedup_refused"
    exit 0
    ;;
esac
wl_event "beat-loop" "$PROJECT_ROOT" "$$" "spawn"

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
_zero_streak=0
while :; do
  if [[ ! -d "$PROJECT_ROOT" ]]; then
    printf '[beat-loop] project root gone (%s), stopping\n' "$PROJECT_ROOT" >&2
    exit 0
  fi
  # WATCHER-LIFECYCLE-LEAK-01 #2: owner-bound self-reap, checked every
  # iteration so the exit lands within one interval. The DURABLE owner of
  # this loop is the root's live-lane board — the zero-streak stop below IS
  # the heartbeat-staleness reap — because the arming dispatcher exits
  # seconds after worker_spawned (binding to ITS pid would kill the beat
  # immediately). The explicit pid seam exists for ops/tests that arm with
  # a concrete owner process; unset (production default) changes nothing.
  if wl_owner_gone; then
    printf '[beat-loop] owner pid %s gone, self-reaping\n' "${LEADV2_WATCHER_OWNER_PID}" >&2
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
  fi
  # >=1 live lane (or unknown — fail-open): drive the beat. --check keeps the
  # beat script's own throttle/flock/transition machinery; align its clock to
  # this loop's interval unless the caller pinned a tighter one.
  if [[ -f "$BEAT_BIN" ]]; then
    LEADV2_SINGLE_LEAD_BEAT_S="${LEADV2_SINGLE_LEAD_BEAT_S:-$INTERVAL}" \
      LEADV2_PROJECT_ROOT="$PROJECT_ROOT" \
      bash "$BEAT_BIN" --check >/dev/null 2>&1 &
    WL_CHILD=$!
    wait "$WL_CHILD" 2>/dev/null || true
    WL_CHILD=""
  fi
  # background sleep + wait: TERM must fire the handler NOW, not when the
  # sleep ends (see _on_term above for the measured 29.5s-of-30s deferral)
  sleep "$INTERVAL" &
  WL_CHILD=$!
  wait "$WL_CHILD" 2>/dev/null || true
  WL_CHILD=""
  _now="$(date +%s)"
  if (( _now - _started >= MAX_S )); then
    printf '[beat-loop] lifetime cap %ss reached, exiting\n' "$MAX_S" >&2
    exit 0
  fi
done
