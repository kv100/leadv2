#!/usr/bin/env bash
# leadv2-portable-lock.sh -- advisory file lock that works with or without flock(1).
#
# macOS ships no flock(1) (it's a util-linux binary); the acceptance PATH for the
# SwiftBar widget (`env -i PATH=/usr/bin:/bin`) never has it even on a dev machine
# that does (homebrew's flock lives outside that PATH). Every caller in this repo
# already does `( flock -w N -x 9 || exit 3 ; ... ) 9>"$lockf"` -- same acquire
# contract (0=acquired, 3=timeout), same fd-9/subshell release scope. This file
# swaps ONLY the acquire primitive; it never moves a critical-section boundary.
#
# Usage (inside the existing `( ... ) 9>"$lockf"` subshell):
#   lv2_lock_wait "$lockf" 10 || exit 3
#   ...critical section...
# Release is automatic: on real flock, fd 9 closing (subshell exit) releases it.
# On the mkdir fallback, an EXIT trap set by lv2_lock_wait removes the lock dir
# when the subshell exits (normal exit OR a kill -9 of the shell that owns the
# trap -- POSIX runs EXIT traps on any shell termination it can catch; the
# staleness reaper below is the backstop for the cases it can't, e.g. SIGKILL of
# the whole process group).

LV2_LOCK_STALE_S="${LEADV2_LOCK_STALE_S:-120}"

# lv2_lock_wait <lockfile> <timeout_secs> -> rc0 acquired, rc3 timeout
lv2_lock_wait() {
  local lockf="$1" timeout="${2:-10}"
  if command -v flock >/dev/null 2>&1; then
    flock -w "${timeout}" -x 9
    return $?
  fi
  _lv2_lock_wait_mkdir "${lockf}" "${timeout}"
}

# lv2_lock_release <lockfile> -- idempotent; no-op under real flock (fd-9 close
# already released it). Only meaningful for the mkdir fallback.
lv2_lock_release() {
  local lockf="$1"
  rm -rf "${lockf}.d" 2>/dev/null || true
}

_lv2_lock_stale() {  # <lockdir> -> 0 if stale (reap-eligible)
  local dir="$1" pidfile="${1}/pid" pid mtime now age
  if [[ -f "${pidfile}" ]]; then
    pid="$(cat "${pidfile}" 2>/dev/null || true)"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      : # holder still alive -- fall through to the mtime check as a belt-and-braces cap
    else
      return 0  # holder pid missing or dead -> stale
    fi
  fi
  mtime="$(_lv2_lock_mtime "${dir}")"
  [[ -z "${mtime}" ]] && return 1
  now="$(date +%s 2>/dev/null || printf '0')"
  age=$(( now - mtime ))
  [[ ${age} -ge ${LV2_LOCK_STALE_S} ]]
}

_lv2_lock_mtime() {  # <path> -> epoch mtime, best-effort across BSD/GNU stat
  local path="$1"
  [[ "$(uname -s)" == "Darwin" ]] && stat -f '%m' "${path}" 2>/dev/null || stat -c '%Y' "${path}" 2>/dev/null || printf ''
}

_lv2_sleep_step() {
  # Fractional sleep if the platform supports it; else 1s granularity (§2.1.3).
  if sleep 0.1 2>/dev/null; then
    return 0
  fi
  sleep 1
}

_lv2_lock_wait_mkdir() {  # <lockfile> <timeout_secs> -> rc0 acquired, rc3 timeout
  local lockf="$1" timeout="$2" dir="${1}.d" start now deadline step_is_fractional=1
  dir="${lockf}.d"
  start="$(date +%s 2>/dev/null || printf '0')"
  deadline=$(( start + timeout ))
  sleep 0.1 2>/dev/null || step_is_fractional=0
  while true; do
    if mkdir "${dir}" 2>/dev/null; then
      printf '%s' "$$" > "${dir}/pid" 2>/dev/null || true
      trap 'lv2_lock_release "'"${lockf}"'"' EXIT
      return 0
    fi
    if _lv2_lock_stale "${dir}"; then
      rm -rf "${dir}" 2>/dev/null || true
      continue
    fi
    now="$(date +%s 2>/dev/null || printf '0')"
    if [[ ${now} -ge ${deadline} ]]; then
      return 3
    fi
    if [[ ${step_is_fractional} -eq 1 ]]; then
      sleep 0.1 2>/dev/null || sleep 1
    else
      sleep 1
    fi
  done
}
