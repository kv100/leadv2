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
if [[ -x "$SWEEPER" ]]; then
  LEADV2_PROJECT_ROOT="$PROJECT_ROOT" bash "$SWEEPER" --non-interactive --mark-only || \
    printf '[leadv2-stale-pid-sweep] stale sweep (mark-only) failed rc=%s (non-blocking)\n' "$?" >&2
  if [[ -z "${LEADV2_SSWEEP_NO_DETACH:-}" ]]; then
    _ssw_log="/tmp/leadv2-stale-sweeper.$(basename "$PROJECT_ROOT").log"
    nohup env LEADV2_PROJECT_ROOT="$PROJECT_ROOT" bash "$SWEEPER" --non-interactive \
      >>"$_ssw_log" 2>&1 &
    disown 2>/dev/null || true
  fi
fi
# end STALE-SWEEPER-WIRING-01 wiring
exit 0
