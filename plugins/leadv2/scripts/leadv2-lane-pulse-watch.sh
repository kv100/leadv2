#!/usr/bin/env bash
# scripts/leadv2-lane-pulse-watch.sh — MON-PULSE-01 part 1: dispatcher-owned lane watch.
#
# Started DETACHED (nohup, never a Claude Monitor) by leadv2-dispatch-code.sh at
# worker_spawned. Founder order 2026-08-28 (3rd occurrence of
# PULSE-IN-SINGLE-LEAD-01): lane tracking must work IN THE PLUGIN — a Monitor
# armed ad hoc by the lead with `tail -n 0` missed a dispatch_terminal written
# 25s post-spawn and the founder saw nothing until he asked.
#
# Replay-safe: the line offset starts at 0, so the FIRST pass reads the journal
# from line 1 (tail -n +1) — terminal lines written between spawn and watcher
# start are still reported. Exit-triggering states are ONLY
#   dispatch_terminal | dispatch_refused | worker_died
# and only for THIS watcher's own task sig (a foreign sig's line never pulses).
# review_gate is a BEAT, never a terminal (fix-round C1): leadv2-review-run.sh
# emits it repeatedly mid-flight (status=ran, round0_skip, dedup,
# arm_infra_died action=retry), so it is pulsed but the watch keeps running
# until a true terminal. A per-sig seen ledger (fix-round H2) survives watcher
# exit, so a re-arm never re-pulses lines a previous watcher already pulsed.
# Each matched line appends exactly one pulse line via the EXISTING
# leadv2-pulse.sh (task_id, phase, <=80 bytes — reused, not reimplemented;
# LEADV2_PULSE_MODE=0 is honored inside leadv2-pulse.sh itself).
#
# Exits after the first pass that matched a terminal line, or after --timeout
# (default 3900s = the FREEPOOL/GLM wall-clock backstop 3600s + 300s grace —
# there is nothing left to watch past the worker's own timeout).
# Never two watchers per lane: pidfile guard keyed by sig.
#
# Usage:
#   leadv2-lane-pulse-watch.sh --sig <sig8> [--root DIR] [--journal FILE]
#     [--interval S=15] [--timeout S=3900] [--state-dir DIR]
#
# Hermetic seams (tests): --root/--journal/--state-dir args,
# LEADV2_LANE_PULSE_BIN (pulse writer), LEADV2_PROJECT_ROOT (root fallback).
# Read-only w.r.t. the journal; writes only its pidfile + the pulse file.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SIG=""
ROOT=""
JOURNAL=""
INTERVAL="${LEADV2_LANE_PULSE_WATCH_INTERVAL:-15}"
TIMEOUT="${LEADV2_LANE_PULSE_WATCH_TIMEOUT:-3900}"
STATE_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sig)       SIG="${2:-}"; shift 2 ;;
    --root)      ROOT="${2:-}"; shift 2 ;;
    --journal)   JOURNAL="${2:-}"; shift 2 ;;
    --interval)  INTERVAL="${2:-}"; shift 2 ;;
    --timeout)   TIMEOUT="${2:-}"; shift 2 ;;
    --state-dir) STATE_DIR="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1}//'
      exit 0 ;;
    *) printf '[lane-pulse-watch] unknown arg: %s\n' "$1" >&2; exit 1 ;;
  esac
done
[[ -n "$SIG" ]] || { printf '[lane-pulse-watch] --sig required\n' >&2; exit 1; }
[[ "$INTERVAL" =~ ^[0-9]+$ ]] || { printf '[lane-pulse-watch] bad --interval: %s\n' "$INTERVAL" >&2; exit 1; }
[[ "$TIMEOUT"  =~ ^[0-9]+$ ]] || { printf '[lane-pulse-watch] bad --timeout: %s\n'  "$TIMEOUT"  >&2; exit 1; }

# ── root + journal path (same resolution order leadv2-journal.sh uses) ──────
if [[ -z "$ROOT" ]]; then
  ROOT="${LEADV2_PROJECT_ROOT:-$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)}"
