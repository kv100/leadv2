#!/usr/bin/env bash
# leadv2-lane-watch-v2.sh — ONE-LANE-WATCH-01
#
# The ONE observability instrument for a leadv2 session: reports which lanes
# are stalled, heartbeats every active lane's idle age on a schedule, and
# reaps its own dead-session watcher bookkeeping. Replaces ad-hoc pulse/beat/
# status/guard/monitor scripts for this purpose (see docs/handoff/
# ONE-LANE-WATCH-01/report.md for the census and what each is superseded by).
#
# Liveness signal = mtime of files INSIDE a lane's own worktree, excluding
# lead-written bookkeeping (docs/leadv2/, docs/handoff/dispatch-*,
# LEAD_V2_STATE.md, .git/). Every provider (Claude/GLM/Codex/Kimi/freepool)
# must touch the worktree to do work, so this is arm-agnostic by
# construction — it does not special-case any provider, which is exactly
# what the v1 GLM-only watcher got wrong (it watched ~/.claude/cache/
# glm-runs only and was blind to every codex/kimi/freepool lane).
#
# Subcommands:
#   --arm-from-hook           SessionStart hook entry. Reads {session_id,cwd}
#                             JSON on stdin, backgrounds a --loop for this
#                             session (idempotent — a live loop already
#                             armed for this session id is left alone),
#                             opportunistically reaps other sessions' dead
#                             loop bookkeeping, exits 0 always (fail-open —
#                             must never block session start).
#   --disarm-from-hook        SessionEnd hook entry. Reads {session_id} JSON
#                             on stdin, kills THIS session's loop (argv-
#                             verified before any kill -- see
#                             _lw_is_our_loop), exits 0 always.
#   --once SESSION ROOT       Run exactly one check cycle against ROOT's
#                             worktrees and exit. Used by the test suite and
#                             for manual inspection; never blocks.
#   --loop SESSION ROOT       Internal. --once in an infinite fork-free-wait
#                             loop. Only ever invoked backgrounded by
#                             --arm-from-hook — never call this directly in
#                             the foreground, it does not return.
#   --reap-stale              Sweep the state root for OTHER sessions' loop
#                             pidfiles whose recorded pid is no longer
#                             running, and remove the stale bookkeeping.
#                             Never touches a live process. This is the
#                             "help what is stuck" verb this tool ships: a
#                             stale watcher's pidfile/lock is the one class
#                             of stall this tool can safely clear on its
#                             own (see report.md §3 for why a hung WORKER is
#                             deliberately NOT auto-restarted).
#
# Bash 3.2 only (macOS ships 3.2; no mapfile, no associative arrays). Every
# list is space-separated and iterated with a plain `for`, never an array,
# so nothing here needs an `${arr[@]}` guard under `set -u`.
set -u

SELF="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/$(basename "${BASH_SOURCE[0]:-$0}")"
SELF_BASENAME="$(basename "$SELF")"

STALE_MIN="${LANE_STALL_MIN:-20}"
BEAT_MIN="${LANE_BEAT_MIN:-12}"
GRACE_MIN="${LANE_GRACE_MIN:-15}"
POLL_SEC="${LEADV2_LANE_WATCH_POLL_SEC:-60}"
STATE_ROOT="${LEADV2_LANE_WATCH_STATE_DIR:-$HOME/.claude/leadv2-lane-watch}"
RUN_ROOT_PARENTS="${LEADV2_LANE_WATCH_RUN_ROOTS:-$HOME/.claude/cache}"

