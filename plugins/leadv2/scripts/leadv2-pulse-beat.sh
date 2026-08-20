#!/usr/bin/env bash
# scripts/leadv2-pulse-beat.sh — PULSE-IN-SINGLE-LEAD-01
#
# Drives the SAME composer (leadv2-broad-status.sh) that
# the (now-retired) supervisor loop's beat branch used to call, for a session
# that is running single-lead mode instead of the supervisor loop. Never renders
# anything itself and never writes founder-status.md directly — this is
# purely a "dispatch, then compose" driver, same order as the loop
# (the now-retired supervisor loop, formerly lines 842-852): the backlog pump runs first and its
# dispatched-count is exported into the beat before the composer sees it.
#
# Kill-switch: LEADV2_SINGLE_LEAD_BEAT=0 makes every invocation a no-op
# (rc=0, no pump call, no composer call, no state touched). This is the
# rollback for the whole feature — the hook that calls this script also
# checks the same var first, so the composer is never reached from either
# caller when it's off.
#
# Invocations:
#   --check   background-safe: honours the throttle + loop-liveness gate,
#             never fails a caller (always rc=0)
#   --now     bypasses the throttle, runs synchronously, exit = composer rc
#   --due     predicate only: prints due|not-due|loop-owns, exits 0/1
set -uo pipefail
trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:---check}"

[[ "${LEADV2_SINGLE_LEAD_BEAT:-1}" == "0" ]] && { [[ "$MODE" == "--due" ]] && { printf -- 'disabled\n'; exit 1; }; exit 0; }

PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)}}"
if [[ -z "$PROJECT_ROOT" ]]; then
  [[ "$MODE" == "--due" ]] && printf -- 'no-root\n'
  exit 0
fi
export LEADV2_PROJECT_ROOT="$PROJECT_ROOT"

STATE_PATH_SH="$SCRIPT_DIR/leadv2-state-path.sh"
PUMP_SH="${LEADV2_BACKLOG_PUMP_BIN:-${SCRIPT_DIR}/leadv2-backlog-pump.sh}"
BROAD_STATUS_SH="${LEADV2_BROAD_STATUS_BIN:-${SCRIPT_DIR}/leadv2-broad-status.sh}"
LOG_FILE="$(PROJECT_ROOT="$PROJECT_ROOT" "$STATE_PATH_SH" supervise-loop.log 2>/dev/null || true)"
[[ -z "$LOG_FILE" ]] && LOG_FILE="${PROJECT_ROOT}/docs/leadv2/supervise-loop.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

BEAT_S="${LEADV2_SINGLE_LEAD_BEAT_S:-1800}"
[[ "$BEAT_S" =~ ^[0-9]+$ ]] || BEAT_S=1800

STATE_DIR="$(PROJECT_ROOT="$PROJECT_ROOT" "$STATE_PATH_SH" --no-link root 2>/dev/null || true)"
[[ -z "$STATE_DIR" ]] && STATE_DIR="${PROJECT_ROOT}/docs/leadv2"
mkdir -p "$STATE_DIR" 2>/dev/null || true
BEAT_LAST_FILE="${STATE_DIR}/.pulse-beat-last"
BEAT_LOCK_FILE="${STATE_DIR}/.pulse-beat.lock"
LOOP_SENTINEL="${STATE_DIR}/.supervise-loop.json"

_now_epoch() { date +%s; }

# ── loop-liveness: if the real supervise loop owns this beat, never
#    double-drive the composer (R2). Same primitive as
#    leadv2-supervisor-pump-caller.sh. ─────────────────────────────────────
_loop_is_live() {
  [[ -f "$LOOP_SENTINEL" ]] || return 1
  python3 -c "
import sys, json, os
try:
    with open(sys.argv[1], encoding='utf-8') as fh:
        d = json.load(fh) or {}
    pid = d.get('pid')
    if pid is None:
        sys.exit(1)
    os.kill(int(pid), 0)
    sys.exit(0)
except Exception:
    sys.exit(1)
" "$LOOP_SENTINEL" 2>/dev/null
}

_due() {
  # 0 = due, 1 = not due (throttle), 2 = loop owns the beat
  if _loop_is_live; then
    return 2
  fi
  local now last
  now="$(_now_epoch)"
  last=0
  [[ -f "$BEAT_LAST_FILE" ]] && last="$(cat "$BEAT_LAST_FILE" 2>/dev/null || echo 0)"
  [[ "$last" =~ ^[0-9]+$ ]] || last=0
  (( now - last >= BEAT_S ))
}

