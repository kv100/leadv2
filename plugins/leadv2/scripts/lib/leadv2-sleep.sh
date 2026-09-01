#!/usr/bin/env bash
# FORK-STORM-KILLS-HOOKS-01 - fork-free wait + orphan-proof child reaping.
#
# The 2026-09-01 fork storm (638 processes, 56 orphaned `sleep` at PPID 1) had
# one root cause per orphan: a watcher was killed while its `sleep N` child was
# mid-wait, and the child was reparented to launchd and survived forever. Two
# fixes, both in this library so every poll loop inherits them:
#
#   1. leadv2_wait SECS waits WITHOUT forking. Bash 3.2 has no sleep builtin,
#      but `read -t` on a never-EOF fd is a kernel timed wait: zero children,
#      so a SIGKILLed watcher cannot leave an orphan behind - there is nothing
#      to orphan. Cost: one mkfifo per watcher lifetime (first call), zero
#      forks per wait after that.
#   2. leadv2_reap_arm installs EXIT/TERM/INT/HUP traps that kill every child
#      the watcher spawned through leadv2_spawn, for the watchers that must
#      keep real child processes (codex runs, monitors).
#
# Sourced, not executed. Does not change shell options; every API fails open.
# Bash 3.2 only: no mapfile, no read -t fractions (integer seconds).

LEADV2_SLEEP_VERSION=1
LEADV2_CHILD_PIDS="${LEADV2_CHILD_PIDS:-}"

# leadv2_wait SECS - fork-free timed wait, integer seconds. Sleep semantics:
# returns 0 when the wait is over, whatever ended it. (read -t returns 1 on
# timeout under bash 3.2 AND 5.x - measured 2026-09-01 - and the fifo is held
# read-write, so it can never deliver EOF; every rc means the wait is done.)
# Best effort: if the fifo or fd cannot be set up, fall back to `sleep` - a
# degraded wait that forks once is better than a watcher that spins or dies.
leadv2_wait() {
  local _secs="${1:-0}"
  case "$_secs" in ''|*[!0-9]*) _secs=0 ;; esac
  [ "$_secs" -le 0 ] && return 0
  if [ -z "${LEADV2_WAIT_FD:-}" ]; then
    local _fifo="${TMPDIR:-/tmp}/leadv2-wait.$$.fifo"
    if command mkfifo "$_fifo" 2>/dev/null && exec 3<>"$_fifo" 2>/dev/null; then
      LEADV2_WAIT_FD=3
      # The open fd keeps the fifo alive after the name is gone, and no name
      # in /tmp outlives the watcher.
      command rm -f "$_fifo" 2>/dev/null
    else
      command sleep "$_secs"
      return 0
    fi
  fi
  read -t "$_secs" _dummy <&"$LEADV2_WAIT_FD" || :
  return 0
}

# leadv2_spawn CMD... - run CMD in the background and remember its pid so
# leadv2_reap can kill it on exit. Returns 127 if there is nothing to run,
# mirroring sh's not-found status.
leadv2_spawn() {
  [ "$#" -eq 0 ] && return 127
  "$@" &
  LEADV2_CHILD_PIDS="$LEADV2_CHILD_PIDS $!"
  return 0
}

# leadv2_reap - TERM every spawned child, give it one second, then KILL the
# survivors. All builtins: the reaping itself cannot fail by forking.
leadv2_reap() {
  local _pid _left=""
  for _pid in ${LEADV2_CHILD_PIDS:-}; do
    kill -TERM "$_pid" 2>/dev/null && _left="$_left $_pid"
  done
  if [ -n "$_left" ]; then
    leadv2_wait 1
    for _pid in $_left; do
      kill -KILL "$_pid" 2>/dev/null
    done
  fi
  LEADV2_CHILD_PIDS=""
  wait 2>/dev/null
  return 0
}

# leadv2_reap_arm - install the exit/signal traps. TERM/INT/HUP reap first and
# then exit with the kill status so a supervisor still sees "was killed".
leadv2_reap_arm() {
  trap 'leadv2_reap' EXIT
  trap 'leadv2_reap; exit 143' TERM
  trap 'leadv2_reap; exit 130' INT
  trap 'leadv2_reap; exit 129' HUP
}