# --- fork-free wait ----------------------------------------------------------
# Duplicated, not sourced, from FORK-STORM-KILLS-HOOKS-01's
# plugins/leadv2/scripts/lib/leadv2-sleep.sh (leadv2_wait). That lib landed on
# main via merge 1d17985 AFTER this lane's branch point — verified 2026-09-01:
# `git ls-tree main` has plugins/leadv2/scripts/lib/leadv2-sleep.sh,
# `git cat-file -e HEAD:plugins/leadv2/scripts/lib/leadv2-sleep.sh` does not
# (HEAD's merge-base with main is two commits behind main's tip). LANE_WRITES
# for this task does not include scripts/lib/, so it cannot be vendored in
# properly either. Same algorithm as the shared lib: a `read -t` on a
# held-open fifo fd is a kernel timed wait with zero forked children, so a
# killed loop cannot leave an orphaned `sleep` behind — falls back to `sleep`
# once, only if the fifo cannot be set up at all.
# Follow-up (report.md): once this lane is rebased past that merge, delete
# this block and `source "${SELF%/*}/lib/leadv2-sleep.sh"` instead.
_LW_WAIT_READY=0
_lw_wait() {
  local _secs="${1:-0}"
  case "$_secs" in ''|*[!0-9]*) _secs=0 ;; esac
  [ "$_secs" -le 0 ] && return 0
  if [ "$_LW_WAIT_READY" != "1" ]; then
    local _fifo="${TMPDIR:-/tmp}/leadv2-lane-watch-wait.$$.fifo"
    if command mkfifo "$_fifo" 2>/dev/null && exec 9<>"$_fifo" 2>/dev/null; then
      _LW_WAIT_READY=1
      command rm -f "$_fifo" 2>/dev/null
    else
      command sleep "$_secs"
      return 0
    fi
  fi
  read -t "$_secs" _dummy <&9 || :
  return 0
}

# --- core signal ---------------------------------------------------------------

# _lw_newest_age_min WORKTREE_DIR -> minutes since the newest worker-written
# file. Noise paths are excluded because the session's own bookkeeping is
# written by the LEAD, not the worker, and would make a dead lane look alive.
# `.git` is excluded by NAME as well as by path: a git WORKTREE's `.git` is a
# plain FILE (not a directory) pointing at the main repo's gitdir, so
# `-not -path '*/.git/*'` alone never matches it — measured 2026-09-01, a
# fixture with only that filter reported a 25-minute-stale lane as 0m because
# the worktree's own `.git` file (checkout-time mtime) beat the stale file.
_lw_newest_age_min() {
  local w="$1" newest
  [ -d "$w" ] || { printf '999999'; return 0; }
  newest="$(find "$w" -type f \
      -not -path '*/.git/*' \
      -not -name '.git' \
      -not -path '*/docs/leadv2/*' \
      -not -path '*/docs/handoff/dispatch-*' \
      -not -name 'LEAD_V2_STATE.md' \
      -newermt '-600 minutes' -print0 2>/dev/null \
    | xargs -0 stat -f '%m' 2>/dev/null | sort -rn | head -1)"
  [ -n "$newest" ] || { printf '999'; return 0; }
  printf '%s' $(( ( $(date +%s) - newest ) / 60 ))
}

