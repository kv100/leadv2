#!/usr/bin/env bash
# leadv2-orphan-reaper.sh — CONTROL-PLANE-SATURATES-THE-MACHINE-AND-FAKES-RED-01
#
# Reaps ORPHANED control-plane loops whose owning Claude session is PROVABLY
# dead. Every dead session used to leave its detached children beating
# forever (measured 2026-09-06: 16 orphaned beat-loops — that subject was
# retired with the beat chain, ONE-STATUS-MECHANISM-01 2026-09-13 — aged
# 10-13h from ~16 dead sessions in one day; 11 anti-silence pulses older
# than an hour; 8 stale-sweepers with ppid=1). They saturate the machine,
# the load drops time-sensitive suites red, the e2e gate claims the lane,
# the lane is re-dispatched, the load grows — the feedback loop this reaper
# breaks on the orphan side (the spawn side is deduped by the sweeper's
# single-flight gate).
#
# THE RULE (founder brief): bury only on a POSITIVE sign of death.
#   - kill -0 has THREE answers: rc=0 alive; ESRCH dead; EPERM ALIVE
#     (a process we may not signal — pid 1 — is running, not gone).
#   - "session dead" = the session's transcript (~/.claude/projects/*/<sid>
#     .jsonl) is IDLE beyond the idle threshold, or ABSENT while the orphan
#     itself is older than the absent grace. A live session's transcript is
#     minutes-fresh; a missing transcript with a young process is a fixture
#     or a race, never a kill.
#   - a pulse additionally requires its OWNER CHAIN broken: the pulse is a
#     child of the arming session (claude → shell wrapper → pulse), so a
#     live-but-SILENT session (transcript idle for hours, REPL waiting) is
#     still ALIVE and its pulse must survive. Transcript-idle alone killed
#     exactly such a pulse in the 2026-09-06 dry-run — the two-signal rule
#     (transcript dead AND chain broken) is what keeps live watchers alive.
#   - every kill is preceded by an identity check: argv-verified process
#     pattern (never a bare pid from a file) and, where a .birth sidecar
#     exists, ps-lstart identity (pid reuse turns a recorded pid into
#     someone else's process).
#
# Subjects:
#   1. anti-silence-pulse loops   — pidfile-driven (docs/leadv2/
#      anti-silence-pulse.<session>[.<key>].pid under the project root and
#      its worktrees); session id comes from the pidfile NAME.
#   2. leadv2-stale-sweeper full sweeps — age-driven (a oneshot; etime over
#      the stuck threshold is positive death of its progress) OR, for a
#      ppid=1 candidate, owner-death-driven (REAPER-AGE-CRITERION-NEVER-
#      REACHES-THE-POPULATION-01: orphans are reparented young — measured
#      0:57-20:20 against the 3600/1800s gates, one fresh orphan a minute —
#      so the age gate never meets the population; a ppid=1 sweep whose
#      owning claude is provably dead (env CLAUDE_PID gone via the
#      three-answer kill -0, or transcript dead via CLAUDE_CODE_SESSION_ID)
#      is reaped NOW, on the death sign, not on age).
#   3. leadv2-worktree-cleanup --sweep-dead — same two branches, same
#      rationale. Kills go leaves-first (grandchildren → children →
#      parent): TERMing a parent first guarantees a reparented survivor
#      (CONTROL-PLANE-SATURATES-01/reaper-constraint-20260906T1550Z.md).
#   4. DELETED (ONE-STATUS-MECHANISM-01, 2026-09-13): beat-loops — the
#      spawner is gone with the retired beat chain; population permanently 0.
#
# Never touches: pid 1, itself, any process it cannot identify, and any
# pulse/watcher whose session transcript is fresh. --dry-run prints the
# would-kill verdicts without signalling.
#
# Usage: leadv2-orphan-reaper.sh [--dry-run] [--project-root <path>]
# Env:  DRY_RUN=1|true|yes|on       same effect as --dry-run (case-insensitive;
#                                    DRY_RUN=true matches the repo convention
#                                    in leadv2-backfill-history.sh)
#                                    (REAPER-DRY-RUN-ENV-VAR-IS-SILENTLY-
#                                    IGNORED-01: the env var used to be
#                                    read and then unconditionally
#                                    overwritten by the script's own
#                                    default, so it was silently ignored.
#                                    Either surface asking for dry-run
#                                    wins -- env DRY_RUN or --dry-run;
#                                    there is no way to force a live run
#                                    when a truthy DRY_RUN is exported,
#                                    by design. Any other non-empty value
#                                    (0/false/no/off count as explicit off)
#                                    is REFUSED with exit 2 -- an unknown
#                                    spelling never falls through to live.)
#       LEADV2_PROJECT_ROOT          project whose pulse pidfiles to scan
#       LEADV2_REAPER_PROJECTS_DIR   transcript root override (tests)
#       LEADV2_REAPER_IDLE_MIN       transcript idle threshold (default 360,
#                                    aligned with lane-watch-v2's
#                                    LW_REAP_IDLE_MIN: six quiet hours)
#       LEADV2_REAPER_ABSENT_GRACE_S process age required before an absent
#                                    transcript counts as death (default 7200)
#       LEADV2_REAPER_SWEEPER_STUCK_SEC   default 3600
#       LEADV2_REAPER_CLEANUP_STUCK_SEC   default 1800
#       LEADV2_REAPER_BEAT_MAX_SEC        default 21600 (unused since the
#                                          beat-loop subject was retired)
#       LEADV2_REAPER_SUBJECT_SCOPE       path prefix; when set, sweeper/
#                                    cleanup subjects whose command line does
#                                    not contain it are invisible to this
#                                    pass, and pulse/beat subjects are
#                                    skipped entirely (test hermeticity — a
#                                    suite must never mutate the live control
#                                    plane; unset in production)
#       LEADV2_REAPER_DISABLE=1     no-op (escape hatch)
#
# Wired from hooks/leadv2-stale-pid-sweep.sh (synchronous, bounded — a
# handful of pgrep/ps/stat calls, no python3) so every SessionStart sweeps
# the previous session's orphans away.

