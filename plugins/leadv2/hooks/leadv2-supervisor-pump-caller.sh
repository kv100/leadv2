#!/usr/bin/env bash
# hooks/leadv2-supervisor-pump-caller.sh — UserPromptSubmit throttled
# pump-caller (T-i, SUPERVISOR-AUDIT-01 mission-c, design-map row 7/point 7).
# leadv2-backlog-pump.sh already runs every tick INSIDE
# leadv2-supervise-loop.sh; this hook is the fallback caller for an
# interactive supervise session that isn't running that background loop —
# same auto-refill effect, triggered off the lead's own turns.
#
# ACTIVE only for the exact session owning a LIVE .supervise-active sentinel
# (same resolve+pid-scope primitive as leadv2-supervise-fanout-guard.sh /
# leadv2-supervisor-guard.sh). Throttle: a last-run stamp in the same
# control-plane dir as the sentinel, >=180s between runs, flock-guarded so
# two near-simultaneous turns can't both fire. Runs leadv2-backlog-pump.sh
# once per throttle window.
#
# LIVE-LOOP NO-OP (fix round 1, review-verdict BLOCKING #4):
# leadv2-supervise-loop.sh already calls this exact pump (`check`) itself on
# every close/idle cycle via `_run_pump_on_close` — this hook exists ONLY as
# the fallback for an interactive session that is NOT running that
# background loop. Previously it never checked for the loop's own
# `.supervise-loop.json` liveness, so the two callers ran side by side: their
# mkdir-based locks only serialize a single `check` invocation against
# itself, they do not make the pump's own capacity read (active.yaml
# `sessions` count) consistent across TWO independently-scheduled callers.
# Sequential calls from each caller could each observe stale headroom and
# refill past `active.yaml`'s hard cap. Fix: before doing anything, check the
# SAME sentinel primitive used elsewhere (.supervise-loop.json, liveness via
# os.kill(pid,0)) — if the loop is live, it already owns the pump; no-op.
#
# COUNTED-LANE RESERVATION (fix round 1, BLOCKING #4, second half): when this
# hook DOES own the fallback, the pump dispatch must reserve its lane before
# this hook returns, not after. The prior version ran the pump via
# `nohup ... &` + `disown`, so the throttle stamp (and thus "you may call
# again") was written before `leadv2-backlog-pump.sh check` had even started
# — let alone acquired its own PUMP_LOCK_DIR mkdir-lock or done its
# active.yaml capacity read. A second UserPromptSubmit past the 180s window
# could then race a still-starting backgrounded check with a fresh one and
# both could see "capacity free". The call is made SYNCHRONOUSLY, bounded by
# PUMP_CALL_TIMEOUT_S — the pump's own lock/claim/lane-reservation
# bookkeeping has fully completed before this hook, and therefore the turn,
# returns; see the FIX2 block just above the call site for why the actual
# leadv2-dispatch-code.sh spawn itself is now deferred (async) rather than
# waited on inline, and why the default timeout dropped from 20s to 3s.
#
# Kill-switches: LEADV2_SUPERVISOR_PUMP_CALLER=0 disables this hook only.
# LEADV2_BACKLOG_PUMP=0 (existing pump kill-switch) is also honored here so a
# disabled pump never spawns a background process at all.
set -uo pipefail
trap 'exit 0' ERR

[[ "${LEADV2_SUPERVISOR_PUMP_CALLER:-1}" == "0" ]] && exit 0
[[ "${LEADV2_BACKLOG_PUMP:-1}" == "0" ]] && exit 0
[[ -n "${LEADV2_ASYNC_QUESTIONS:-}" ]] && exit 0

INPUT="$(cat 2>/dev/null || true)"
CWD_FROM_INPUT="$(printf -- '%s' "$INPUT" | python3 -c "
import sys, json
try:
    print(json.loads(sys.stdin.read()).get('cwd', '') or '')
except Exception:
    print('')
" 2>/dev/null || true)"
[[ -z "$CWD_FROM_INPUT" ]] && CWD_FROM_INPUT="$PWD"

if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -f "${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-state-path.sh" ]]; then
  RESOLVER="${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-state-path.sh"
  REGISTRY="${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-active-registry.sh"
  PUMP_BIN="${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-backlog-pump.sh"
else
  _LV2_D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  RESOLVER="${_LV2_D}/../scripts/leadv2-state-path.sh"
  REGISTRY="${_LV2_D}/../scripts/leadv2-active-registry.sh"
  PUMP_BIN="${_LV2_D}/../scripts/leadv2-backlog-pump.sh"
fi
[[ -x "$RESOLVER" && -x "$PUMP_BIN" ]] || exit 0

# Live-loop no-op (fix #4): leadv2-supervise-loop.sh already pumps on its own
# cadence via the identical .supervise-loop.json sentinel/liveness primitive
# used everywhere else in this plugin. If that loop is live, it owns the
# pump — this fallback caller must not also fire.
LOOP_SENTINEL="$(PROJECT_ROOT="$CWD_FROM_INPUT" "$RESOLVER" --no-link .supervise-loop.json 2>/dev/null || true)"
if [[ -n "$LOOP_SENTINEL" && -f "$LOOP_SENTINEL" ]]; then
  LOOP_LIVE="$(python3 -c "
