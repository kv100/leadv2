#!/usr/bin/env bash
# leadv2-lane-worker-alive.sh — D4-NO-PATH-LOSES-WORK-01 liveness authority.
#
# WHY: the sweeper this file backs (leadv2-orphan-checkpoint.sh) runs OUTSIDE
# every lane's own process tree, on purpose — the three checkpoint mechanisms
# that already existed (leadv2_worker_commit_epilogue, pc_stop_gate_autocommit,
# leadv2-turncap-checkpoint-commit.sh) all run INSIDE the worker's process, so
# a SIGKILL of that process (or the whole host tree) takes the checkpoint down
# with it. An external sweeper needs a liveness signal it can evaluate from
# OUTSIDE that tree, and the two obvious ones both lie: file mtime goes silent
# for long stretches while a worker is mid-turn (a live worker can look
# "stale" for many minutes), and a bare `pgrep <lane-name>` both false-matches
# an unrelated process whose argv text happens to contain the lane id AND
# false-misses a live worker whose wrapper argv never names the lane at all.
# The one signal checkable from outside the tree that is NOT spoofed by
# argv text is the worker's own current working directory: every coder
# wrapper in this repo (glm-coder.sh / kimi-coder.sh / freepool-coder.sh /
# claude-subsession.sh) `cd`s into the lane worktree before spawning the
# model process, so a live worker's cwd sits inside that worktree path by
# construction.
#
# Four named false-answer cases this module exists to survive (D4 brief +
# lead addendum 2):
#   false-zero:  lsof returns rc=0 with EMPTY output (sandboxed/restricted
#                lsof, or a transient race) — must NOT read as "nobody is
#                alive"; fails closed to ALIVE exactly like an lsof error.
#   false-life:  an OS can reuse a pid number after the original process
#                exits, so `kill -0 <stale-pid>` alone can report ALIVE for
#                a process that is not the worker at all. A recorded PID
#                handle is one signal, not proof by itself — see
#                lv2_lane_alive_combined.
#   mirror-dead: two worktrees whose names are string-prefixes of each other
#                (".claude/worktrees/abc" vs ".claude/worktrees/abc-def")
#                must never cross-match — every prefix check below requires
#                an exact path or a "/"-bounded child, never a bare string
#                prefix.
#   several-handles-one-alive: a lane with MULTIPLE recorded pid handles is
#                ALIVE if ANY one is alive, DEAD only if ALL are dead — never
#                a last-handle-wins or first-handle-wins shortcut.
#
# Bash 3.2 safe: no associative arrays, no ${x^^}, no mapfile. D5: no
# iteration in this file ever uses a bare unquoted `for p in $pids` — zsh
# does NOT word-split an unquoted variable in a for-loop the way bash does,
# so that idiom silently iterates ONCE over the whole blob under zsh instead
# of once per pid (a real, already-reproduced false "everyone is dead"
# verdict). Every multi-value iteration here uses `while IFS= read -r` over
# a newline-separated list instead, which is byte-identical under bash and
# zsh — the test suite runs this file under both and fails if they disagree.
#
# This file is sourced, never executed.

LV2_LANE_ALIVE_PRIMED=0
LV2_LANE_ALIVE_FAILCLOSED=0
LV2_LANE_ALIVE_CWD_FILE=""

# _lv2_lane_realpath <path> -> stdout: canonical (symlink-resolved) path, or
# the input unchanged if python3 is unavailable. GATE-WRONG-ROOT-FALSE-DEAD-01
# class bug: the real OS `lsof` always reports a process's cwd fully resolved
# (macOS /tmp -> /private/tmp, $TMPDIR -> /private/var/...), so comparing a
# caller-supplied wt_path against that output without the SAME normalization
# false-negatives on every host where the worktree root was reached through a
# symlink -- exactly the "path through symlink is not the path git knows"
# trap this repo has hit twice before. No portable `readlink -f` on macOS;
# python3's os.path.realpath is this repo's existing convention for this
# exact problem (lib/leadv2-e2e-root.sh's _lv2_realpath).
_lv2_lane_realpath() {
  local p="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "${p}" 2>/dev/null && return 0
  fi
  printf '%s\n' "${p}"
}

