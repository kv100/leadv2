#!/usr/bin/env bash
set -euo pipefail
# leadv2-lane-report.sh — ask "what did this lane produce?" from either name.
#
# Usage: leadv2-lane-report.sh <founder-task-id|sig8|dispatch-<sig8>> [--worktrees]
# Exit: 0 found · 1 none · 2 unknown · 3 usage.
#
# The search path and coverage are part of the answer, not debug flags: every
# location consulted prints its own labelled line even when it contributed
# nothing (census §5 — a location that prints zero bytes lets the next
# location's output slide into its slot, which is how one lane's answer was
# read as the answer to a different question).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/leadv2-lane-address.sh
. "${SCRIPT_DIR}/lib/leadv2-lane-address.sh"

if [[ $# -lt 1 ]]; then
  printf 'Usage: leadv2-lane-report.sh <founder-task-id|sig8|dispatch-<sig8>> [--worktrees]\n' >&2
  exit 3
fi

QUERY="$1"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
export PROJECT_ROOT

rc=0
lane_address_resolve "$QUERY" "${2:-}" || rc=$?

case "$LA_RESULT" in
  usage)
    printf 'Usage: leadv2-lane-report.sh <founder-task-id|sig8|dispatch-<sig8>> [--worktrees]\n' >&2
    exit 3
    ;;
  found)
    printf 'lane: %s\n' "$QUERY"
    printf 'resolved: tid=%s sig8=%s via=%s\n' "${LA_TID:--}" "${LA_SIG8:--}" "${LA_VIA:-direct}"
    ;;
esac

printf 'searched:\n'
printf '  registry   docs/leadv2/active.yaml                                  -> %s rows\n' "$LA_REGISTRY_ROWS"
printf '  receipts   %s dispatch dirs, %s with a receipt                    -> %s task_id match\n' \
  "$LA_DISPATCH_SEEN" "$LA_RECEIPT_SEEN" "$LA_RECEIPT_MATCH"
printf '  missions   %s dispatch dirs, %s with lane-mission.md              -> %s H1 match\n' \
  "$LA_DISPATCH_SEEN" "$LA_MISSION_SEEN" "$LA_MISSION_MATCH"
printf '  eponymous  docs/handoff/%s/  -> %s\n' "${LA_TID:-$LA_SIG8}" "$LA_EPON_STATE"
if [[ "$LA_WT_SEARCHED" -eq 1 ]]; then
  printf '  worktrees  searched %s worktree handoff root(s)\n' "$LA_WT_ROOTS"
else
  printf '  worktrees  NOT SEARCHED (pass --worktrees)\n'
fi

case "$LA_RESULT" in
  found)
    printf 'coverage: %s\n' "$LA_COVERAGE_LINE"
    printf 'found:\n'
    printf '%s' "$LA_FOUND_ROWS"
    printf 'result: found %s\n' "$LA_NFOUND"
    exit 0
    ;;
  none)
    printf 'result: none (searched: docs/leadv2/active.yaml [%s rows], %s receipts [no task_id match],\n' \
      "$LA_REGISTRY_ROWS" "$LA_RECEIPT_SEEN"
    printf '        %s missions [no H1 match], docs/handoff/%s/ [%s]; 0 unattributable dirs remain;\n' \
      "$LA_MISSION_SEEN" "${LA_TID:-$LA_SIG8}" "$LA_EPON_STATE"
    if [[ "$LA_WT_SEARCHED" -eq 1 ]]; then
      printf '        searched: %s worktree root(s))\n' "$LA_WT_ROOTS"
    else
      printf '        NOT searched: .claude/worktrees/*/docs/handoff/)\n'
    fi
    exit 1
    ;;
  unknown)
    printf 'result: unknown (%s;\n' "$LA_REASON"
    printf '        searched: docs/leadv2/active.yaml [%s rows], %s receipts, %s missions,\n' \
      "$LA_REGISTRY_ROWS" "$LA_RECEIPT_SEEN" "$LA_MISSION_SEEN"
    printf '        docs/handoff/%s/ [%s]; ' "${LA_TID:-$LA_SIG8}" "$LA_EPON_STATE"
    if [[ "$LA_WT_SEARCHED" -eq 1 ]]; then
      printf 'searched: %s worktree root(s))\n' "$LA_WT_ROOTS"
    else
      printf 'NOT searched: .claude/worktrees/*/docs/handoff/)\n'
    fi
    exit 2
    ;;
esac
printf 'result: internal-error (LA_RESULT empty)\n' >&2
exit 3