import sys, json, os
path = sys.argv[1]
try:
    with open(path, encoding='utf-8') as fh:
        d = json.load(fh) or {}
    pid = d.get('pid')
    if pid is None:
        print('DEAD'); sys.exit(0)
    try:
        os.kill(int(pid), 0)
        print('LIVE')
    except (TypeError, ValueError, ProcessLookupError, PermissionError):
        print('DEAD')
except Exception:
    print('DEAD')
" "$LOOP_SENTINEL" 2>/dev/null || printf -- 'DEAD')"
  [[ "$LOOP_LIVE" == "LIVE" ]] && exit 0
fi

SENTINEL="$(PROJECT_ROOT="$CWD_FROM_INPUT" "$RESOLVER" --no-link .supervise-active 2>/dev/null || true)"
[[ -z "$SENTINEL" || ! -f "$SENTINEL" ]] && exit 0

SENTINEL_INFO="$(python3 -c "
import sys, json, os
path = sys.argv[1]
try:
    with open(path, encoding='utf-8') as fh:
        d = json.load(fh) or {}
    pid = d.get('pid')
    if pid is None:
        print('DEAD'); print(''); sys.exit(0)
    try:
        os.kill(int(pid), 0)
        print('LIVE'); print(int(pid))
    except (TypeError, ValueError, ProcessLookupError, PermissionError):
        print('DEAD'); print('')
except Exception:
    print('DEAD'); print('')
" "$SENTINEL" 2>/dev/null || printf -- 'DEAD\n\n')"

SENTINEL_STATUS="$(printf -- '%s' "$SENTINEL_INFO" | sed -n '1p')"
SENTINEL_PID="$(printf -- '%s' "$SENTINEL_INFO" | sed -n '2p')"

if [[ "$SENTINEL_STATUS" != "LIVE" ]]; then
  rm -f "$SENTINEL" 2>/dev/null || true
  exit 0
fi

MY_PID=""
if [[ -f "$REGISTRY" ]]; then
  # shellcheck source=leadv2-active-registry.sh
  source "$REGISTRY"
  MY_PID="$(_lv2_durable_pid 2>/dev/null || true)"
fi
[[ -z "$MY_PID" || "$MY_PID" != "$SENTINEL_PID" ]] && exit 0

STATE_DIR="$(dirname "$SENTINEL")"
STAMP="${STATE_DIR}/.pump-caller-last-run"
LOCK="${STATE_DIR}/.pump-caller.lock"

exec 9>"$LOCK" || exit 0
command -v flock >/dev/null 2>&1 && { flock -n 9 || exit 0; }

NOW="$(date +%s)"
LAST=0
[[ -f "$STAMP" ]] && LAST="$(cat "$STAMP" 2>/dev/null || echo 0)"
[[ "$LAST" =~ ^[0-9]+$ ]] || LAST=0

if (( NOW - LAST < 180 )); then
  exit 0
fi

printf '%s' "$NOW" > "$STAMP" 2>/dev/null || true

# Synchronous, bounded (fix #4 counted-lane reservation): the pump's own
# PUMP_LOCK_DIR mkdir-lock and active.yaml capacity read must complete BEFORE
# this hook — and the turn — returns, so any lane it reserves is committed
# ahead of the next throttled call, not racing it.
#
# FIX2 (SUPERVISOR-AUDIT-01 review-verdict-2 NM1): hooks.json gives this hook
# a 5s HOST timeout that this script cannot see or extend — a synchronous
# wait bounded at the prior default of 20s could be killed by the host
# mid-dispatch, ambiguous claim/lane state (see B5). Two changes close that
# gap without touching hooks.json (out of this fix's file scope):
#   1. LEADV2_BACKLOG_PUMP_ASYNC_DISPATCH=1 -- the pump still reserves the
#      active.yaml lane (pid=null placeholder) synchronously, but backgrounds
#      the dispatch call itself (detached re-invocation, setsid when
#      available) so `check` returns as soon as bookkeeping — claim, lane
#      reserve, per-candidate git/quota checks — is done, never waiting on
#      leadv2-dispatch-code.sh's own call.
#   2. PUMP_CALL_TIMEOUT_S default lowered from 20s to 3s: with (1) in
#      effect, the bounded operation `check` performs before returning is
#      bookkeeping-only (fast, file-local) — 3s leaves headroom under the
#      5s host ceiling for this script's own preamble (input parse, sentinel
#      resolve, lock) which already runs before this line.
export LEADV2_BACKLOG_PUMP_ASYNC_DISPATCH=1
PUMP_CALL_TIMEOUT_S="${LEADV2_SUPERVISOR_PUMP_CALLER_TIMEOUT_S:-3}"
if command -v timeout >/dev/null 2>&1; then
  timeout "$PUMP_CALL_TIMEOUT_S" "$PUMP_BIN" >/dev/null 2>&1 || true
else
  "$PUMP_BIN" >/dev/null 2>&1 || true
fi

exit 0
