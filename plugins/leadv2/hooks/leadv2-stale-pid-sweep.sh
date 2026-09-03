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
exit 0
