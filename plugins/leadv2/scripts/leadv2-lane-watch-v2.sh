#!/usr/bin/env bash
# leadv2-lane-watch-v2.sh — ONE-LANE-WATCH-01
#
# The ONE observability instrument for a leadv2 session: reports which lanes
# are stalled, heartbeats every active lane's idle age on a schedule, and
# reaps its own dead-session watcher bookkeeping. Replaces ad-hoc pulse/beat/
# status/guard/monitor scripts for this purpose (see docs/handoff/
# ONE-LANE-WATCH-01/report.md for the census and what each is superseded by).
#
# Two liveness signals, and a lane is STALLED only when BOTH are quiet past
# LANE_STALL_MIN: (a) mtime of files INSIDE the lane's own worktree, excluding
# lead-written bookkeeping (docs/leadv2/, docs/handoff/dispatch-*,
# LEAD_V2_STATE.md, .git/), and (b) the lane's provider run state producing
# output. One signal is not enough in either direction: a worker reading and
# planning writes its provider run dir while touching no worktree file
# (worktree-only -> false alarm), and a provider run dir's own DIRECTORY
# mtime is kept fresh by ordinary runner bookkeeping (state rewrites, .stale
# rotation) regardless of whether the WORKER produces anything, so directory
# mtime can never be the sole stall signal either — see
# _lw_provider_output_age_min below, which measures WORKER-output file
# mtimes only, never the directory's own. When both
# go quiet AND nothing is live anywhere while docs/tasks.yaml still has open
# rows, the watcher says so (LANE-IDLE) — the one job the retired
# leadv2-idle-lead-guard.sh did honestly (its liveness input,
# leadv2-lane-liveness.sh --all, measured 0/231 while a lane wrote).
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
CODEX_STATE_ROOT="${LEADV2_LANE_WATCH_CODEX_STATE:-$HOME/.claude/plugins/data/codex-openai-codex/state}"

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