set -uo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
# REAPER-DRY-RUN-ENV-VAR-IS-SILENTLY-IGNORED-01: DRY_RUN was accepted from
# the environment and then unconditionally clobbered by the next line's
# default, so `DRY_RUN=1 leadv2-orphan-reaper.sh` killed anyway. Capture the
# inherited value BEFORE the default assignment; either surface asking for
# dry-run (env DRY_RUN=1 OR the --dry-run flag below) wins -- a safety
# switch fails toward safe, never toward live.
_dry_run_env="${DRY_RUN:-}"
_dry_run_env_lc="$(printf '%s' "${_dry_run_env}" | tr '[:upper:]' '[:lower:]')"
DRY_RUN=0
case "${_dry_run_env_lc}" in
  1|true|yes|on) DRY_RUN=1 ;;
  ""|0|false|no|off) : ;;
  *)
    # REAPER-DRY-RUN-ENV-VAR-IS-SILENTLY-IGNORED-01 round 3: an unknown
    # spelling must never fall through to a live run. Refuse, naming the
    # value received and the accepted set.
    printf '[orphan-reaper] refusing: DRY_RUN=%q is not recognised (on: 1/true/yes/on; off: 0/false/no/off/unset)\n' "${_dry_run_env}" >&2; exit 2 ;;