fi
[[ -n "$ROOT" ]] || { printf '[lane-pulse-watch] no project root\n' >&2; exit 1; }
if [[ -z "$JOURNAL" ]]; then
  _lv2_dir="$(grep -E "^[[:space:]]*leadv2_dir[[:space:]]*:" "${ROOT}/.claude/leadv2-overrides/state-paths.yaml" 2>/dev/null \
    | head -1 | sed -E "s/^[[:space:]]*leadv2_dir[[:space:]]*:[[:space:]]*//" | sed -E "s/^['\"]//; s/['\"][[:space:]]*$//" | tr -d '\r' || true)"
  [[ -z "${_lv2_dir}" || "${_lv2_dir}" == "null" || "${_lv2_dir}" == "~" ]] && _lv2_dir="docs/leadv2"
  JOURNAL="${ROOT}/${_lv2_dir}/tasks/dispatch-${SIG}/journal.md"
fi
TASK_ID="dispatch-${SIG}"

# ── pidfile guard: never two watchers per lane (keyed by sig) ───────────────
if [[ -z "$STATE_DIR" ]]; then
  STATE_DIR="$(PROJECT_ROOT="$ROOT" bash "${SCRIPT_DIR}/leadv2-state-path.sh" --no-link lane-pulse-watch 2>/dev/null || true)"
fi
[[ -n "$STATE_DIR" ]] || STATE_DIR="${TMPDIR:-/tmp}/leadv2-lane-pulse-watch"
PID_DIR="${STATE_DIR}/lane-pulse-watch"
mkdir -p "$PID_DIR" 2>/dev/null || true
PID_FILE="${PID_DIR}/${SIG}.pid"
SEEN_FILE="${PID_DIR}/${SIG}.seen"   # fix-round H2: pulsed-line ledger, survives exit
if [[ -f "$PID_FILE" ]]; then
  _old_pid="$(cat "$PID_FILE" 2>/dev/null | tr -d ' ')"
  if [[ "${_old_pid}" =~ ^[0-9]+$ ]] && kill -0 "${_old_pid}" 2>/dev/null; then
    printf '[lane-pulse-watch] %s already watched by pid %s, no-op\n' "$SIG" "$_old_pid" >&2
    exit 0
  fi
fi
printf '%s\n' "$$" > "${PID_FILE}.tmp.$$" 2>/dev/null \
  && mv -f "${PID_FILE}.tmp.$$" "$PID_FILE" 2>/dev/null || true
_cleanup_pid() { rm -f "$PID_FILE" 2>/dev/null || true; }
trap _cleanup_pid EXIT INT TERM

PULSE_BIN="${LEADV2_LANE_PULSE_BIN:-${SCRIPT_DIR}/leadv2-pulse.sh}"
export LEADV2_PROJECT_ROOT="$ROOT"

# BEATS pulse but never end the watch (fix-round C1): review_gate is emitted
# repeatedly mid-flight by leadv2-review-run.sh, long before the lane ends.
PULSE_PAT='review_gate'
# Exit-triggering states ONLY, for this watcher's sig. `dispatch_terminal` is
# boundary-guarded so dispatch_terminal_dedup noise rows (a duplicate-suppression
# receipt, reason=terminal_already_recorded — not a state transition) never
# terminate the watch (fix-round H1; same guard leadv2-lane-watch.sh:135
# documents with its trailing-space EMIT_PAT). worker_died_stale is excluded
# the same way.
EXIT_PAT='dispatch_terminal([^_]|$)|dispatch_refused([^_]|$)|worker_died([^_]|$)'
KIND_PAT='dispatch_terminal|dispatch_refused|worker_died'

_pulse() {  # <kind> <text> — one line via the existing pulse writer, soft-fail
  [[ -f "$PULSE_BIN" ]] || return 0
  bash "$PULSE_BIN" "$TASK_ID" "$1" "$2" >/dev/null 2>&1 || true
}

_seen_init() {  # <journal> -> initial line offset
  local n
  n="$(wc -l < "$1" 2>/dev/null | tr -d ' ')"
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  # REPLAY-SAFE (MON-PULSE-01): seen starts at 0 so the first pass reads the
  # journal from line 1 (tail -n +1). Today's incident was exactly this bug in
  # Monitor form: `tail -n 0` skipped lines written before the watcher armed.
  # The negative control in test-lane-pulse-watch.sh reverts this return value
  # to the pre-existing line count (tail -n 0 semantics) and MUST go red.
  printf '0'
}

