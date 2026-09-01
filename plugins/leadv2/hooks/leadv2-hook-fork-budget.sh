#!/usr/bin/env bash
# FORK-STORM-KILLS-HOOKS-01 - answer "are we near the fork wall right now?" in
# one cheap command, so the 2026-09-01 diagnosis session (638 processes, 56
# orphaned `sleep` at PPID 1, fork() returning EAGAIN mid-session) is never
# done by hand again. Read-only by default; `--sweep` kills ONLY processes
# whose comm is sleep and whose PPID is 1 - the exact orphan class the storm
# produced; it never touches a live session tree.
#
# Output: key=value lines on stdout, human notes on stderr.
# Exit codes: 0 healthy (under 80% of the user process ceiling), 1 within the
# wall band, 2 could not measure. Two ps passes worst case, else builtins.

set -u

SWEEP=0
[ "${1:-}" = "--sweep" ] && SWEEP=1

DEGRADE_LOG="${LEADV2_DEGRADE_LOG:-${TMPDIR:-/tmp}/leadv2-hook-degrade.log}"

STATS="$(ps -axo user=,ppid=,comm= 2>/dev/null | awk -v me="$(id -un)" '
  { total++
    if ($1 == me) mine++
    if ($1 == me && $3 ~ /claude/) claudes++
    if ($2 == 1 && $3 ~ /sleep/) orphans++
  }
  END {
    printf "procs_total=%d\nprocs_mine=%d\nprocs_claude=%d\norphan_sleep_ppid1=%d\n", total, mine+0, claudes+0, orphans+0
  }
')" || STATS=""
if [ -z "$STATS" ]; then
  echo "fork-budget: could not measure (ps/awk failed)" >&2
  exit 2
fi
# shellcheck disable=SC1090
eval "$STATS"

LIMIT="$(ulimit -u 2>/dev/null || echo 0)"

if [ "${orphan_sleep_ppid1:-0}" -gt 0 ]; then
  if [ "$SWEEP" -eq 1 ]; then
    ps -axo pid=,ppid=,comm= 2>/dev/null | awk '$2==1 && $3 ~ /sleep/ {print $1}' |
      while IFS= read -r _opid; do
        kill -TERM "$_opid" 2>/dev/null && echo "fork-budget: swept orphan sleep pid=$_opid" >&2
      done
    orphan_sleep_ppid1="$(ps -axo ppid=,comm= 2>/dev/null | awk '"'"'$1==1 && $2 ~ /sleep/'"'"' | wc -l | tr -d " ")"
  else
    echo "fork-budget: ${orphan_sleep_ppid1} orphaned sleep at ppid=1; rerun with --sweep to reap" >&2
  fi
fi

if [ -f "$DEGRADE_LOG" ]; then
  hook_degrade_lines="$(wc -l < "$DEGRADE_LOG" | tr -d " ")"
else
  hook_degrade_lines=0
fi

echo "procs_total=${procs_total:-0}"
echo "procs_mine=${procs_mine:-0}"
echo "procs_claude=${procs_claude:-0}"
echo "orphan_sleep_ppid1=${orphan_sleep_ppid1:-0}"
echo "procs_limit_user=${LIMIT:-0}"
echo "hook_degrade_lines=${hook_degrade_lines:-0}"

if [ "${LIMIT:-0}" -gt 0 ] && [ "${procs_mine:-0}" -ge $(( LIMIT * 80 / 100 )) ]; then
  echo "verdict=NEAR-WALL (procs_mine ${procs_mine:-0} >= 80% of ${LIMIT})"
  exit 1
fi
echo "verdict=healthy"
exit 0