esac
PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --project-root)
      PROJECT_ROOT="${2:-}"
      if [[ $# -ge 2 ]]; then shift 2; else shift; fi ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf '[orphan-reaper] unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

[[ "${LEADV2_REAPER_DISABLE:-}" == "1" ]] && exit 0

REAPER_IDLE_MIN="${LEADV2_REAPER_IDLE_MIN:-360}"
REAPER_ABSENT_GRACE_S="${LEADV2_REAPER_ABSENT_GRACE_S:-7200}"
SWEEPER_STUCK_SEC="${LEADV2_REAPER_SWEEPER_STUCK_SEC:-3600}"
CLEANUP_STUCK_SEC="${LEADV2_REAPER_CLEANUP_STUCK_SEC:-1800}"
BEAT_MAX_SEC="${LEADV2_REAPER_BEAT_MAX_SEC:-21600}"
PROJECTS_DIR="${LEADV2_REAPER_PROJECTS_DIR:-$HOME/.claude/projects}"

_killed=0
_reap_log() { printf '[orphan-reaper] %s\n' "$*" >&2; }

# REAPER-AGE-CRITERION-NEVER-REACHES-THE-POPULATION-01: a single collapsed
# "reaped: N" line reads identically whether N is 0-because-clean or
# 0-because-this-subject-was-never-checked -- the exact ambiguity that read
# 18 ppid=1 sweeper orphans, none over the age threshold, as "nothing to see"
# on 2026-09-06T13:05Z. Per-subject candidate counters, broken down by which
# positive-death SIGNAL each candidate did or didn't meet (never a bare
# count -- "a number must carry its own boundary"), so a report can never
# again look clean while a whole subject went unexamined.
_seen_pulses=0; _killed_pulses=0
_seen_sweeper=0; _seen_sweeper_ppid1=0; _seen_sweeper_stuck=0; _killed_sweeper=0
_seen_sweeper_owner_dead=0; _seen_sweeper_owner_live=0
_seen_cleanup=0; _seen_cleanup_ppid1=0; _seen_cleanup_stuck=0; _killed_cleanup=0
_seen_cleanup_owner_dead=0; _seen_cleanup_owner_live=0

# ── three-answer liveness ──────────────────────────────────────────────────
_pid_alive() {  # rc=0 alive; rc=1 dead. EPERM is ALIVE (pid 1 et al).
  local pid="$1" err
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  (( pid > 1 )) || return 0                       # pid 1 is launchd — alive
  err="$(kill -0 "$pid" 2>&1)" && return 0
  case "$err" in
    *"not permitted"*|*"Not permitted"*|*"operation not permitted"*) return 0 ;;
    *) return 1 ;;
  esac
}