# fix-round H2: the ledger records how many lines a previous watcher for this
# sig already pulsed; it wins over the replay-from-line-1 default so a re-arm
# (fix round, arm advance, retry — all re-enter _spawn_worker_body) cannot
# duplicate stale pulses. Journal rotation is detected in the loop (n < SEEN)
# and resets both SEEN and the ledger.
_ledger_save() {  # <n> — atomic write, soft-fail
  printf '%s\n' "$1" > "${SEEN_FILE}.tmp.$$" 2>/dev/null \
    && mv -f "${SEEN_FILE}.tmp.$$" "$SEEN_FILE" 2>/dev/null || true
}
SEEN="$(_seen_init "$JOURNAL")"
_ledger="$(cat "$SEEN_FILE" 2>/dev/null | tr -d ' ' || true)"
if [[ "$_ledger" =~ ^[0-9]+$ ]] && (( _ledger > SEEN )); then
  SEEN="$_ledger"
fi
_started="$(date +%s)"
# Liveness: the journal ALWAYS exists at arm time (worker_spawned was just
# journaled), so a journal that stays missing means the lane tree was wiped
# (test fixture cleanup, worktree sweep). Never linger for the full timeout on
# a dead root: exit when the root is gone or the journal has been missing for
# GRACE_S consecutive seconds. Defensive bound, not an observation (fix-round
# H4): no live orphan count was ever taken — tune via
# LEADV2_LANE_PULSE_WATCH_GRACE_S if real telemetry ever demands it.
GRACE_S="${LEADV2_LANE_PULSE_WATCH_GRACE_S:-300}"
[[ "$GRACE_S" =~ ^[0-9]+$ ]] || GRACE_S=300
_missing_since=0

while :; do
  if [[ ! -d "$ROOT" ]]; then
    printf '[lane-pulse-watch] %s root gone (%s), exiting\n' "$SIG" "$ROOT" >&2
    exit 0
  fi
  if [[ -f "$JOURNAL" ]]; then
    _missing_since=0
    n="$(wc -l < "$JOURNAL" | tr -d ' ')"
    [[ "$n" =~ ^[0-9]+$ ]] || n=0
    if (( n > SEEN )); then
      # atomic-replace-safe: line-count offsets, never inode following
      own="$(tail -n +"$((SEEN + 1))" "$JOURNAL" \
        | grep -E "task=${SIG}([^0-9A-Za-z]|$)" || true)"
      # beats first (fix-round C1): review_gate transitions pulse but NEVER
      # end the watch — they are mid-flight signal, not lane termination.
      beats="$(printf '%s' "$own" | grep -E "$PULSE_PAT" || true)"
      if [[ -n "$beats" ]]; then
        while IFS= read -r l; do
          detail="$(printf '%s' "$l" | sed -E 's/^.*\[[a-z]+\] //' | cut -c1-60)"
          _pulse "review_gate" "$detail"
        done <<< "$beats"
      fi
      SEEN="$n"
      _ledger_save "$SEEN"
      # exit ONLY on a true terminal for this sig (fix-round C1/H1): dedup
      # rows and review_gate lines are already excluded by EXIT_PAT.
      term="$(printf '%s' "$own" | grep -E "$EXIT_PAT" || true)"
      if [[ -n "$term" ]]; then
        while IFS= read -r l; do
          kind="$(printf '%s' "$l" | grep -oE "$KIND_PAT" | head -n1)"
          detail="$(printf '%s' "$l" | sed -E 's/^.*\[[a-z]+\] //' | cut -c1-60)"
          _pulse "${kind:-dispatch_terminal}" "$detail"
        done <<< "$term"
        printf '[lane-pulse-watch] %s terminal, exiting\n' "$SIG" >&2
        exit 0
      fi
    elif (( n < SEEN )); then
      # rotation/truncate — restart from line 1 (replay-safe again)
      printf '[lane-pulse-watch] %s rotated (lines %s < seen %s), re-reading\n' "$SIG" "$n" "$SEEN" >&2
      SEEN=0
      _ledger_save 0
    fi
  else
    _now="$(date +%s)"
    if (( _missing_since == 0 )); then
      _missing_since="$_now"
    elif (( _now - _missing_since >= GRACE_S )); then
      printf '[lane-pulse-watch] %s journal missing %ss, exiting\n' "$SIG" "$GRACE_S" >&2
      exit 0
    fi
  fi
  _now="$(date +%s)"
  if (( _now - _started >= TIMEOUT )); then
    printf '[lane-pulse-watch] %s timeout after %ss, exiting\n' "$SIG" "$TIMEOUT" >&2
    exit 0
  fi
  sleep "$INTERVAL"
done