if [[ "$MODE" == "--due" ]]; then
  if _loop_is_live; then
    printf -- 'loop-owns\n'; exit 1
  elif _due; then
    printf -- 'due\n'; exit 0
  else
    printf -- 'not-due\n'; exit 1
  fi
fi

if [[ "$MODE" != "--now" ]]; then
  # --check: loop-liveness + throttle gate BEFORE touching anything.
  if _loop_is_live; then
    exit 0
  fi
  if ! _due; then
    exit 0
  fi
fi

# R1: stamp the throttle clock BEFORE doing any work, so a hung composer
# cannot cause a beat storm on the next --check.
printf -- '%s' "$(_now_epoch)" > "${BEAT_LAST_FILE}.tmp.$$" 2>/dev/null \
  && mv -f "${BEAT_LAST_FILE}.tmp.$$" "$BEAT_LAST_FILE" 2>/dev/null || true

# BROAD-STATUS-RELAY-SCOPE-01 (round 2, HIGH-2): the session that armed this
# beat becomes its recorded owner ONLY if it actually has a live dispatched
# lane -- otherwise ownership would just be "whoever's --check won the
# throttle race", which is the original incident (a focused session with no
# lanes claims the beat and starves everyone else). Written when the hook
# told us which session armed it AND that session qualifies; any other case
# (no LEADV2_BEAT_OWNER_SESSION, resolver missing, no live lane) leaves the
# owner file untouched rather than recording an unqualified or empty owner.
# The read side (leadv2-beat-owner.sh's ladder) is authoritative regardless
# -- a bug in this write-side check can only under-grant, never over-grant,
# ownership, since a stale/absent owner file still resolves to "unresolved"
# (full relay) there.
if [[ -n "${LEADV2_BEAT_OWNER_SESSION:-}" ]]; then
  BEAT_OWNER_SH="${SCRIPT_DIR}/leadv2-beat-owner.sh"
  if [[ -f "$BEAT_OWNER_SH" ]]; then
    # shellcheck source=/dev/null
    source "$BEAT_OWNER_SH"
    if command -v leadv2_session_has_live_lane >/dev/null 2>&1 \
      && leadv2_session_has_live_lane "$LEADV2_BEAT_OWNER_SESSION" "$STATE_DIR" "$PROJECT_ROOT" 2>/dev/null; then
      BEAT_OWNER_FILE="${STATE_DIR}/.pulse-beat-owner"
      printf -- '%s %s' "$LEADV2_BEAT_OWNER_SESSION" "$(_now_epoch)" > "${BEAT_OWNER_FILE}.tmp.$$" 2>/dev/null \
        && mv -f "${BEAT_OWNER_FILE}.tmp.$$" "$BEAT_OWNER_FILE" 2>/dev/null || true
    fi
  fi
fi

_run_beat() {
  export LEADV2_BROAD_STATUS_DISPATCHED="unavailable"
  if [[ "${LEADV2_BACKLOG_PUMP:-1}" == "1" && -x "$PUMP_SH" ]]; then
    local pump_out dispatched_n
    pump_out="$(bash "$PUMP_SH" check 2>&1)" || true
    [[ -z "$pump_out" ]] || printf -- '%s\n' "$pump_out" >>"$LOG_FILE"
    dispatched_n="$(printf -- '%s\n' "$pump_out" \
      | sed -n 's/.*check complete:.*dispatched=\([0-9][0-9]*\).*/\1/p' | tail -n1)"
    export LEADV2_BROAD_STATUS_DISPATCHED="${dispatched_n:-unavailable}"
  fi
  local rc=0
  if [[ -x "$BROAD_STATUS_SH" ]]; then
    bash "$BROAD_STATUS_SH" >>"$LOG_FILE" 2>&1 || rc=$?
  else
    printf -- '%s [BROAD_STATUS] failure: composer unavailable (single-lead beat)\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$LOG_FILE"
    rc=1
  fi
  unset LEADV2_BROAD_STATUS_DISPATCHED
  return $rc
}

if [[ "$MODE" == "--now" ]]; then
  _run_beat
  exit $?
fi

# --check: non-blocking flock so a second concurrent trigger just returns.
exec 9>"$BEAT_LOCK_FILE" || exit 0
if command -v flock >/dev/null 2>&1; then
  flock -n 9 || exit 0
fi

SELF="${BASH_SOURCE[0]}"
if command -v setsid >/dev/null 2>&1; then
  setsid nohup bash "$SELF" --now >/dev/null 2>&1 &
else
  nohup bash "$SELF" --now >/dev/null 2>&1 &
fi
disown 2>/dev/null || true
exit 0