_norm_lstart() {
  # Identical to anti-silence-pulse.sh's _norm_ps_field: squeeze internal
  # whitespace AND strip leading/trailing — `ps -o lstart=` pads with leading
  # spaces, so a squeeze-only normalizer mismatches every pulse birth file
  # (observed live 2026-09-06: every pidfile read as "recycled").
  local s
  s="$(printf '%s' "$1" | tr -s '[:space:]' ' ')"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# pid_identity PID BIRTH_FILE — "verified" | "unverified" | "mismatch".
# Only a recorded birth CONTRADICTED by live observation is a mismatch
# (pid recycled); absent/unobservable degrades to unverified and never
# blocks a kill decision that already has positive death elsewhere.
_pid_identity() {
  local pid="$1" birth_file="$2" recorded observed
  [[ -f "$birth_file" ]] || { printf 'unverified'; return; }
  recorded="$(cat "$birth_file" 2>/dev/null || true)"
  [[ -n "$recorded" ]] || { printf 'unverified'; return; }
  observed="$(_norm_lstart "$(ps -o lstart= -p "$pid" 2>/dev/null || true)")"
  [[ -n "$observed" ]] || { printf 'unverified'; return; }
  if [[ "$observed" == "$recorded" ]]; then printf 'verified'
  else printf 'mismatch'; fi
}

# session_death_age_min SID -> "alive" | "idle:N" | "absent"
# A live session's transcript is minutes-fresh (every turn appends); N quiet
# minutes ≥ REAPER_IDLE_MIN means the session cannot still be running.
_session_death_age_min() {
  local sid="$1" f m best="" now
  case "$sid" in
    ''|*[!A-Za-z0-9_-]*) printf 'absent'; return 0 ;;
  esac
  for f in "$PROJECTS_DIR"/*/"$sid.jsonl" "$PROJECTS_DIR"/"$sid.jsonl"; do
    [[ -f "$f" ]] || continue
    m="$(stat -f %m "$f" 2>/dev/null)" || continue
    if [[ -z "$best" ]] || (( m > best )); then best="$m"; fi
  done
  if [[ -z "$best" ]]; then printf 'absent'; return 0; fi
  now="$(date +%s)"
  local age_min=$(( ( now - best ) / 60 ))
  if (( age_min < REAPER_IDLE_MIN )); then printf 'alive'
  else printf 'idle:%s' "$age_min"; fi
}

_etime_sec() {  # "dd-hh:mm:ss" | "hh:mm:ss" | "mm:ss" -> seconds
  local t="$1" d h m s
  t="${t// /}"
  [[ -n "$t" ]] || { printf '0'; return; }
  s="${t##*:}"
  if [[ "$t" == *-* ]]; then
    d="${t%%-*}"; t="${t#*-}"
  else d=0; fi
  if [[ "$t" == *:*:* ]]; then
    h="${t%%:*}"; t="${t#*:}"
    m="${t%%:*}"
  else h=0; m="${t%%:*}"; fi
  printf '%s' $(( (( (10#${d:-0}*24 + 10#${h:-0})*60 + 10#${m:-0})*60 ) + 10#${s:-0} ))
}

_pid_etime_sec() { _etime_sec "$(ps -o etime= -p "$1" 2>/dev/null | tr -d ' ')"; }

# kill only after argv verification: the pid's command line must contain the
# expected script name, so a recycled pid never gets signalled on faith.
_argv_verified() {
  local pid="$1" needle="$2" cmd
  cmd="$(ps -o command= -p "$pid" 2>/dev/null || true)"
  [[ -n "$cmd" ]] && [[ "$cmd" == *"$needle"* ]]
}

# ── owner oracle for detached (ppid=1) sweep subjects ──────────────────────
# REAPER-AGE-CRITERION-NEVER-REACHES-THE-POPULATION-01: the owning session of
# a detached sweep is read from the subject's OWN environment (`ps eww`,
# same-user) — hooks spawn detached sweeps inheriting the session env, which
# carries CLAUDE_PID=<claude process pid> and CLAUDE_CODE_SESSION_ID=<sid>
# (observed live 2026-09-06 on a ppid=1 sweeper orphan: both present, its
# spawner's sandbox root already deleted). Priority: CLAUDE_PID first — the
# process-level three-answer check is the strongest sign; the transcript
# oracle only when no readable CLAUDE_PID. Neither readable -> unknown, and
# unknown NEVER kills (age branch only, unchanged behaviour).
_owner_death_state() {  # ENV_STRING AGE_SEC -> "live"|"unknown"|"dead(<how>)"
  local env="$1" age="$2" v death
  if [[ "$env" == *"CLAUDE_PID="* ]]; then
    v="${env##*CLAUDE_PID=}"
    v="${v%%[[:space:]]*}"
    v="${v//[\"\']/}"
    if [[ "$v" =~ ^[0-9]+$ ]]; then
      if _pid_alive "$v"; then
        printf 'live'
      else
        printf 'dead(owner claude pid %s: kill -0 says gone)' "$v"
      fi
      return 0
    fi
  fi
  if [[ "$env" == *"CLAUDE_CODE_SESSION_ID="* ]]; then
    v="${env##*CLAUDE_CODE_SESSION_ID=}"
    v="${v%%[[:space:]]*}"
    v="${v//[\"\']/}"
    case "$v" in
      ''|*[!0-9a-fA-F-]*) ;;
      *)
        death="$(_session_death_age_min "$v")"
        if [[ "$death" == "alive" ]]; then
          printf 'live'
        elif [[ "$death" == "absent" ]] && (( age < REAPER_ABSENT_GRACE_S )); then
          printf 'unknown'    # young process + missing transcript = fixture/race, never a kill
        else
          printf 'dead(owner session %s: transcript %s)' "$v" "$death"
        fi
        return 0
        ;;
    esac
  fi
  printf 'unknown'
}

# ── leaves-first chain termination ─────────────────────────────────────────
# CONTROL-PLANE-SATURATES-01/reaper-constraint-20260906T1550Z.md: kill the
# LEAF, never the wrapper — TERMing a parent first guarantees a reparented
# survivor (observed on the lead's own double pulse: kill rc=0, wrapper gone,
# the real watcher survived to ppid=1, strict count unmoved at 14).
#
# Cost discipline: the descendant walk is ONE `ps ax` snapshot per run (lazy,
# cached) plus ONE awk per subject — never a ps/pgrep per node. A per-node
# `pgrep -P` walk measured 3:45 wall for 20 subjects / 119 processes on a
# saturated machine; the snapshot form costs one ps total. A descendant
# spawned after the snapshot escapes this pass and is caught by the next
# (the reaper runs at every SessionStart). The seen-set makes a malformed
# (cyclic) ps graph terminate instead of recursing forever.
_EDGE_SNAPSHOT=""
_edges() {  # "ppid pid" lines, snapshotted once per run
  if [[ -z "$_EDGE_SNAPSHOT" ]]; then
    _EDGE_SNAPSHOT="$(ps ax -o ppid=,pid= 2>/dev/null || true)"
  fi
  printf '%s' "$_EDGE_SNAPSHOT"
}

_descendants_deepest_first() {  # ROOT -> descendant pids, deepest level first
  [[ "$1" =~ ^[0-9]+$ ]] || return 0
  _edges | awk -v root="$1" '
    { ch[$1] = ch[$1] " " $2 }
    END {
      seen[root] = 1
      lvl[1] = ch[root]; l = 1
      while (lvl[l] != "") {
        m = split(lvl[l], cur, " "); lvl[l + 1] = ""
        for (i = 1; i <= m; i++) {
          if (cur[i] == "" || seen[cur[i]]++) continue
          lvl[l + 1] = lvl[l + 1] " " ch[cur[i]]
        }
        l++
      }
      for (x = l - 1; x >= 1; x--) {
        m = split(lvl[x], cur, " ")
        for (i = 1; i <= m; i++) if (cur[i] != "") print cur[i]
      }
    }'
}

_term_chain_leaf_first() {  # PID REASON — grandchildren, children, then the subject
  local pid="$1" reason="$2" d
  for d in $(_descendants_deepest_first "$pid"); do
    _term "$d" "${reason} (descendant of ${pid})"
  done
  _term "$pid" "$reason"
}

_term() {  # _term PID REASON — honours DRY_RUN, counts, always idempotent
  local pid="$1" reason="$2"
  if (( DRY_RUN )); then
    _reap_log "DRY-RUN would TERM pid=$pid ($reason)"
  else
    if kill -TERM "$pid" 2>/dev/null; then
      _reap_log "TERM pid=$pid ($reason)"
    else
      _reap_log "TERM pid=$pid failed ($reason) — treating as already gone"
    fi
  fi
  _killed=$((_killed+1))
}

# ── subject 1: anti-silence-pulse loops ────────────────────────────────────
# Session id sits in the pidfile NAME: anti-silence-pulse.<sid>.pid (hook
# arms one per session) or anti-silence-pulse.<sid>.<key>.pid (unverified-
# takeover instance key). The <sid> is the FIRST dot-field after the prefix.
# The pidfile walk is authoritative; a process-table walk catches pulses
# whose pidfile went missing while the loop lived (observed 2026-09-06: a
# buggy reaper dry-run unlinked live pidfiles) — same-user `ps eww` exposes
# the process's own PULSE_PID_FILE env, which carries the same session id.
_pulse_seen=" "
# A pulse is a CHILD of the arming session's process chain (claude → shell
# wrapper → pulse), unlike nohup'd loops. So a pulse gets TWO independent
# death signals, both required: transcript idle/absent AND the owner chain
# broken. The chain walk caught a live false-positive on 2026-09-06: session
# 065edeee's transcript was 790 min idle (live-but-silent REPL) while its
# claude process 8525 was ALIVE — transcript alone would have killed a
# working pulse of a living session. Live-but-idle must survive the reaper.
_pulse_owner_chain_broken() {  # PID -> rc=0 broken (orphaned), rc=1 intact/unknown
  local pid="$1" p i comm
  p="$pid"
  for i in 1 2 3 4 5; do
    p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
    [[ -n "$p" ]] || return 1          # unobservable — no positive proof, keep
    [[ "$p" == "1" ]] && return 0      # reached launchd without meeting claude
    comm="$(ps -o comm= -p "$p" 2>/dev/null || true)"
    case "$comm" in
      *claude*) return 1 ;;            # a LIVE claude owns the chain — never reap
    esac
  done
  return 1                              # deep chain without a verdict — keep
}

_pulse_death_verdict() {  # PID SID -> rc=0 killed, rc=1 keep
  local pid="$1" sid="$2" age death
  death="$(_session_death_age_min "$sid")"
  [[ "$death" == "alive" ]] && return 1
  if [[ "$death" == "absent" ]]; then
    age="$(_pid_etime_sec "$pid")"
    (( age >= REAPER_ABSENT_GRACE_S )) || return 1
  fi
  _pulse_owner_chain_broken "$pid" || return 1
  if [[ "$death" == "absent" ]]; then
    _term "$pid" "pulse of session $sid: transcript absent, process ${age}s old (>$((REAPER_ABSENT_GRACE_S))s grace), owner chain broken"
  else
    _term "$pid" "pulse of session $sid: transcript ${death#idle:} min idle (>=$REAPER_IDLE_MIN), owner chain broken"
  fi
  return 0
}

reap_pulses() {
  local root pidfile base sid pid death age ident env pf
  local -a roots=("$PROJECT_ROOT/docs/leadv2")
  local wt
  while IFS= read -r wt; do
    [[ -d "$wt/docs/leadv2" ]] && roots+=("$wt/docs/leadv2")
  done < <(find "$PROJECT_ROOT/.claude/worktrees" -maxdepth 1 -mindepth 1 -type d 2>/dev/null || true)

  for root in "${roots[@]}"; do
    for pidfile in "$root"/anti-silence-pulse.*.pid; do
      [[ -f "$pidfile" ]] || continue
      base="$(basename "$pidfile")"
      base="${base%.pid}"
      base="${base#anti-silence-pulse.}"
      sid="${base%%.*}"                      # first dot-field = session id
      case "$sid" in
        ''|*[!0-9a-fA-F-]*) continue ;;      # not session-shaped — skip
      esac
      pid="$(cat "$pidfile" 2>/dev/null || true)"
      if ! _pid_alive "$pid"; then
        (( DRY_RUN )) || rm -f "$pidfile" "${pidfile}.birth"   # dead holder: file is litter
        continue
      fi
      _pulse_seen="$_pulse_seen$pid "
      ident="$(_pid_identity "$pid" "${pidfile}.birth")"
      if [[ "$ident" == "mismatch" ]]; then
        _reap_log "pulse pidfile $pidfile: pid recycled (birth mismatch) — unlinking file only"
        (( DRY_RUN )) || rm -f "$pidfile" "${pidfile}.birth"
        continue
      fi
      if ! _argv_verified "$pid" "anti-silence-pulse.sh"; then
        continue                             # live pid, but not a pulse — leave it
      fi
      _seen_pulses=$((_seen_pulses+1))
      if _pulse_death_verdict "$pid" "$sid"; then
        _killed_pulses=$((_killed_pulses+1))
        (( DRY_RUN )) || rm -f "$pidfile" "${pidfile}.birth"
      fi
    done
  done

  # table sweep: pidfile-less pulses (env carries PULSE_PID_FILE)
  for pid in $(pgrep -f "anti-silence-pulse.sh" 2>/dev/null || true); do
    [[ "$pid" != "$$" ]] || continue
    case "$_pulse_seen" in *" $pid "*) continue ;; esac
    _argv_verified "$pid" "anti-silence-pulse.sh" || continue
    env="$(ps eww -o command= -p "$pid" 2>/dev/null || true)"
    [[ "$env" == *"PULSE_PID_FILE="* ]] || continue   # no env readable — no positive proof
    pf="${env##*PULSE_PID_FILE=}"
    pf="${pf%% *}"
    pf="${pf%\"}"; pf="${pf#\"}"
    base="$(basename "$pf" 2>/dev/null || true)"
    [[ "$base" == anti-silence-pulse.* ]] || continue
    base="${base%.pid}"
    base="${base#anti-silence-pulse.}"
    sid="${base%%.*}"
    case "$sid" in
      ''|*[!0-9a-fA-F-]*) continue ;;
    esac
    _pulse_seen="$_pulse_seen$pid "
    _seen_pulses=$((_seen_pulses+1))
    if _pulse_death_verdict "$pid" "$sid"; then
      _killed_pulses=$((_killed_pulses+1))
    fi
  done
}

# ── subjects 2+3: oneshot sweeps — TWO kill branches, never age-only ───────
# Branch A (kept): age — etime over the stuck threshold is positive death of
#   a oneshot's progress. Right for any process, orphaned or not.
# Branch B (new): for a ppid=1 candidate, POSITIVE death of the owning
#   session — the population reaches ppid=1 in under a minute and dies before
#   the age gate, so age alone reaped an honest 0 over 18 live orphans
#   (REAPER-AGE-CRITERION-NEVER-REACHES-THE-POPULATION-01). Owner state comes
#   from _owner_death_state; "unknown" never kills.
# Every kill goes _term_chain_leaf_first: grandchildren before children
# before the subject, so no descendant survives its parent into ppid=1.
# <kind> selects which global counters this call updates ("sweeper" |
# "cleanup") -- reported alongside the kill count so a candidate that is
# orphaned (ppid=1) but spared (owner live/unknown, too young) is VISIBLE as
# seen-but-spared, never silently folded into the same "0" a truly empty
# population would report.
reap_stuck_by_age() {  # <pattern> <needle> <max_sec> <label> <kind>
  local pattern="$1" needle="$2" max_sec="$3" label="$4" kind="$5"
  local pid age cmd ppid env owner why
  local scope="${LEADV2_REAPER_SUBJECT_SCOPE:-}"
  for pid in $(pgrep -f "$pattern" 2>/dev/null || true); do
    [[ "$pid" != "$$" ]] || continue
    cmd="$(ps -o command= -p "$pid" 2>/dev/null || true)"
    [[ -n "$cmd" ]] || continue
    [[ "$cmd" == *"$needle"* ]] || continue
    # hermetic runs (suites) restrict subjects to their own fixtures; unset
    # in production -- the live control plane is never scoped away.
    if [[ -n "$scope" ]]; then
      [[ "$cmd" == *"$scope"* ]] || continue
    fi
    age="$(_pid_etime_sec "$pid")"
    ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    owner="unknown"
    if [[ "$ppid" == "1" ]]; then
      env="$(ps eww -o command= -p "$pid" 2>/dev/null || true)"
      owner="$(_owner_death_state "$env" "$age")"
    fi
    case "$kind" in
      sweeper)
        _seen_sweeper=$((_seen_sweeper+1))
        if [[ "$ppid" == "1" ]]; then
          _seen_sweeper_ppid1=$((_seen_sweeper_ppid1+1))
          case "$owner" in
            dead*) _seen_sweeper_owner_dead=$((_seen_sweeper_owner_dead+1)) ;;
            live)  _seen_sweeper_owner_live=$((_seen_sweeper_owner_live+1)) ;;
          esac
        fi
        (( age >= max_sec )) && _seen_sweeper_stuck=$((_seen_sweeper_stuck+1)) ;;
      cleanup)
        _seen_cleanup=$((_seen_cleanup+1))
        if [[ "$ppid" == "1" ]]; then
          _seen_cleanup_ppid1=$((_seen_cleanup_ppid1+1))
          case "$owner" in
            dead*) _seen_cleanup_owner_dead=$((_seen_cleanup_owner_dead+1)) ;;
            live)  _seen_cleanup_owner_live=$((_seen_cleanup_owner_live+1)) ;;
          esac
        fi
        (( age >= max_sec )) && _seen_cleanup_stuck=$((_seen_cleanup_stuck+1)) ;;
    esac
    why=""
    if (( age >= max_sec )); then
      why="$label stuck: ${age}s old (>=$max_sec)"
    elif [[ "$ppid" == "1" && "$owner" == dead* ]]; then
      why="$label orphan: ppid=1, ${age}s old (under the $max_sec age gate), $owner"
    fi
    [[ -n "$why" ]] || continue
    _term_chain_leaf_first "$pid" "$why"
    case "$kind" in
      sweeper) _killed_sweeper=$((_killed_sweeper+1)) ;;
      cleanup) _killed_cleanup=$((_killed_cleanup+1)) ;;
    esac
  done
}

# Hermetic-scope gate: LEADV2_REAPER_SUBJECT_SCOPE (see header) filters the
# sweeper/cleanup subjects below; pulses have no per-fixture scoping, so
# under a scope they are skipped ENTIRELY — a suite must never TERM a real
# pulse of another session while proving sweeper behaviour
# (SUITES-MUTATE-LIVE-CONTROL-PLANE-01). Production runs leave the scope
# unset and reap every subject. The beat-loop subject 4 was deleted with the
# retired single-lead-beat chain (ONE-STATUS-MECHANISM-01, 2026-09-13): the
# spawner is gone, so its population is permanently zero.
if [[ -n "${LEADV2_REAPER_SUBJECT_SCOPE:-}" ]]; then
  _reap_log "subject-scope active: pulse subjects skipped (hermetic pass)"
else
  reap_pulses
fi
reap_stuck_by_age "leadv2-stale-sweeper.sh" "leadv2-stale-sweeper.sh" \
  "$SWEEPER_STUCK_SEC" "stale-sweeper full sweep" "sweeper"
reap_stuck_by_age "leadv2-worktree-cleanup.sh --sweep-dead" "leadv2-worktree-cleanup.sh --sweep-dead" \
  "$CLEANUP_STUCK_SEC" "worktree-cleanup --sweep-dead" "cleanup"

# REAPER-AGE-CRITERION-NEVER-REACHES-THE-POPULATION-01: one line per subject,
# each candidate count carrying the signal it was counted against -- never a
# bare number. A subject line with candidates=0 says "nothing here"; a
# subject line with candidates>0 and killed=0 says "seen, spared by the
# criteria below" -- the two are no longer the same "0" in the summary.
_verb="$( (( DRY_RUN )) && printf would-kill || printf termed )"
if [[ -n "${LEADV2_REAPER_SUBJECT_SCOPE:-}" ]]; then
  _reap_log "subject-scope: ${LEADV2_REAPER_SUBJECT_SCOPE} (hermetic pass — subjects outside the scope are invisible to THIS run only)"
fi
_reap_log "pulses: candidates=${_seen_pulses} (argv-verified alive: ${_seen_pulses}) ${_verb}=${_killed_pulses}"
_reap_log "sweeper: candidates=${_seen_sweeper} (ppid=1: ${_seen_sweeper_ppid1}, older_than=${SWEEPER_STUCK_SEC}s: ${_seen_sweeper_stuck}, owner_dead: ${_seen_sweeper_owner_dead}, owner_live: ${_seen_sweeper_owner_live}) ${_verb}=${_killed_sweeper}"
_reap_log "cleanup: candidates=${_seen_cleanup} (ppid=1: ${_seen_cleanup_ppid1}, older_than=${CLEANUP_STUCK_SEC}s: ${_seen_cleanup_stuck}, owner_dead: ${_seen_cleanup_owner_dead}, owner_live: ${_seen_cleanup_owner_live}) ${_verb}=${_killed_cleanup}"

# Summary counts SUBJECTS (a subject = one death-verified chain root), while
# _killed counts every TERM dispatched, descendants included — the two differ
# exactly when leaf-first chain kills ran, and the line says which is which.
_subjects_total=$(( _killed_pulses + _killed_sweeper + _killed_cleanup ))
printf '[orphan-reaper] %s: %d subject(s) (%d process TERM(s) incl. descendants) %s\n' \
  "$( (( DRY_RUN )) && printf dry-run || printf reaped )" \
  "$_subjects_total" "$_killed" "$( (( DRY_RUN )) && printf 'would-reap' || printf 'termed' )" >&2
exit 0