# lv2_lane_cwd_prime — one global `lsof -a -d cwd -Fpn` pass, cached for the
# rest of the process (a sweep run touches many worktrees; re-running lsof
# per-worktree would be both slow and racier). D2: fail-closed to ALIVE
# (LV2_LANE_ALIVE_FAILCLOSED=1) when lsof is missing, errors AND produces no
# output, times out, or (false-zero) returns rc=0 with truly empty output —
# a live host always has at least one process holding a cwd fd, so empty
# output is a signal the probe did not really run, never proof the machine
# is empty of workers.
lv2_lane_cwd_prime() {
  LV2_LANE_ALIVE_PRIMED=1
  LV2_LANE_ALIVE_FAILCLOSED=0
  LV2_LANE_ALIVE_CWD_FILE="$(mktemp "${TMPDIR:-/tmp}/leadv2-lane-cwd.XXXXXX" 2>/dev/null || true)"
  if [[ -z "${LV2_LANE_ALIVE_CWD_FILE}" ]]; then
    LV2_LANE_ALIVE_FAILCLOSED=1
    return 0
  fi

  if ! command -v lsof >/dev/null 2>&1; then
    LV2_LANE_ALIVE_FAILCLOSED=1
    return 0
  fi

  local timeout_s="${LEADV2_LANE_CWD_LSOF_TIMEOUT_S:-8}"
  local raw rc
  if command -v timeout >/dev/null 2>&1; then
    raw="$(timeout "${timeout_s}" lsof -a -d cwd -Fpn 2>/dev/null)"
    rc=$?
  else
    raw="$(lsof -a -d cwd -Fpn 2>/dev/null)"
    rc=$?
  fi
  # lsof commonly returns non-zero when it cannot read some processes' state
  # (sandboxed/restricted environments) while still emitting useful partial
  # output for the processes it COULD read — only fail-closed when a bad rc
  # is ALSO accompanied by empty output (nothing usable came back at all).
  if [[ "${rc}" != "0" && -z "${raw}" ]]; then
    LV2_LANE_ALIVE_FAILCLOSED=1
    return 0
  fi
  if [[ -z "${raw}" ]]; then
    # false-zero case: rc=0 but nothing enumerated.
    LV2_LANE_ALIVE_FAILCLOSED=1
    return 0
  fi

  # Parse -Fpn pairs: a "p<pid>" line followed by "n<name>" line(s) naming
  # the fds -a/-d selected (here, exactly the cwd fd). Emit "<pid>\t<cwd>".
  local pid=""
  while IFS= read -r line; do
    case "${line}" in
      p*) pid="${line#p}" ;;
      n*) [[ -n "${pid}" ]] && printf '%s\t%s\n' "${pid}" "${line#n}" >> "${LV2_LANE_ALIVE_CWD_FILE}" ;;
    esac
  done <<< "${raw}"
  return 0
}

# lv2_lane_cwd_reset — clear primed state. Test-only: forces a re-prime
# after swapping the stubbed `lsof` between cases in the same process.
lv2_lane_cwd_reset() {
  [[ -n "${LV2_LANE_ALIVE_CWD_FILE}" && -f "${LV2_LANE_ALIVE_CWD_FILE}" ]] && rm -f "${LV2_LANE_ALIVE_CWD_FILE}"
  LV2_LANE_ALIVE_PRIMED=0
  LV2_LANE_ALIVE_FAILCLOSED=0
  LV2_LANE_ALIVE_CWD_FILE=""
}