# _lw_dispatch_age_min LANE -> minutes since LANE's most recent provider run
# directory. The provider segment is WILDCARDED ("*-runs", not an enumerated
# "glm-runs"), which is the structural fix for the codex-blindness class of
# bug: v1 checked ~/.claude/cache/glm-runs only, so every codex/kimi/freepool
# lane read as "never dispatched" and its grace period never applied.
# Verified 2026-09-01: `ls ~/.claude/cache/*-runs` -> claude-runs, freepool-
# runs, glm-runs, kimi-runs all exist as siblings; none is special-cased here.
_lw_dispatch_age_min() {
  local lane="$1" d m newest best=999999
  for d in "${RUN_ROOT_PARENTS}"/*-runs/*"${lane}"*; do
    [ -e "$d" ] || continue
    m="$(stat -f %m "$d" 2>/dev/null)" || continue
    newest=$(( ( $(date +%s) - m ) / 60 ))
    [ "$newest" -lt "$best" ] && best=$newest
  done
  printf '%s' "$best"
}

# _lw_discover_lanes WORKTREES_DIR -> space-separated lane names. A lane is
# any worktree still checked out; leadv2-merged-worktree-sweep.sh (an
# existing SessionStart hook) removes a worktree once its lane lands, so
# "still present under WORKTREES" is a reliable proxy for "still active"
# without parsing any registry file's schema.
_lw_discover_lanes() {
  local wt="$1" d
  if [ -n "${LEADV2_LANE_WATCH_LANES:-}" ]; then
    printf '%s' "${LEADV2_LANE_WATCH_LANES}"
    return 0
  fi
  [ -d "$wt" ] || return 0
  for d in "$wt"/*; do
    [ -d "$d" ] || continue
    [ -e "$d/.git" ] || continue
    printf '%s ' "$(basename "$d")"
  done
}

# --- one check cycle -----------------------------------------------------------

_lw_drop_reported() {
  # Remove LANE from the reported file so a future stall reports again
  # (recovered lane, or a fresh re-dispatch inside the grace window).
  local lane="$1" reported_file="$2"
  grep -vFx "$lane" "$reported_file" > "${reported_file}.tmp" 2>/dev/null || : > "${reported_file}.tmp"
  mv -f "${reported_file}.tmp" "$reported_file" 2>/dev/null || true
}

_lw_run_once() {
  local session="$1" project_root="$2"
  local wt="${LEADV2_LANE_WATCH_WORKTREES:-${project_root}/.claude/worktrees}"
  local state_dir="${STATE_ROOT}/${session}"
  mkdir -p "$state_dir" 2>/dev/null || true
  local reported_file="${state_dir}/reported"
  local beat_file="${state_dir}/last_beat"
  [ -f "$reported_file" ] || : > "$reported_file"

  local lanes; lanes="$(_lw_discover_lanes "$wt")"
  local now; now="$(date +%s)"
  local beat_line="" lane age d_age

  for lane in $lanes; do
    [ -n "$lane" ] || continue
    age="$(_lw_newest_age_min "${wt}/${lane}")"
    beat_line="${beat_line}${lane}:${age}m "

    # Grace: a lane dispatched within GRACE_MIN has not had time to write
    # yet — reporting that is the false alarm that fired on
    # GUARDS-MUST-PROVE-THEY-FIRE-01 sixty seconds after dispatch.
    d_age="$(_lw_dispatch_age_min "$lane")"
    if [ "$d_age" -lt "$GRACE_MIN" ]; then
      _lw_drop_reported "$lane" "$reported_file"
      continue
    fi

    if grep -qFx "$lane" "$reported_file" 2>/dev/null; then
      [ "$age" -lt "$STALE_MIN" ] && _lw_drop_reported "$lane" "$reported_file"
      continue
    fi

    if [ "$age" -ge "$STALE_MIN" ]; then
      printf 'LANE-STALL: %s — worktree untouched for %sm; worker is not producing, check and re-dispatch\n' "$lane" "$age"
      printf '%s\n' "$lane" >> "$reported_file"
    fi
  done

  local last_beat=0
  if [ -f "$beat_file" ]; then
    last_beat="$(cat "$beat_file" 2>/dev/null || printf 0)"
    case "$last_beat" in ''|*[!0-9]*) last_beat=0 ;; esac
  fi

  if [ $(( now - last_beat )) -ge $(( BEAT_MIN * 60 )) ]; then
    printf 'LANE-BEAT: %s\n' "${beat_line:-no active lanes}"
    printf '%s' "$now" > "$beat_file" 2>/dev/null || true
  fi
}

# --- arm / disarm / reap ---------------------------------------------------------

_lw_pidfile() { printf '%s/%s/loop.pid' "${STATE_ROOT}" "$1"; }

# _lw_is_our_loop PID SESSION — true only if `ps`'s command column for PID
# contains BOTH this script's own basename and this exact session id as a
# --loop argument. Never a bare lane-name substring match: the lead killed
# his own watchdog today because a filter matched the lane name inside its
# own command line. This checks OUR identity, never the thing we watch.
_lw_is_our_loop() {
  local pid="$1" session="$2" cmd
  cmd="$(ps -o command= -p "$pid" 2>/dev/null || true)"
  [ -n "$cmd" ] || return 1
  case "$cmd" in
    *"$SELF_BASENAME"*"--loop"*"$session"*) return 0 ;;
    *) return 1 ;;
  esac
}

cmd_reap_stale() {
  local d other_pid
  mkdir -p "$STATE_ROOT" 2>/dev/null || true
  for d in "${STATE_ROOT}"/*; do
    [ -d "$d" ] || continue
    [ -f "$d/loop.pid" ] || continue
    other_pid="$(cat "$d/loop.pid" 2>/dev/null || true)"
    case "$other_pid" in
      ''|*[!0-9]*) rm -f "$d/loop.pid" 2>/dev/null; continue ;;
    esac
    kill -0 "$other_pid" 2>/dev/null || rm -f "$d/loop.pid" 2>/dev/null
  done
}

_lw_arm() {
  local session="$1" project_root="$2"
  local dir="${STATE_ROOT}/${session}"
  mkdir -p "$dir" 2>/dev/null || return 0
  local pidfile; pidfile="$(_lw_pidfile "$session")"
  if [ -f "$pidfile" ]; then
    local old; old="$(cat "$pidfile" 2>/dev/null || true)"
    case "$old" in
      ''|*[!0-9]*) : ;;
      *)
        if kill -0 "$old" 2>/dev/null && _lw_is_our_loop "$old" "$session"; then
          return 0   # already armed for this session — idempotent
        fi
        ;;
    esac
  fi
  nohup "$SELF" --loop "$session" "$project_root" >/dev/null 2>&1 &
  printf '%s' "$!" > "$pidfile" 2>/dev/null || true
  disown 2>/dev/null || true
  cmd_reap_stale
}

_lw_disarm() {
  local session="$1"
  local pidfile; pidfile="$(_lw_pidfile "$session")"
  [ -f "$pidfile" ] || return 0
  local pid; pid="$(cat "$pidfile" 2>/dev/null || true)"
  rm -f "$pidfile" 2>/dev/null || true
  case "$pid" in
    ''|*[!0-9]*) return 0 ;;
  esac
  _lw_is_our_loop "$pid" "$session" || return 0
  kill -TERM "$pid" 2>/dev/null || return 0
  local waited=0
  while [ "$waited" -lt 3 ] && kill -0 "$pid" 2>/dev/null; do
    _lw_wait 1
    waited=$(( waited + 1 ))
  done
  kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null
  return 0
}

# --- hook entrypoints --------------------------------------------------------

_lw_read_hook_meta() {
  local input; input="$(cat 2>/dev/null || true)"
  [ -n "$input" ] || { printf '\n\n'; return 0; }
  printf '%s' "$input" | python3 -c '
import sys, json
try:
    r = json.loads(sys.stdin.read())
except Exception:
    r = {}
print(r.get("session_id","") or "")
print(r.get("cwd","") or "")
' 2>/dev/null || printf '\n\n'
}

cmd_arm_from_hook() {
  local meta session cwd project_root
  meta="$(_lw_read_hook_meta)"
  session="$(printf '%s' "$meta" | sed -n '1p')"
  cwd="$(printf '%s' "$meta" | sed -n '2p')"
  [ -n "$session" ] || exit 0
  [ -n "$cwd" ] || exit 0
  project_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$cwd")"
  [ -d "${project_root}/docs/leadv2" ] || exit 0
  _lw_arm "$session" "$project_root"
  exit 0
}

cmd_disarm_from_hook() {
  local meta session
  meta="$(_lw_read_hook_meta)"
  session="$(printf '%s' "$meta" | sed -n '1p')"
  [ -n "$session" ] || exit 0
  _lw_disarm "$session"
  exit 0
}

# --- dispatch ------------------------------------------------------------------

case "${1:-}" in
  --arm-from-hook)
    cmd_arm_from_hook
    ;;
  --disarm-from-hook)
    cmd_disarm_from_hook
    ;;
  --reap-stale)
    cmd_reap_stale
    ;;
  --once)
    SESSION="${2:?session required}"
    PROJECT_ROOT="${3:?project_root required}"
    _lw_run_once "$SESSION" "$PROJECT_ROOT"
    ;;
  --loop)
    SESSION="${2:?session required}"
    PROJECT_ROOT="${3:?project_root required}"
    while :; do
      _lw_run_once "$SESSION" "$PROJECT_ROOT"
      _lw_wait "$POLL_SEC"
    done
    ;;
  *)
    echo "usage: ${SELF_BASENAME} --arm-from-hook|--disarm-from-hook|--reap-stale|--once SESSION ROOT|--loop SESSION ROOT" >&2
    exit 2
    ;;
esac
