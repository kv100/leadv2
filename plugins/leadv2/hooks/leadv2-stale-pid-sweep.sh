#!/usr/bin/env bash
# SessionStart reconciliation.  Lane state owns PID identity; this hook must
# never delete rows with bare kill -0 because a reused PID is not a worker.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
STATE_LIB="${SCRIPT_DIR}/../scripts/lib/leadv2-lane-state.sh"

if [[ -f "$STATE_LIB" ]]; then
  # shellcheck source=../scripts/lib/leadv2-lane-state.sh
  source "$STATE_LIB"
  LEADV2_PROJECT_ROOT="$PROJECT_ROOT" lane_reconcile >/dev/null 2>&1 || \
    printf '[leadv2-stale-pid-sweep] lane reconciliation failed; preserving registry\n' >&2
fi

# STALE-SWEEPER-WIRING-01: this hook is the stale sweeper's invoker.
# leadv2-stale-sweeper.sh is the sole writer of the `stale` flag — the flag
# fanout's selection filter counts on (not s.get("stale")) — and until this
# call it ran from nowhere: the live registry held 40 rows with zero stale
# against hard_limit 3, so every fanout launch was refused "hard_limit
# reached" while ~37 rows were provably dead.
#
# Two-stage invocation:
#   1. Synchronous --mark-only: the sweep's essential part (registry stale
#      marks; ~5s) runs inside the hook timeout and its [sweeper] lines are
#      visible in session context. A failure is logged, never blocking.
#   2. Detached full sweep: the slow tail (orphan-worktree detection,
#      dead-worktree GC over ~100 worktrees — measured minutes 2026-09-06 —
#      graveyard scan, budget reset, outcome-watch --sweep) runs via
#      nohup+disown (same pattern as leadv2-lane-watch-v2.sh --arm-from-hook)
#      so it is never truncated by a hook timeout and never delays session
#      start. Output appends to /tmp/leadv2-stale-sweeper.<repo>.log.
#      LEADV2_SSWEEP_NO_DETACH=1 (tests) suppresses stage 2.
SWEEPER="${SCRIPT_DIR}/../scripts/leadv2-stale-sweeper.sh"
# CONTROL-PLANE-SATURATES-01: reap orphans of DEAD sessions (pulse loops,
# stuck sweeps, beat-loops) at every session start — bounded, pure bash/ps,
# positive-death-only (kill -0 three answers; transcript-age oracle).
REAPER="${SCRIPT_DIR}/../scripts/leadv2-orphan-reaper.sh"
if [[ -x "$REAPER" ]]; then
  LEADV2_PROJECT_ROOT="$PROJECT_ROOT" bash "$REAPER" \
    || printf '[leadv2-stale-pid-sweep] orphan reaper failed rc=%s (non-blocking)\n' "$?" >&2
fi
if [[ -x "$SWEEPER" ]]; then
  LEADV2_PROJECT_ROOT="$PROJECT_ROOT" bash "$SWEEPER" --non-interactive --mark-only || \
    printf '[leadv2-stale-pid-sweep] stale sweep (mark-only) failed rc=%s (non-blocking)\n' "$?" >&2
  if [[ -z "${LEADV2_SSWEEP_NO_DETACH:-}" ]]; then
    # CONTROL-PLANE-SATURATES-01: dedup belongs in the SPAWNER, not in a
    # later kill-list. Before nohup'ing the slow full sweep, check the
    # sweeper's single-flight lock (same control-plane path the sweeper
    # itself gates on) for a live owner — if one runs, skip the spawn
    # entirely. The sweeper's own mkdir gate stays authoritative (this
    # pre-check is advisory only: a lost race just spawns a bash that exits
    # in <1s). Without this, every SessionStart of every live session bred
    # another concurrent sweep (measured 2026-09-06: 8 sweepers, 13
    # cleanups, 11 lane-liveness pythons, load 167 on 10 cores).
    _ssw_should_spawn=1
    _ssw_lock=""
    _ssw_yaml="$(cd "$PROJECT_ROOT" 2>/dev/null && bash "${SCRIPT_DIR}/../scripts/leadv2-state-path.sh" --no-link active.yaml 2>/dev/null || true)"
    if [[ -n "$_ssw_yaml" ]]; then
      _ssw_lock="$(dirname "$_ssw_yaml")/.stale-sweeper-full.lock"
    fi
    if [[ -n "$_ssw_lock" && -d "$_ssw_lock" ]]; then
      _ssw_owner="$(cat "${_ssw_lock}/owner.pid" 2>/dev/null || true)"
      if [[ "$_ssw_owner" =~ ^[0-9]+$ ]] && kill -0 "$_ssw_owner" 2>/dev/null; then
        _ssw_should_spawn=0
        printf '[leadv2-stale-pid-sweep] full sweep already running (pid=%s) — skipping detached spawn\n' "$_ssw_owner" >&2
      fi
    fi
    if [[ "$_ssw_should_spawn" == "1" ]]; then
      _ssw_log="/tmp/leadv2-stale-sweeper.$(basename "$PROJECT_ROOT").log"
      nohup env LEADV2_PROJECT_ROOT="$PROJECT_ROOT" bash "$SWEEPER" --non-interactive \
        >>"$_ssw_log" 2>&1 &
      disown 2>/dev/null || true
    fi
  fi
fi
# end STALE-SWEEPER-WIRING-01 wiring
exit 0