# lv2_lane_worker_alive <wt_path> -> rc0 ALIVE, rc1 DEAD.
# Prefix-matches primed cwd rows against <wt_path>, requiring a path
# boundary (mirror-dead case): "<wt_path>" itself or "<wt_path>/<anything>"
# — never a bare string prefix that a sibling worktree name could collide
# with.
lv2_lane_worker_alive() {
  local wt_path="$1"
  [[ -n "${wt_path}" ]] || return 0   # nothing to judge -- fail closed to ALIVE

  if [[ "${LV2_LANE_ALIVE_PRIMED}" != "1" ]]; then
    lv2_lane_cwd_prime
  fi
  if [[ "${LV2_LANE_ALIVE_FAILCLOSED}" == "1" ]]; then
    return 0   # D2: fail-closed to ALIVE
  fi
  [[ -s "${LV2_LANE_ALIVE_CWD_FILE}" ]] || return 1

  wt_path="$(_lv2_lane_realpath "${wt_path}")"
  while [[ "${wt_path}" == */ && "${wt_path}" != / ]]; do wt_path="${wt_path%/}"; done

  local _pid cwd
  while IFS=$'\t' read -r _pid cwd; do
    [[ -n "${cwd}" ]] || continue
    case "${cwd}" in
      "${wt_path}"|"${wt_path}"/*) return 0 ;;
    esac
  done < "${LV2_LANE_ALIVE_CWD_FILE}"
  return 1
}

# lv2_lane_pid_alive <pid> -> rc0 ALIVE (kill -0 succeeded), rc1 DEAD.
# D3: when a handle is ALREADY RECORDED (dispatcher's handle=PID=...), use
# this directly — never re-derive liveness from argv patterns for that case.
# false-life warning: kill -0 success alone does NOT prove THIS worker is
# alive — an OS can reuse a pid number after the original process exits, so
# a STALE recorded handle can point straight at an unrelated live process.
# Bare callers of this function get only "is a process alive under this pid
# number" — use lv2_lane_pid_alive_for (below) whenever a worktree path is
# available, since that additionally cross-checks the SAME pid's own cwd
# (already visible in the primed lsof table) against the worktree, catching
# exactly the reused-pid case this function alone cannot.
lv2_lane_pid_alive() {
  local pid="$1" err
  [[ "${pid}" =~ ^[0-9]+$ ]] || return 1
  err="$(kill -0 "${pid}" 2>&1)" && return 0
  # rc!=0 alone does not distinguish ESRCH (no such process, truly DEAD) from
  # EPERM (process exists, owned by someone else -- the process IS alive, we
  # just can't signal it). Classify by stderr text, per D2's bias to fail
  # closed toward ALIVE under ambiguity: only an explicit "no such process"
  # counts as DEAD; anything else (including a permission denial) is ALIVE.
  case "${err}" in
    *[Nn]o\ such\ process*) return 1 ;;
    *) return 0 ;;
  esac
}

# lv2_lane_pid_cwd <pid> -> stdout: the cwd recorded for <pid> in the primed
# lsof table, or nothing if this pid has no recorded cwd (either it was
# never in the table, or priming itself failed-closed). Requires the caller
# to have primed already; does not prime on demand (this is a read-only
# lookup, priming has its own fail-closed semantics that must run exactly
# once per sweep — see lv2_lane_cwd_prime / lv2_lane_worker_alive).
lv2_lane_pid_cwd() {
  local want_pid="$1" row_pid cwd
  [[ -n "${LV2_LANE_ALIVE_CWD_FILE}" && -s "${LV2_LANE_ALIVE_CWD_FILE}" ]] || return 1
  while IFS=$'\t' read -r row_pid cwd; do
    [[ "${row_pid}" == "${want_pid}" ]] && { printf '%s\n' "${cwd}"; return 0; }
  done < "${LV2_LANE_ALIVE_CWD_FILE}"
  return 1
}

# lv2_lane_pid_alive_for <pid> <wt_path> -> rc0 ALIVE-and-relevant, rc1 DEAD
# or NOT-this-lane. Closes the false-life gap: kill -0 succeeding is
# necessary but not sufficient. If the SAME lsof pass that primed this
# sweep also recorded a cwd for this exact pid, that cwd MUST be inside
# <wt_path> for this to count as "this lane's worker" — a live-but-
# unrelated process that happens to have reused the recorded pid number is
# thereby caught (its real cwd is visible and does not match). If lsof
# could not report a cwd for this pid at all (priming failed-closed, or the
# pid legitimately has no cwd entry in this pass, e.g. permission walls),
# there is nothing to disprove the handle with — fail closed to trusting
# kill -0, consistent with D2's overall bias toward ALIVE under ambiguity.
lv2_lane_pid_alive_for() {
  local pid="$1" wt_path="$2" cwd
  lv2_lane_pid_alive "${pid}" || return 1
  if [[ "${LV2_LANE_ALIVE_PRIMED}" != "1" ]]; then
    lv2_lane_cwd_prime
  fi
  [[ "${LV2_LANE_ALIVE_FAILCLOSED}" == "1" ]] && return 0   # cannot verify -- trust the pid
  cwd="$(lv2_lane_pid_cwd "${pid}")" || return 0             # no cwd recorded for this pid -- trust the pid
  wt_path="$(_lv2_lane_realpath "${wt_path}")"
  while [[ "${wt_path}" == */ && "${wt_path}" != / ]]; do wt_path="${wt_path%/}"; done
  case "${cwd}" in
    "${wt_path}"|"${wt_path}"/*) return 0 ;;
    *) return 1 ;;   # false-life: this exact pid's real cwd is elsewhere
  esac
}

# lv2_lane_any_alive <newline-separated pid list> [<wt_path>] -> rc0 if ANY
# pid is alive, rc1 only if ALL are dead (or the list is empty/blank). D4: a
# lane with multiple recorded handles is ALIVE if ANY pid is alive, DEAD
# only if ALL are dead. D5: iterate via while-read, never a bare
# `for p in $pids`. When <wt_path> is given, each pid is checked with the
# stronger lv2_lane_pid_alive_for (false-life cross-check); omitted, falls
# back to a bare kill -0 per pid.
lv2_lane_any_alive() {
  local pid_list="$1" wt_path="${2:-}" pid
  [[ -n "${pid_list}" ]] || return 1
  while IFS= read -r pid; do
    [[ -n "${pid}" ]] || continue
    if [[ -n "${wt_path}" ]]; then
      lv2_lane_pid_alive_for "${pid}" "${wt_path}" && return 0
    else
      lv2_lane_pid_alive "${pid}" && return 0
    fi
  done <<< "${pid_list}"
  return 1
}

# lv2_lane_alive_combined <wt_path> [<newline-separated pid list>] -> rc0
# ALIVE, rc1 DEAD. The one entry point callers should use: ANY of (D3+D4
# pid-handle check, cross-checked per-pid against cwd to close false-life;
# D2 cwd prefix-match against the worktree itself) reporting ALIVE wins — a
# checkpointer must never race a worker that is provably still running by
# EITHER measure.
lv2_lane_alive_combined() {
  local wt_path="$1" pid_list="${2:-}"
  if [[ -n "${pid_list}" ]] && lv2_lane_any_alive "${pid_list}" "${wt_path}"; then
    return 0
  fi
  lv2_lane_worker_alive "${wt_path}"
}