# lane_dirs LANE -> one provider state directory per line that may hold
# LANE's run state. This is THE single place that knows which provider arms
# exist: adding an arm later is a one-line change here, and every consumer
# (_lw_dispatch_age_min, _lw_provider_output_age_min) picks it up. The round-1
# glob was "*-runs" under the cache root, which matched glm-runs/freepool-runs
# but nothing for a codex lane — measured 2026-09-01, a codex lane's state
# lives under ~/.claude/plugins/data/codex-openai-codex/state/<LANE>-<hash>
# (probe: TESTS-POLLUTE-REAL-JOURNAL-01-14806a70f0cacf75 exists there), so a
# codex lane had no dispatch age at all and was "stalled" seconds after a
# healthy dispatch. Unmatched globs print literally under bash 3.2, so every
# consumer MUST guard with [ -e ] / [ -d ].
# Round-2 census (2026-09-01, `ls -d ~/.claude/cache/*-runs`) found FOUR
# `*-runs` families, not two: claude-runs and kimi-runs exist alongside
# glm-runs/freepool-runs. Round 2's first cut enumerated only the latter two,
# so a claude-arm lane matched nothing here and lost both dispatch grace and
# provider-output suppression — d_age/prov_age both 999999, i.e. reported
# stalled seconds after a healthy dispatch (the same regression class this
# whole lane exists to kill, this time against the claude arm instead of
# codex). Fix: enumerate every `*-runs` sibling under each root by name,
# explicitly, so the list this function returns is the SAME list a fresh
# `ls -d ~/.claude/cache/*-runs` would show, not a two-of-four subset.
lane_dirs() {
  local lane="$1" root roots
  roots="$(printf '%s' "$RUN_ROOT_PARENTS" | tr ':' ' ')"
  for root in $roots; do
    printf '%s\n' \
      "${root}"/glm-runs/*"${lane}"* \
      "${root}"/freepool-runs/*"${lane}"* \
      "${root}"/claude-runs/*"${lane}"* \
      "${root}"/kimi-runs/*"${lane}"*
  done
  printf '%s\n' "${CODEX_STATE_ROOT}"/*"${lane}"*
}

# _lw_birth_epoch PATH -> st_birthtime as epoch seconds, falling back to mtime
# where %B is unavailable (GNU stat; macOS %B is the birth time). The
# fallback is stated honestly: it degrades birth semantics to mtime and can
# only make a lane look FRESHER than it is, never older.
_lw_birth_epoch() {
  local m
  m="$(stat -f %B "$1" 2>/dev/null)"
  case "$m" in
    ''|*[!0-9]*) m="$(stat -f %m "$1" 2>/dev/null)" || return 1 ;;
  esac
  printf '%s' "$m"
}

# _lw_dispatch_age_min LANE -> minutes since LANE was last DISPATCHED, i.e.
# the youngest birth time among its provider run directories. Birth, not
# mtime: the DIRECTORY's own mtime (as opposed to the mtime of the WORKER-
# output files inside it — see _lw_provider_output_age_min below) is pinged
# by ordinary filesystem housekeeping unrelated to the worker producing
# anything: a runner bookkeeping rewrite (state.json, .stream_state,
# .lockref rotation) or a new file being created inside the dir both bump
# the directory mtime without the worker having written a single line of
# output. An mtime-based dispatch age therefore stays near zero indefinitely
# and the grace window never expires for exactly the lanes worth watching —
# a lane sat 23 minutes past LANE_STALL_MIN in silence before a human
# reading the heartbeat noticed. Birth time is what "how long since this
# lane was dispatched" actually means, and is immune to this pinging because
# birth is set once, at directory creation, and cannot be bumped by later
# writes into the directory.
#
# NOTE: this is a narrower claim than round 2's original draft ("broker.json
# rotates every ~30 min") — that specific claim was UNVERIFIED and is
# contradicted by the live tree (probe 2026-09-01, three codex state dirs
# under codex-openai-codex/state: broker.json/state.json mtimes are Aug 9 /
# Aug 26, weeks stale, while each dir's jobs/ subdirectory shows Sep 1
# 22:46 activity — broker.json is NOT rotating on any ~30-min cadence in
# this tree). The design does not depend on that claim: it depends only on
# "directory mtime can be pinged by something other than worker output",
# which the jobs/ vs broker.json split above demonstrates directly.
_lw_dispatch_age_min() {
  local lane="$1" d m newest best=999999 now
  now="$(date +%s)"
  while IFS= read -r d; do
    [ -e "$d" ] || continue
    m="$(_lw_birth_epoch "$d")" || continue
    newest=$(( ( now - m ) / 60 ))
    [ "$newest" -lt 0 ] && newest=0
    [ "$newest" -lt "$best" ] && best=$newest
  done < <(lane_dirs "$lane")
  printf '%s' "$best"
}

# _lw_provider_output_age_min LANE -> minutes since LANE's provider state
# last produced MODEL output. Deliberately NOT the run dir's own mtime —
# ordinary runner bookkeeping pings it while the worker hangs (round-2
# [Critical] 1 measurement). Round 4 (reviewer glm [High]): round 3 counted
# "every top-level file except broker.json/state.json" as worker output, but
# progress.log, meta.yaml, supervisor.log, exit_code, stderr/child.log are
# written by the RUNNER (glm-coder/freepool-coder heartbeat, status flips,
# supervisor polls) — a hung or killed worker kept reading "provider-fresh"
# and LANE-STALL was suppressed. Measured: 53 min of silence on
# 260901-184335-PHASE-GATE-IS-INVERTED-01-7ddb never reported. Inverted to an
# ALLOW-list — only files the MODEL's own session writes, per arm:
#   glm/kimi/freepool run dirs -> journal.jsonl ONLY. That is the stream-json
#     transcript (assistant/tool_use/tool_result events, written by the
#     session as the model acts; probe 2026-09-01: the live run dir
#     glm-runs/260901-233754-ONE-LANE-WATCH-01-R2-2fcc holds 17 assistant /
#     10 tool_use / 9 tool_result events in journal.jsonl, while progress.log,
#     meta.yaml, supervisor.log, stderr.log, pgid, git-pre*, prompt.txt,
#     child.log and the .stream_state/.lockref/.workbase dotfiles are all
#     runner-written). There is no `*.stream.jsonl` / `developer.stream.jsonl`
#     in these run dirs — searched the live cache tree, zero hits — the
#     journal IS the stream artifact.
#   codex state dirs -> jobs/* ONLY (task-*.json/.log written by the codex
#     worker; probe 2026-09-01: state/05d28614-d519cdfbfdea302f/jobs/
#     task-mtj1kt02-6z5iy9.{json,log}, vs top-level state.json runner
#     bookkeeping — matched by ${CODEX_STATE_ROOT}/*, not a hardcoded name).
#   claude run dirs -> NOTHING model-written exists there (probe 2026-09-01:
#     claude-runs/developer-dispatch-34f12615-*/ holds only .finalized,
#     .outcome, meta.yaml, pid — all runner bookkeeping). For this arm the
#     lane worktree mtime — the `age` half of the both-signal stall rule in
#     _lw_run_once — is the only liveness signal; the dir birth-time fallback
#     below makes prov_age track time-since-dispatch and get out of the way.
# A run dir with no allow-listed model file has produced nothing since it was
# CREATED, so its birth time is the honest fallback. Nothing found anywhere
# -> 999999 (quiet).
_lw_provider_output_age_min() {
  local lane="$1" d f m cand newest best=999999 now
  now="$(date +%s)"
  while IFS= read -r d; do
    [ -d "$d" ] || continue
    cand="$(_lw_birth_epoch "$d")" || continue
    case "$d" in
      "${CODEX_STATE_ROOT}"/*)
        for f in "$d"/jobs/*; do
          [ -f "$f" ] || continue
          m="$(stat -f %m "$f" 2>/dev/null)" || continue
          [ "$m" -gt "$cand" ] && cand="$m"
        done
        ;;
      */glm-runs/*|*/kimi-runs/*|*/freepool-runs/*)
        f="$d/journal.jsonl"
        if [ -f "$f" ]; then
          m="$(stat -f %m "$f" 2>/dev/null)" || m=""
          if [ -n "$m" ] && [ "$m" -gt "$cand" ]; then cand="$m"; fi
        fi
        # no journal.jsonl yet -> cand stays at dir birth: honest
        # "nothing produced since creation" fallback
        ;;
      *)
        # claude-runs and any future family with no model-written file in
        # the run dir: count nothing here (see probe above) — the lane
        # worktree mtime is this arm's only liveness signal.
        ;;
    esac
    newest=$(( ( now - cand ) / 60 ))
    [ "$newest" -lt 0 ] && newest=0
    [ "$newest" -lt "$best" ] && best=$newest
  done < <(lane_dirs "$lane")
  printf '%s' "$best"
}

# _lw_queued_task_count PROJECT_ROOT -> number of open rows in the project's
# docs/tasks.yaml (statuses queued/ready/pending — the same predicate the
# retired idle-lead-guard used). No file or unparseable YAML -> 0, so a
# project without a task store can never trigger LANE-IDLE.
_lw_queued_task_count() {
  local f="${LEADV2_LANE_WATCH_TASKS_FILE:-${1}/docs/tasks.yaml}"
  [ -f "$f" ] || { printf '0'; return 0; }
  python3 - "$f" "${LEADV2_LANE_WATCH_QUEUED_STATUSES:-queued,ready,pending}" <<'PY' 2>/dev/null || printf '0'
import sys
try:
    import yaml
    with open(sys.argv[1]) as fh:
        items = yaml.safe_load(fh)
except Exception:
    items = None
if isinstance(items, dict):
    items = items.get("tasks")
if not isinstance(items, list):
    items = []
statuses = set(s.strip() for s in sys.argv[2].split(",") if s.strip())
print(sum(1 for it in items
          if isinstance(it, dict)
          and str(it.get("status", "")).strip() in statuses))
PY
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
  local beat_line="" lane age prov_age d_age live_lanes=0

  for lane in $lanes; do
    [ -n "$lane" ] || continue
    age="$(_lw_newest_age_min "${wt}/${lane}")"
    prov_age="$(_lw_provider_output_age_min "$lane")"
    beat_line="${beat_line}${lane}:${age}m "

    # Live = either signal fresh. A worker reading and planning writes its
    # provider run dir while touching no worktree file, and vice versa a
    # worker between provider calls can go quiet in the run dir while its
    # worktree still shows writes.
    if [ "$age" -lt "$STALE_MIN" ] || [ "$prov_age" -lt "$STALE_MIN" ]; then
      live_lanes=$(( live_lanes + 1 ))
    fi

    # Grace: a lane DISPATCHED within GRACE_MIN has not had time to write
    # yet — reporting that is the false alarm that fired on
    # GUARDS-MUST-PROVE-THEY-FIRE-01 sixty seconds after dispatch. The age
    # is birth-based (see _lw_dispatch_age_min): an mtime-based grace never
    # expires for exactly the lanes worth watching.
    d_age="$(_lw_dispatch_age_min "$lane")"
    if [ "$d_age" -lt "$GRACE_MIN" ]; then
      _lw_drop_reported "$lane" "$reported_file"
      continue
    fi

    if grep -qFx "$lane" "$reported_file" 2>/dev/null; then
      if [ "$age" -lt "$STALE_MIN" ] || [ "$prov_age" -lt "$STALE_MIN" ]; then
        _lw_drop_reported "$lane" "$reported_file"
      fi
      continue
    fi

    # Stall = BOTH signals quiet. Never a backstop that overrides fresh
    # provider output: a working-but-not-yet-committing lane (reading,
    # planning) is the false alarm that makes a watcher get ignored.
    if [ "$age" -ge "$STALE_MIN" ] && [ "$prov_age" -ge "$STALE_MIN" ]; then
      printf 'LANE-STALL: %s — worktree untouched %sm, provider output %sm; check and re-dispatch\n' "$lane" "$age" "$prov_age"
      printf '%s\n' "$lane" >> "$reported_file"
    fi
  done

  # LANE-IDLE — the one honest job inherited from the retired idle-lead-guard:
  # there is queued work and no live lane (by the SAME two signals above,
  # never leadv2-lane-liveness.sh --all, which measured 0/231 while a lane
  # wrote). Reported once per queued-count so a polling loop does not spam;
  # re-reports when the count changes, clears when a lane goes live or the
  # queue drains.
  local queued; queued="$(_lw_queued_task_count "$project_root")"
  local idle_file="${state_dir}/idle_reported"
  if [ "$queued" -gt 0 ] && [ "$live_lanes" -eq 0 ]; then
    local last_idle
    last_idle="$(cat "$idle_file" 2>/dev/null || true)"
    case "$last_idle" in ''|*[!0-9]*) last_idle=0 ;; esac
    if [ "$last_idle" != "$queued" ]; then
      printf 'LANE-IDLE: no live lane, %s task(s) queued\n' "$queued"
      printf '%s' "$queued" > "$idle_file" 2>/dev/null || true
    fi
  else
    rm -f "$idle_file" 2>/dev/null || true
  fi

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
