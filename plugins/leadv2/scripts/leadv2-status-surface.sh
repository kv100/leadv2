#!/usr/bin/env bash
# leadv2-status-surface.sh — SUPERVISOR-STATUS-SURFACE-02
#
# A cheap, always-fresh, terminal-INDEPENDENT status surface for the leadv2
# supervisor. Pure local file reads — ZERO LLM calls, zero network, zero
# Supabase. Designed target <150 ms wall (one python3 start ~35 ms).
#
# Why this exists (founder order 2026-07-31): the Claude statusline proved
# fragile for supervisor visibility — ghost lanes from a stale sentinel, memo-TTL
# lag, and it dies with the session that owned it. This renderer reads the same
# truth the supervisor loop does, marks every lane LIVE-with-a-cause or DEAD-with-
# a-cause, and never renders a bare "?" or silently omits a row.
#
# READ-ONLY. This script never writes active.yaml, the ledger, a run dir, or any
# state file. Freshness is the whole point; there is no cache/memo layer.
#
# Sources (all env-injected so tests never touch the real ~/.claude):
#   S1 active.yaml          <STATE_DIR>/active.yaml
#   S2 supervise sentinel   <STATE_DIR>/.supervise-active        (first int = pid)
#   S3 supervise heartbeat  <STATE_DIR>/.supervise-loop.heartbeat (mtime only)
#   S4 dispatch ledger      <LEDGER_DIR>/<repo>.jsonl             (tail -n 400 bound)
#   S5 provider runs        <RUNS_ROOT>/{glm,kimi}-runs/<handle>/{meta.yaml,journal.jsonl}
#
# Usage:
#   leadv2-status-surface.sh             # multi-line table (default)
#   leadv2-status-surface.sh --oneline   # single embedded line
#
# Env (every var read with ${X:-default}; unset IS the production path):
#   LEADV2_STATUS_STATE_DIR   default: leadv2-state-path.sh --no-link root
#   LEADV2_STATUS_LEDGER_DIR  default: ~/.claude/cache/dispatch-ledger
#   LEADV2_STATUS_RUNS_ROOT   default: ~/.claude/cache
#   LEADV2_STATUS_REPO        default: basename of git toplevel, else persona-engine
#   LEADV2_STATUS_NOW         default: date +%s   (frozen clock for tests)
#
# Naming follows the LEADV2_* convention; no LEAD_V2_* form is introduced.
# All bash comparisons use POSIX single-bracket tests [ x = y ] / [ "$a" -gt
# "$b" ]; double-bracket == is banned here (eval-adjacent glob-match hazard) —
# verified by the test suite.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_PATH_SH="${SCRIPT_DIR}/leadv2-state-path.sh"

# ── Resolve env ─────────────────────────────────────────────────────────────
# STATE_DIR default MUST go through leadv2-state-path.sh --no-link: rendering
# must never mutate a worktree's symlink set as a side effect of being read.
if [ -n "${LEADV2_STATUS_STATE_DIR:-}" ]; then
  STATE_DIR="${LEADV2_STATUS_STATE_DIR}"
elif [ -x "${STATE_PATH_SH}" ]; then
  STATE_DIR="$(bash "${STATE_PATH_SH}" --no-link root 2>/dev/null || true)"
else
  STATE_DIR=""
fi
LEDGER_DIR="${LEADV2_STATUS_LEDGER_DIR:-${HOME}/.claude/cache/dispatch-ledger}"
RUNS_ROOT="${LEADV2_STATUS_RUNS_ROOT:-${HOME}/.claude/cache}"
NOW="${LEADV2_STATUS_NOW:-$(date +%s)}"
# STATUS-SURFACE-R5-01 (defect 2): terminal-lane retention. A done/dead row
# drops off the list after a short window so a wall of corpses stops burying
# the one genuinely stuck lane. Live rows are NEVER aged out (any age). Both
# knobs are env-overridable for the regression suite.
DONE_TTL="${LEADV2_STATUS_DONE_TTL_S:-900}"   # 15 min for done(exit=0) rows
DEAD_TTL="${LEADV2_STATUS_DEAD_TTL_S:-3600}"  # 60 min for dead(...) rows (a
                                              # crashed lane needs a longer
                                              # window than a clean finish)
# N-7c: freshness window for a ledger handle we cannot identity-check (argv
# lacks dispatch-<sig8>). 0 = identity-only (strictest). No value restores
# bare-pid trust.
HANDLE_TRUST_S="${LEADV2_STATUS_HANDLE_TRUST_S:-900}"
# N-7d: close-phase (act two) signals. Motion inside a lane's
# docs/handoff/dispatch-<sig8>/ newer than CLOSE_FRESH_S names the act "gate"
# and resets the silence clock, but never by itself yields live (see §2 of
# the N-7d design: a process makes a row live, an artifact only moves the
# clock). SCAN_MAX bounds the per-lane directory stat cost.
CLOSE_FRESH_S="${LEADV2_STATUS_CLOSE_FRESH_S:-600}"
CLOSE_SCAN_MAX="${LEADV2_STATUS_CLOSE_SCAN_MAX:-400}"
# R1 (fix round 3): tasks.yaml title-lookup source. Default = <git toplevel>/
# docs/tasks.yaml if present, else empty (degrades to dispatch-<sig8> names).
TASKS_YAML="${LEADV2_STATUS_TASKS_YAML:-}"
if [ -z "$TASKS_YAML" ]; then
  _ty_top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$_ty_top" ] && [ -f "${_ty_top}/docs/tasks.yaml" ]; then
    TASKS_YAML="${_ty_top}/docs/tasks.yaml"
  fi
fi
unset _ty_top
# STATUS-SURFACE-R5-01 (defect 1, C1a): handoff dir for Rule 2.5 name
# resolution. Reuses the render_questions() resolution pattern (env override
# else <git toplevel>/docs/handoff), lifted to a single shell-level resolution
# so the lanes python block can read it without each lane re-resolving.
HANDOFF_DIR="${LEADV2_STATUS_HANDOFF_DIR:-}"
if [ -z "$HANDOFF_DIR" ]; then
  _hd_top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$_hd_top" ] && [ -d "${_hd_top}/docs/handoff" ] && HANDOFF_DIR="${_hd_top}/docs/handoff"
fi
unset _hd_top
if [ -n "${LEADV2_STATUS_REPO:-}" ]; then
  REPO="${LEADV2_STATUS_REPO}"
else
  _top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$_top" ]; then
    REPO="$(basename "$_top")"
  else
    REPO="persona-engine"
  fi
fi
unset _top

# ── SWIFTBAR-LIVE-01: cwd-independent multi-project lane enumeration ───────
# Only engaged when the caller did NOT pin LEADV2_STATUS_STATE_DIR — that env
# var remains the single-project, byte-identical-output regression contract
# (the existing test suite's run_render() always sets it, so this whole block
# is a strict no-op for every pre-existing test). The supervisor gate below
# (round 2, §2.5) resolves over the UNION of PROJ_STATE_DIRS populated by
# THIS block — the supervisor is a machine-wide singleton, not swept
# per-project, but its beat/sentinel lookup no longer pins to a single cwd-
# derived STATE_DIR.
MULTI_PROJECT=0
PROJ_SLUGS=()
PROJ_STATE_DIRS=()
PROJ_REPO_ROOTS=()
if [ -z "${LEADV2_STATUS_STATE_DIR:-}" ]; then
  PROJECTS_SH="${LEADV2_STATUS_PROJECTS_SH:-${SCRIPT_DIR}/leadv2-status-projects.sh}"
  if [ -x "$PROJECTS_SH" ]; then
    _proj_tsv="$(bash "$PROJECTS_SH" 2>/dev/null || true)"
    if [ -n "$_proj_tsv" ]; then
      while IFS="$(printf '\t')" read -r _pslug _psdir _prroot; do
        [ -n "$_pslug" ] || continue
        PROJ_SLUGS+=("$_pslug")
        PROJ_STATE_DIRS+=("$_psdir")
        PROJ_REPO_ROOTS+=("$_prroot")
      done <<EOF
$_proj_tsv
EOF
    fi
    unset _proj_tsv
  fi
  PROJECT_COUNT="${#PROJ_SLUGS[@]}"
  if [ "$PROJECT_COUNT" -ge 2 ]; then
    MULTI_PROJECT=1
  elif [ "$PROJECT_COUNT" -eq 1 ]; then
    # Single enumerated project: point the existing single-project vars at it
    # so the rest of the script (unchanged) renders exactly as if
    # LEADV2_STATUS_STATE_DIR had been pinned to it -- no PROJ column.
    STATE_DIR="${PROJ_STATE_DIRS[0]}"
    REPO="${PROJ_SLUGS[0]}"
    _p_root="${PROJ_REPO_ROOTS[0]}"
    TASKS_YAML=""
    [ -f "${_p_root}/docs/tasks.yaml" ] && TASKS_YAML="${_p_root}/docs/tasks.yaml"
    HANDOFF_DIR=""
    [ -d "${_p_root}/docs/handoff" ] && HANDOFF_DIR="${_p_root}/docs/handoff"
    export LEADV2_STATUS_REPO_ROOT="${_p_root}"
    unset _p_root
  fi
  # PROJECT_COUNT -eq 0: leave the pre-existing cwd/git-derived STATE_DIR/etc
  # resolved above as-is (so a checkout with a valid cwd-derived STATE_DIR
  # but no .repo-root marker yet does not regress). Only when THAT fallback
  # also produced nothing usable do we surface the named "no project state"
  # cause instead of the generic "active.yaml не прочитан" warning.
  if [ "$PROJECT_COUNT" -eq 0 ]; then
    if [ -z "$STATE_DIR" ] || [ ! -f "${STATE_DIR}/active.yaml" ]; then
      ZERO_PROJECTS=1
      ZERO_PROJECTS_BASE="${LEADV2_STATE_BASE:-${HOME}/.claude/leadv2-state}"
    fi
  fi
fi
ZERO_PROJECTS="${ZERO_PROJECTS:-0}"
ZERO_PROJECTS_BASE="${ZERO_PROJECTS_BASE:-}"

# Round 4: opt-in section flags. BARE invocation stays byte-identical to the
# pre-round-4 renderer (the regression contract for the 32 existing tests) —
# only an explicit flag changes the output. Unknown flag → usage, exit 2.
MODE="default"
_usage_r4() {
  printf -- 'Usage: leadv2-status-surface.sh [flag]\n' >&2
  printf -- '  (no flag)         lanes table (default; byte-identical to pre-round-4)\n' >&2
  printf -- '  --oneline         single embedded line\n' >&2
  printf -- '  --questions       pending founder questions section\n' >&2
  printf -- '  --limits          per-provider quota limits section (reads a snapshot)\n' >&2
  printf -- '  --due             scheduled-decisions due/overdue count\n' >&2
  printf -- '  --alarms          urgent alarm count (supervise events, 4h)\n' >&2
  printf -- '  --all             lanes table + --- + every section above\n' >&2
  printf -- '  --refresh-limits  run leadv2-quota-status.sh and write the limits snapshot\n' >&2
}
while [ $# -gt 0 ]; do
  case "$1" in
    --oneline)        MODE="oneline" ;;
    --questions)      MODE="questions" ;;
    --limits)         MODE="limits" ;;
    --due)            MODE="due" ;;
    --alarms)         MODE="alarms" ;;
    --all)            MODE="all" ;;
    --refresh-limits) MODE="refresh-limits" ;;
    -h|--help)        _usage_r4; exit 0 ;;
    --*)              _usage_r4; exit 2 ;;
    *)                _usage_r4; exit 2 ;;
  esac
  shift
done
unset -f _usage_r4 2>/dev/null || true

LEDGER_FILE="${LEDGER_DIR}/${REPO}.jsonl"

# SWIFTBAR-LIVE-01 round 2 (§2.1): one `ps` snapshot, not N pgreps per row --
# the surface renders on a 10s SwiftBar tick and must not fork per row.
# Absolute path: SwiftBar's stripped PATH is /usr/bin:/bin, where `ps` may
# not resolve unqualified. Overridable so tests can inject a synthetic
# snapshot and get a deterministic offline liveness signal.
PS_SNAPSHOT="${LEADV2_STATUS_PS_SNAPSHOT:-$(/bin/ps -Ao pid=,args= 2>/dev/null || true)}"

# ── Portable mtime (macOS stat -f %m, Linux stat -c %Y) ─────────────────────
_mtime() {
  # echo epoch seconds or empty; never fails the pipeline
  local f="$1"
  [ -z "$f" ] && { printf ''; return; }
  [ -e "$f" ] || { printf ''; return; }
  stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || printf ''
}

# ── R4: kill -0 with EPERM-as-alive ─────────────────────────────────────────
# A foreign-uid pid makes kill -0 return exit 1 with "Operation not permitted" —
# that is a LIVE process we just can't signal. Treat EPERM as alive so we never
# false-DEAD a lane whose worker runs under a different uid.
_pid_alive() {
  local pid="$1" err
  if [ -z "$pid" ]; then return 1; fi
  if err="$(kill -0 "$pid" 2>&1)"; then
    return 0
  fi
  case "$err" in
    *"Operation not permitted"*) return 0 ;;
    *) return 1 ;;
  esac
}

# ── Age label: <60s -> Ns, <90m -> Nm, else Nh ──────────────────────────────
_age_label() {
  local secs="$1"
  case "$secs" in
    ''|*[!0-9]*) secs=0 ;;
  esac
  if [ "$secs" -lt 60 ]; then
    printf '%ss' "$secs"
  elif [ "$secs" -lt 5400 ]; then
    printf '%sm' "$(( secs / 60 ))"
  else
    printf '%sh' "$(( secs / 3600 ))"
  fi
}

# ── Supervisor gate (SUP-OFF-IS-A-LIE-01), pure bash ────────────────────────
# Heartbeat is the PRIMARY liveness signal; the sentinel is corroborating. The
# supervise loop writes .supervise-loop.heartbeat every ~60s — a fresh beat IS
# the supervisor alive, even when the sentinel bookkeeping file is missing or
# split across two directories. Gating the whole block on `[ -f $SENTINEL ]`
# (the pre-fix reader) collapsed three distinct worlds (nothing running /
# stale sentinel / reader looking in the wrong place) into one bare `OFF` —
# false-RED, the mirror of lying-green. Now both signals are stat'd
# unconditionally and the truth table below decides.
#
# Emits globals: SUP_STATE (on|off|stale), SUP_PID (int or "" — ON no longer
# implies a non-empty pid), SUP_BEAT ("beat <label>" or "", now populated in
# every state that has a beat file), SUP_BEAT_AGE_SECS, SUP_WHY (always a
# non-empty reason), SUP_SHORT (compact reason for the width-constrained
# statusline head).
SUP_STATE="off"
SUP_PID=""
SUP_BEAT=""
SUP_BEAT_AGE_SECS=""
SUP_WHY=""
SUP_SHORT=""
# SUP-OFF-IS-A-LIE-01 D5: beat freshness TTL. The loop beats ~60s; the default
# 300s tolerates ~4 missed beats. Non-numeric/empty => silently fall back to
# 300 — a malformed knob must never `set -u`-abort the whole statusline (the
# R6 failure mode this file already guards against).
SUP_BEAT_TTL="${LEADV2_SUPERVISE_BEAT_TTL_SECS:-300}"
case "$SUP_BEAT_TTL" in
  ''|*[!0-9]*) SUP_BEAT_TTL=300 ;;
esac
# SWIFTBAR-LIVE-01 round 2 (§2.5): the supervisor is a machine-wide
# singleton, not one per repo -- so its state must resolve over the UNION of
# enumerated projects (already cwd-independent, PROJ_STATE_DIRS is rooted at
# $HOME via leadv2-status-projects.sh), never the single cwd-derived
# STATE_DIR. LEADV2_STATUS_STATE_DIR stays the pinned single-project test
# contract, unchanged. Bash 3.2: indexed arrays only.
SUP_DIRS=()
if [ -n "${LEADV2_STATUS_STATE_DIR:-}" ]; then
  SUP_DIRS=("$STATE_DIR")
elif [ "${#PROJ_STATE_DIRS[@]}" -gt 0 ]; then
  SUP_DIRS=("${PROJ_STATE_DIRS[@]}")
else
  SUP_DIRS=("$STATE_DIR")
fi

# BEAT = the .supervise-loop.heartbeat with the NEWEST mtime across all
# resolved dirs -- a singleton loop writes exactly one; "newest" is the safe
# reducer if a stale one lingers from an old project.
BEAT=""
_sup_beat_mtime=-1
for _sd in "${SUP_DIRS[@]}"; do
  [ -n "$_sd" ] || continue
  _cand="${_sd}/.supervise-loop.heartbeat"
  [ -f "$_cand" ] || continue
  _cm="$(_mtime "$_cand")"
  [ -n "$_cm" ] || continue
  if [ "$_cm" -gt "$_sup_beat_mtime" ]; then
    _sup_beat_mtime="$_cm"
    BEAT="$_cand"
  fi
done
unset _sd _cand _cm _sup_beat_mtime
[ -n "$BEAT" ] || BEAT="${STATE_DIR}/.supervise-loop.heartbeat"

# SENTINEL = the first .supervise-active whose parsed pid is alive; else the
# first that exists (so "sentinel pid gone" still fires); else empty (falls
# through to the canonical-sentinel-absent branch below, unchanged).
SENTINEL=""
_sup_sentinel_fallback=""
for _sd in "${SUP_DIRS[@]}"; do
  [ -n "$_sd" ] || continue
  _cand="${_sd}/.supervise-active"
  [ -f "$_cand" ] || continue
  [ -n "$_sup_sentinel_fallback" ] || _sup_sentinel_fallback="$_cand"
  _cpid="$(awk 'match($0,/[0-9]+/){print substr($0,RSTART,RLENGTH); exit}' "$_cand" 2>/dev/null || true)"
  if [ -n "$_cpid" ] && _pid_alive "$_cpid"; then
    SENTINEL="$_cand"
    break
  fi
done
[ -n "$SENTINEL" ] || SENTINEL="$_sup_sentinel_fallback"
[ -n "$SENTINEL" ] || SENTINEL="${STATE_DIR}/.supervise-active"
unset _sd _cand _cpid _sup_sentinel_fallback

# Stat the heartbeat UNCONDITIONALLY — it is the primary signal. Require a
# regular file (`-f`, not `-e`): a directory or FIFO accidentally on the beat
# path would otherwise supply an mtime and false-ON (or hang on a FIFO read).
if [ -f "$BEAT" ]; then
  _bm="$(_mtime "$BEAT")"
  if [ -n "$_bm" ]; then
    SUP_BEAT_AGE_SECS=$(( NOW - _bm ))
    [ "$SUP_BEAT_AGE_SECS" -lt 0 ] && SUP_BEAT_AGE_SECS=0
    SUP_BEAT="beat $(_age_label "$SUP_BEAT_AGE_SECS")"
  fi
  unset _bm
fi
_beat_fresh=0
if [ -n "$SUP_BEAT_AGE_SECS" ] && [ "$SUP_BEAT_AGE_SECS" -le "$SUP_BEAT_TTL" ]; then
  _beat_fresh=1
fi

# Parse the sentinel pid (corroborating). SUP_STATE is decided below, not by
# a sentinel-only gate.
if [ -f "$SENTINEL" ]; then
  SUP_PID="$(awk 'match($0,/[0-9]+/){print substr($0,RSTART,RLENGTH); exit}' "$SENTINEL" 2>/dev/null || true)"
fi

# A live supervisor = fresh beat OR live sentinel pid (each is independently
# sufficient). Truth table rows map 1:1 to the design.
_live_pid=0
if [ -f "$SENTINEL" ] && [ -n "$SUP_PID" ] && _pid_alive "$SUP_PID"; then
  _live_pid=1
fi

if [ "$_beat_fresh" -eq 1 ] || [ "$_live_pid" -eq 1 ]; then
  SUP_STATE="on"
  if [ "$_live_pid" -eq 1 ]; then
    if [ -n "$SUP_BEAT_AGE_SECS" ]; then
      SUP_WHY="pid ${SUP_PID}, beat $(_age_label "$SUP_BEAT_AGE_SECS")"
      SUP_SHORT="${SUP_PID},$(_age_label "$SUP_BEAT_AGE_SECS")"
    else
      SUP_WHY="pid ${SUP_PID}, no beat"
      SUP_SHORT="${SUP_PID},nobeat"
    fi
  elif [ -n "$SUP_PID" ]; then
    SUP_WHY="heartbeat only, beat $(_age_label "$SUP_BEAT_AGE_SECS"), sentinel pid ${SUP_PID} gone"
    SUP_SHORT="beat $(_age_label "$SUP_BEAT_AGE_SECS")"
  elif [ -f "$SENTINEL" ]; then
    SUP_WHY="heartbeat only, beat $(_age_label "$SUP_BEAT_AGE_SECS"), sentinel unparsable"
    SUP_SHORT="beat $(_age_label "$SUP_BEAT_AGE_SECS")"
  else
    SUP_WHY="heartbeat only, beat $(_age_label "$SUP_BEAT_AGE_SECS"), no sentinel"
    SUP_SHORT="beat $(_age_label "$SUP_BEAT_AGE_SECS")"
  fi
else
  # Not ON: STALE (half-alive) or OFF (nothing). Bare OFF must never render —
  # every branch carries a reason so the founder can tell the three worlds apart.
  if [ -n "$SUP_PID" ]; then
    SUP_STATE="stale"
    if [ -n "$SUP_BEAT_AGE_SECS" ]; then
      SUP_WHY="sentinel pid ${SUP_PID} gone, beat $(_age_label "$SUP_BEAT_AGE_SECS") old"
      SUP_SHORT="pid ${SUP_PID}"
    else
      SUP_WHY="sentinel pid ${SUP_PID} gone, no beat"
      SUP_SHORT="pid ${SUP_PID}"
    fi
  elif [ -f "$SENTINEL" ]; then
    SUP_STATE="stale"
    if [ -n "$SUP_BEAT_AGE_SECS" ]; then
      SUP_WHY="sentinel unparsable, beat $(_age_label "$SUP_BEAT_AGE_SECS") old"
      SUP_SHORT="beat $(_age_label "$SUP_BEAT_AGE_SECS") old"
    else
      SUP_WHY="sentinel unparsable, no beat"
      SUP_SHORT="unparsable"
    fi
  else
    # canonical sentinel absent
    if [ -n "$SUP_BEAT_AGE_SECS" ]; then
      SUP_STATE="stale"
      SUP_WHY="no sentinel, beat $(_age_label "$SUP_BEAT_AGE_SECS") old"
      SUP_SHORT="beat $(_age_label "$SUP_BEAT_AGE_SECS") old"
    else
      # SUP-OFF-IS-A-LIE-01 D2: legacy-location sweep (read-only diagnostic).
      # A stale real-file sentinel can linger at the pre-fix repo path
      # (docs/leadv2/.supervise-active) when the writer's no-git fallback put
      # it there and the canonical control plane never adopted the orphan.
      # A hit here NEVER yields `on` by itself — it surfaces the split as
      # STALE so it is visible rather than silent. Skip when STATE_DIR already
      # resolves to docs/leadv2 (the no-git fallback) to avoid a double stat.
      _legacy_sentinel=""
      case "$STATE_DIR" in
        */docs/leadv2) : ;;
        *)
          # LEADV2_STATUS_REPO_ROOT lets a test sandbox pin the repo root;
          # otherwise derive it from this invocation's own checkout. The sweep
          # never escapes a sandbox that sets the var (the 5-var isolation wall
          # gains a 6th for this one new read path).
          _lr="${LEADV2_STATUS_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
          if [ -n "$_lr" ] && [ -f "${_lr}/docs/leadv2/.supervise-active" ]; then
            _legacy_sentinel="${_lr}/docs/leadv2/.supervise-active"
          fi
          ;;
      esac
      if [ -n "$_legacy_sentinel" ]; then
        _lpid="$(awk 'match($0,/[0-9]+/){print substr($0,RSTART,RLENGTH); exit}' "$_legacy_sentinel" 2>/dev/null || true)"
        SUP_STATE="stale"
        if [ -n "$_lpid" ]; then
          SUP_WHY="legacy sentinel at docs/leadv2 (pid ${_lpid}), canonical missing"
          SUP_SHORT="legacy pid ${_lpid}"
        else
          SUP_WHY="legacy sentinel at docs/leadv2, canonical missing"
          SUP_SHORT="legacy"
        fi
      else
        SUP_STATE="off"
        SUP_WHY="no sentinel, no heartbeat"
        SUP_SHORT="no beat"
      fi
      unset _legacy_sentinel _lr _lpid
    fi
  fi
fi
unset _beat_fresh _live_pid

# ── Lanes via one python3 start ─────────────────────────────────────────────
# Emits control lines then one TSV row per surviving lane:
#   #LIVE <n>
#   #DEAD <n>
#   <id>\t<display>\t<model>\t<age>\t<cause>\t<class>
# <class> in {live, done, dead}. If python3 is absent OR active.yaml is
# unreadable, a single warn row is emitted instead — never a blank screen (R6).
_ss_lanes_py() {
  python3 2>/dev/null <<'PYEOF'
import os, sys, subprocess

STATE_DIR   = os.environ.get("LEADV2_SS_STATE_DIR", "")
LEDGER_FILE = os.environ.get("LEADV2_SS_LEDGER_FILE", "")
RUNS_ROOT   = os.environ.get("LEADV2_SS_RUNS_ROOT", "")
NOW         = int(os.environ.get("LEADV2_SS_NOW", "0") or "0")
TASKS_YAML  = os.environ.get("LEADV2_SS_TASKS_YAML", "")
HANDOFF_DIR = os.environ.get("LEADV2_SS_HANDOFF_DIR", "")
PS_SNAPSHOT = os.environ.get("LEADV2_SS_PS_SNAPSHOT", "")
try:
    DONE_TTL = int(os.environ.get("LEADV2_SS_DONE_TTL", "900") or "900")
except Exception:
    DONE_TTL = 900
try:
    DEAD_TTL = int(os.environ.get("LEADV2_SS_DEAD_TTL", "3600") or "3600")
except Exception:
    DEAD_TTL = 3600
# N-7c: a ledger `handle` we cannot identity-check (its argv lacks the lane's
# dispatch-<sig8> marker) is trusted only while the row is still demonstrably
# fresh. 0 disables the fresh fallback -> identity-only (strictest). There is
# no value that restores the old bare-pid trust, by design.
try:
    HANDLE_TRUST_S = int(os.environ.get("LEADV2_SS_HANDLE_TRUST_S", "900") or "900")
except Exception:
    HANDLE_TRUST_S = 900
# N-7d: close-phase (act two) signals. See close_dir_mtime()/close_process_alive().
try:
    CLOSE_FRESH_S = int(os.environ.get("LEADV2_SS_CLOSE_FRESH_S", "600") or "600")
except Exception:
    CLOSE_FRESH_S = 600
try:
    CLOSE_SCAN_MAX = int(os.environ.get("LEADV2_SS_CLOSE_SCAN_MAX", "400") or "400")
except Exception:
    CLOSE_SCAN_MAX = 400

# ---- R5-01 round 2: PyYAML-optional YAML reader --------------------------
# SwiftBar/xbar run under a minimal PATH where `python3` resolves to the
# Xcode-shipped interpreter, which has NO PyYAML -- so active.yaml /
# tasks.yaml went unread and the lanes table silently emptied (same
# works-in-a-terminal-dead-in-the-menu-bar class as the bash-3.2 bug). Both
# documents are MACHINE-WRITTEN by leadv2's own renderers, never hand-edited,
# so a tiny indent-based reader covering the leadv2 subset is sufficient.
# PyYAML stays preferred when importable (terminal path byte-identical).
# Anything outside the subset RAISES so the caller renders a LOUD warning
# instead of a calm wrong-zero. NOTE: a copy of (_mini_yaml,_load_yaml) is
# duplicated verbatim in the render_questions() heredoc (a *separate*
# `python3 <<PYEOF`); sharing a sourced .py would add a runtime artifact to
# this 150 ms read path. See the comment there.
def _mini_yaml(text):
    """Parse the leadv2 machine-written YAML subset -> dict.
    Supports: space indent, 'key: scalar', 'key:' + block child, '- ' list
    items with an inline first key, single/double-quoted scalars (incl.
    multi-line), '[]'/'{}' empty collections, null/bool/int/float scalars.
    Full-line '#' comments are skipped (trailing inline comments are NOT
    stripped -- leadv2 emits none and stripping would risk eating '#' inside
    values). Raises ValueError on anything it cannot handle -- never partial."""
    def _unclosed(v):
        # If v opens a quoted scalar it does not close on this line, return the
        # quote char; else None.
        j, L = 0, len(v)
        while j < L:
            c = v[j]
            if c == "'":
                k = j + 1
                while k < L:
                    if v[k] == "'":
                        if k + 1 < L and v[k + 1] == "'":
                            k += 2; continue
                        return None
                    k += 1
                return "'"
            if c == '"':
                k = j + 1
                while k < L:
                    if v[k] == "\\":
                        k += 2; continue
                    if v[k] == '"':
                        return None
                    k += 1
                return '"'
            j += 1
        return None

    def _vsub(body):
        # value portion of a logical line (after the first 'key:' or '- ').
        if body.startswith("- "):
            inner = body[2:]
            return inner.split(":", 1)[1] if ":" in inner else inner
        return body.split(":", 1)[1] if ":" in body else body

    # Build logical lines, merging multi-line quoted scalars into one line.
    raw = text.replace("\r\n", "\n").split("\n")
    lines = []
    i, n = 0, len(raw)
    while i < n:
        line = raw[i]
        m = 0
        while m < len(line) and line[m] == " ":
            m += 1
        if m < len(line) and line[m] == "\t":
            raise ValueError("tab indentation unsupported")
        body = line[m:]
        if body == "" or body.startswith("#"):
            i += 1; continue
        q = _unclosed(_vsub(body))
        if q is None:
            lines.append((m, body)); i += 1; continue
        parts = [body]; i += 1; closed = False
        while i < n:
            parts.append(raw[i].lstrip(" "))
            if _unclosed(_vsub(" ".join(parts))) is None:
                closed = True; i += 1; break
            i += 1
        if not closed:
            raise ValueError("unterminated quoted scalar")
        lines.append((m, " ".join(parts)))

    def _scalar(v):
        v = v.strip()
        if v == "":
            return None
        if v[:1] in ("[", "{"):
            # Reached only if a caller forgot to route through _flow_parse first
            # (every real call site below does). Fail loud rather than garbage.
            raise ValueError("inline flow collection unsupported")
        if len(v) >= 2 and v[0] == v[-1] and v[0] in ("'", '"'):
            if v[0] == "'":
                return v[1:-1].replace("''", "'")
            s, out, k, L = v[1:-1], [], 0, len(v) - 2
            while k < L:
                c = s[k]
                if c == "\\" and k + 1 < L:
                    n = s[k + 1]
                    if n == "n": out.append("\n"); k += 2
                    elif n == "t": out.append("\t"); k += 2
                    elif n == '"': out.append('"'); k += 2
                    elif n == "'": out.append("'"); k += 2
                    elif n == "\\": out.append("\\"); k += 2
                    elif n == " ": k += 2  # folded line continuation (merge artifact)
                    elif n == "u" and k + 6 <= L:
                        try: out.append(chr(int(s[k + 2:k + 6], 16))); k += 6
                        except ValueError: out.append(c); k += 1
                    elif n == "x" and k + 4 <= L:
                        try: out.append(chr(int(s[k + 2:k + 4], 16))); k += 4
                        except ValueError: out.append(c); k += 1
                    else: out.append(c); k += 1
                else:
                    out.append(c); k += 1
            return "".join(out)
        low = v.lower()
        if low in ("null", "~", ""):
            return None
        if low == "true":
            return True
        if low == "false":
            return False
        try:
            return int(v)
        except Exception:
            pass
        try:
            return float(v)
        except Exception:
            pass
        return v

    # ---- SWIFTBAR-R4 RC-3: flow-style collections ------------------------
    # `key: [a, b]`, `key: [{k: v}, {k: v}]`, and `- {k: v, k2: v}` (a block
    # sequence item written as a flow mapping). Without this, an operator's
    # question `options:` written as a flow sequence of flow mappings -- the
    # only shape the real writer emits -- silently vanished (dropped to ""),
    # under-reporting the pending-question count as 0 instead of raising.
    def _flow_ws(s, pos):
        while pos < len(s) and s[pos] in " \t":
            pos += 1
        return pos

    def _flow_quoted(s, pos):
        q = s[pos]; pos += 1
        out = []
        if q == "'":
            while pos < len(s):
                if s[pos] == "'":
                    if pos + 1 < len(s) and s[pos + 1] == "'":
                        out.append("'"); pos += 2; continue
                    return "".join(out), pos + 1
                out.append(s[pos]); pos += 1
            raise ValueError("unterminated quoted scalar in flow value")
        while pos < len(s):
            c = s[pos]
            if c == "\\" and pos + 1 < len(s):
                nx = s[pos + 1]
                if nx == "n": out.append("\n")
                elif nx == "t": out.append("\t")
                elif nx == '"': out.append('"')
                elif nx == "'": out.append("'")
                elif nx == "\\": out.append("\\")
                else: out.append(nx)
                pos += 2; continue
            if c == '"':
                return "".join(out), pos + 1
            out.append(c); pos += 1
        raise ValueError("unterminated quoted scalar in flow value")

    def _flow_bare(s, pos, stop):
        start = pos
        while pos < len(s) and s[pos] not in stop:
            pos += 1
        return s[start:pos].strip(), pos

    def _flow_value(s, pos):
        pos = _flow_ws(s, pos)
        if pos >= len(s):
            raise ValueError("unexpected end of flow value")
        c = s[pos]
        if c == "[":
            return _flow_seq(s, pos)
        if c == "{":
            return _flow_map(s, pos)
        if c in ("'", '"'):
            raw, pos = _flow_quoted(s, pos)
            return raw, pos
        raw, pos = _flow_bare(s, pos, ",]}\n")
        if raw == "":
            raise ValueError("empty scalar in flow value")
        return _scalar(raw), pos

    def _flow_seq(s, pos):
        pos += 1  # consume '['
        arr = []
        pos = _flow_ws(s, pos)
        if pos < len(s) and s[pos] == "]":
            return arr, pos + 1
        while True:
            val, pos = _flow_value(s, pos)
            arr.append(val)
            pos = _flow_ws(s, pos)
            if pos >= len(s):
                raise ValueError("unterminated flow sequence")
            if s[pos] == ",":
                pos = _flow_ws(s, pos + 1); continue
            if s[pos] == "]":
                return arr, pos + 1
            raise ValueError("expected ',' or ']' in flow sequence")

    def _flow_map(s, pos):
        pos += 1  # consume '{'
        d = {}
        pos = _flow_ws(s, pos)
        if pos < len(s) and s[pos] == "}":
            return d, pos + 1
        while True:
            pos = _flow_ws(s, pos)
            if pos < len(s) and s[pos] in ("'", '"'):
                key, pos = _flow_quoted(s, pos)
            else:
                key, pos = _flow_bare(s, pos, ":,{}[]'\"")
            if key == "":
                raise ValueError("empty key in flow mapping")
            pos = _flow_ws(s, pos)
            if pos >= len(s) or s[pos] != ":":
                raise ValueError("expected ':' in flow mapping")
            val, pos = _flow_value(s, pos + 1)
            d[key] = val
            pos = _flow_ws(s, pos)
            if pos >= len(s):
                raise ValueError("unterminated flow mapping")
            if s[pos] == ",":
                pos = _flow_ws(s, pos + 1); continue
            if s[pos] == "}":
                return d, pos + 1
            raise ValueError("expected ',' or '}' in flow mapping")

    def _flow_parse(v):
        val, pos = _flow_value(v, 0)
        if v[pos:].strip() != "":
            raise ValueError("trailing content after flow value")
        return val

    def _map(lines, pos, indent):
        d = {}
        while pos < len(lines):
            ind, body = lines[pos]
            if ind < indent:
                break
            if ind > indent:
                raise ValueError("unexpected indent in mapping")
            if body == "-" or body.startswith("- "):
                raise ValueError("sequence item where mapping key expected")
            key, sep, val = body.partition(":")
            if sep != ":":
                raise ValueError("expected 'key:'")
            key = key.strip()
            if key == "":
                raise ValueError("empty key")
            val = val.strip()
            pos += 1
            if val == "":
                nind, nbody = (lines[pos] if pos < len(lines) else (None, None))
                if nind is not None and (nind > indent or
                        (nind == indent and (nbody == "-" or nbody.startswith("- ")))):
                    child, pos = _node(lines, pos)
                    d[key] = child
                else:
                    d[key] = None
            elif val[:1] in ("[", "{"):
                d[key] = _flow_parse(val)
            elif val[:1] in ("|", ">"):
                # block scalar (| literal / > folded, optional -/+ chomp).
                # Consume every deeper-indented logical line as content so the
                # parser never chokes on a machine-written block field. Exact
                # value is unused by the renderers (they read scalar keys), so
                # best-effort folding is fine; the contract is: consume the
                # span, never raise.
                buf = []
                while pos < len(lines) and lines[pos][0] > indent:
                    buf.append(lines[pos][1]); pos += 1
                d[key] = " ".join(buf) if val[:1] == ">" else "\n".join(buf)
            elif val.startswith("- "):
                raise ValueError("inline sequence unsupported")
            else:
                # plain (or single-line quoted) scalar. A PLAIN scalar may fold
                # across following more-indented lines (YAML plain-scalar
                # continuation); quoted multi-line is already one logical line.
                v = val
                if not (len(val) >= 2 and val[0] == val[-1] and val[0] in ("'", '"')):
                    while pos < len(lines) and lines[pos][0] > indent:
                        v = v + " " + lines[pos][1]; pos += 1
                d[key] = _scalar(v)
        return d, pos

    def _seq(lines, pos, indent):
        arr = []
        while pos < len(lines):
            ind, body = lines[pos]
            if ind < indent:
                break
            if ind > indent:
                raise ValueError("unexpected indent in sequence")
            if body == "-":
                pos += 1
                nind = lines[pos][0] if pos < len(lines) else None
                if nind is not None and nind > indent:
                    child, pos = _node(lines, pos); arr.append(child)
                else:
                    arr.append(None)
                continue
            if not body.startswith("- "):
                break
            pos += 1
            rest = body[2:].strip()
            if rest == "":
                nind = lines[pos][0] if pos < len(lines) else None
                if nind is not None and nind > indent:
                    child, pos = _node(lines, pos); arr.append(child)
                else:
                    arr.append(None)
                continue
            if rest[:1] in ("[", "{"):
                arr.append(_flow_parse(rest))
            elif ":" in rest:
                # inline first key of a mapping item; its siblings live at +2.
                vindent = indent + 2
                sub = [(vindent, rest)] + lines[pos:]
                item, csub = _map(sub, 0, vindent)
                arr.append(item)
                pos += csub - 1  # minus the one synthesized line
            else:
                arr.append(_scalar(rest))
        return arr, pos

    def _node(lines, pos):
        if pos >= len(lines):
            return None, pos
        ind, body = lines[pos]
        if body == "-" or body.startswith("- "):
            return _seq(lines, pos, ind)
        return _map(lines, pos, ind)

    doc, _ = _node(lines, 0)
    if not isinstance(doc, dict):
        raise ValueError("top-level document is not a mapping")
    return doc

def _load_yaml(path):
    """PyYAML when importable, else _mini_yaml. Returns {} only for a genuinely
    empty file. Raises on any read/parse error (caller decides the warning)."""
    try:
        import yaml
    except ImportError:
        with open(path, "r", encoding="utf-8") as fh:
            txt = fh.read()
        if txt.strip() == "":
            return {}
        return _mini_yaml(txt)
    with open(path, "r", encoding="utf-8") as fh:
        return yaml.safe_load(fh) or {}

# ---- helpers -----------------------------------------------------------
def iso_to_epoch(s):
    if not s:
        return None
    try:
        if isinstance(s, (int, float)):
            return int(s)
        t = str(s).strip()
        if t.endswith("Z"):
            t = t[:-1] + "+00:00"
        from datetime import datetime
        return int(datetime.fromisoformat(t).timestamp())
    except Exception:
        return None

def age_label(secs):
    if secs is None or secs < 0:
        secs = 0
    if secs < 60:
        return "%ds" % int(secs)
    if secs < 5400:
        return "%dm" % (int(secs) // 60)
    return "%dh" % (int(secs) // 3600)

def flat_yaml(path):
    # meta.yaml is flat key:value; parse without the yaml dep for speed/robustness.
    d = {}
    try:
        with open(path, "r") as fh:
            for line in fh:
                line = line.rstrip("\n")
                if not line or line.lstrip().startswith("#") or ":" not in line:
                    continue
                k, _, v = line.partition(":")
                d[k.strip()] = v.strip().strip("'\"")
    except Exception:
        pass
    return d

def journal_mtime(handle, arm):
    if not handle or not arm or not RUNS_ROOT:
        return None
    p = os.path.join(RUNS_ROOT, "%s-runs" % arm, handle, "journal.jsonl")
    try:
        return int(os.path.getmtime(p))
    except Exception:
        return None

def close_dir_mtime(sig8):
    # N-7d signal 5: newest mtime across a lane's docs/handoff/dispatch-<sig8>/
    # directory (the directory itself plus every entry one level down -- the
    # close gate writes e2e-gate.log/deliverable.md/review-verdict.md at that
    # top level, so one hand-picked filename would miss the general case).
    # Deliberately NOT recursive and deliberately NOT prefix-matching sibling
    # dirs (dispatch-<sig8>-architect, -review): those are a different phase
    # and would let one subsession vouch for a lane whose own gate is dead.
    # Never raises -- a permission error here must not break the render.
    if not HANDOFF_DIR or not sig8:
        return None
    d = os.path.join(HANDOFF_DIR, "dispatch-%s" % sig8)
    try:
        if not os.path.isdir(d):
            return None
        best = int(os.path.getmtime(d))
    except Exception:
        return None
    try:
        n = 0
        with os.scandir(d) as it:
            for entry in it:
                n += 1
                if n > CLOSE_SCAN_MAX:
                    break
                try:
                    m = int(entry.stat(follow_symlinks=False).st_mtime)
                    if m > best:
                        best = m
                except Exception:
                    continue
    except Exception:
        pass
    return best

def provider_meta(handle, arm):
    # returns (status, exit_code, model, j_mtime)
    if not handle or not arm or not RUNS_ROOT:
        return (None, None, None, None)
    p = os.path.join(RUNS_ROOT, "%s-runs" % arm, handle, "meta.yaml")
    m = flat_yaml(p)
    status = m.get("status")
    ec = m.get("exit_code")
    model = m.get("model")
    j = journal_mtime(handle, arm)
    return (status, ec, model, j)

def lane_outcome(handle, arm):
    # SWIFTBAR-LIVE-01 round 4 (§Fix 2): .outcome is written by
    # leadv2-lane-outcome.sh (called only from glm-coder.sh / kimi-coder.sh) into
    # the run dir beside meta.yaml. The file is a SMALL key=value block, NOT a
    # bare token:
    #     outcome=<completed|died-with-work|died-clean>
    #     bound=...
    #     work=...
    #     next=...
    #     at=<iso8601>
    # (codex review P1-a: an earlier draft compared the WHOLE file to a bare
    # token and so rejected every real file -> the override was unreachable in
    # production. Parse the `outcome=` line instead.) Whitelist the three tokens;
    # anything else (absent file, junk, unreadable, unknown value) -> "" unknown.
    if not handle or not arm or not RUNS_ROOT:
        return ""
    p = os.path.join(RUNS_ROOT, "%s-runs" % arm, handle, ".outcome")
    try:
        with open(p, "r") as f:
            text = f.read()
    except Exception:
        return ""
    val = ""
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("outcome="):
            val = line[len("outcome="):].strip()
            break
    if val in ("completed", "died-with-work", "died-clean"):
        return val
    return ""

def lstart(pid):
    try:
        out = subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)],
                             capture_output=True, text=True)
        return " ".join(out.stdout.split())
    except Exception:
        return ""

def pid_alive(pid, birth):
    if pid in (None, "", 0):
        return False
    try:
        pid = int(pid)
    except Exception:
        return False
    if pid <= 0:
        return False
    # R3: pair pid with pid_birth; a recycled pid renders a dead lane as live.
    if birth:
        if lstart(pid) != str(birth).strip():
            return False
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True  # R4: EPERM -> alive
    except OSError:
        return False

# SWIFTBAR-LIVE-01 round 2 (§2.1, signal 3): true iff some live process' argv
# contains "task-id dispatch-<sig8>" -- a plain substring scan over the ONE
# ps snapshot the bash layer captured before this python block started (no
# subprocess call from here). Survives a worker whose handle was never
# recorded on the ledger row, which is exactly the "0 live" reproduction.
def sig_process_alive(sig8):
    if not sig8 or not PS_SNAPSHOT:
        return False
    needle = "task-id dispatch-" + sig8
    for line in PS_SNAPSHOT.split("\n"):
        if needle in line:
            return True
    return False

# N-7c: identity, not existence. The process behind `handle` must be THIS lane's
# worker -- same needle as sig_process_alive() so the two signals can never
# disagree. A bare pid is not identity: pids are recycled, and a foreign-uid pid
# (EPERM->alive in pid_alive) is exactly how a dead fleet renders green.
def pid_argv_matches_sig(pid, sig8):
    if not pid or not sig8 or not PS_SNAPSHOT:
        return False
    try:
        spid = str(int(pid))
    except Exception:
        return False
    needle = "task-id dispatch-" + sig8
    for line in PS_SNAPSHOT.split("\n"):
        parts = line.strip().split(None, 1)   # "<pid> <argv...>"
        if len(parts) == 2 and parts[0] == spid:
            return needle in parts[1]
    return False

# N-7d signal 6: identity, not existence, for the CLOSE phase (act two) --
# same standard N-7c set for the worker. A line proves THIS lane's close
# process iff all three hold on its argv tokens:
#   1. some token's basename is leadv2-dispatch-product-close.sh
#   2. sig8 is present as an exact token (not a substring -- a different sig
#      that happens to contain these 8 chars inside a path must not match)
#   3. PROJECT_ROOT is present as a substring of the raw argv (substring, not
#      token, on purpose: a worktree path nests under the root). If the
#      derived root is empty, this clause is skipped -- (1)+(2) alone are
#      already lane-unique, so we degrade to sig-identity, never to false-dead.
# Returns (alive, pid) so the cause text can name the pid.
def close_process_alive(sig8):
    if not sig8 or not PS_SNAPSHOT:
        return (False, "")
    root = ""
    if HANDOFF_DIR:
        root = os.path.dirname(os.path.dirname(HANDOFF_DIR))
    for line in PS_SNAPSHOT.split("\n"):
        parts = line.strip().split(None, 1)
        if len(parts) != 2:
            continue
        pid, argv = parts[0], parts[1]
        tokens = argv.split()
        if not any(os.path.basename(t) == "leadv2-dispatch-product-close.sh" for t in tokens):
            continue
        if sig8 not in tokens:
            continue
        if root and root not in argv:
            continue
        return (True, pid)
    return (False, "")

def is_terminal(status, ledger_state):
    # ledger vocabulary is written ONLY by leadv2-dispatch-code.sh:860 ("pending")
    # and :913 ("pending"->"confirmed"). SWIFTBAR-LIVE-01 round 2: "confirmed" is
    # INTENT -- the row was journalled the instant it was written, nothing mutates
    # it again -- NOT fact that the worker finished. A confirmed row's liveness/
    # completion is decided by process evidence (pid_alive / sig_process_alive /
    # meta.yaml exit code) in add_row below, never by the ledger state alone.
    # "pending" is NON-terminal on purpose: a stale pending == crashed dispatch, keep visible.
    # closed/failed/cancelled: no writer attested in-tree; kept as forward-compat only.
    # SWIFTBAR-LIVE-01 round 4 (§Fix 3, R3.2): the terminal ledger's
    # write-terminal rows carry `terminal` in {landed|parked|refused|dead}; the
    # ingest now maps that into `state` (a terminal row has no real `state`),
    # so is_terminal() must accept these tokens or a terminal-only row stops
    # counting as terminal. parked/refused are retryable in the WRITER's mind
    # but on the READER's side a row that reached write-terminal is done
    # dispatching for this attempt -- it is terminal for display/TTL purposes.
    return status in ("complete", "failed", "cancelled") or \
           ledger_state in ("closed", "failed", "cancelled",
                            "landed", "parked", "refused", "dead")

# ---- R1 (fix round 3): tasks.yaml title map -- ONE parse ----------------
# Source for rule 1 of name resolution. tasks.yaml is mapping-shaped
# {total_open, tasks:[...]} (NOT a top-level list). The human-readable name is
# `title` (forward-compat) or, against today's real data, `external_id` /
# `node_id` (the ALERTS-TO-LEAD-01 shape the founder asked for -- node_id carries
# a `leadv2:` prefix we strip). Index by id, external_id AND node_id so a lookup
# by whichever key the dispatch recorded still hits. A malformed/unreadable
# tasks.yaml degrades to an empty map -- never breaks the render.
titles = {}  # any-of{id, external_id, node_id} -> display name
if TASKS_YAML and os.path.exists(TASKS_YAML):
    try:
        _doc = _load_yaml(TASKS_YAML)
        for _t in (_doc.get("tasks") or []):
            _tid = str(_t.get("id") or "")
            _name = str(_t.get("title") or _t.get("external_id") or "")
            if not _name:
                _nid = str(_t.get("node_id") or "")
                _name = _nid[len("leadv2:"):] if _nid.startswith("leadv2:") else _nid
            _name = _name.strip()
            if _tid and _name:
                titles[_tid] = _name
                _eid = str(_t.get("external_id") or "")
                if _eid:
                    titles.setdefault(_eid, _name)
                _nid = str(_t.get("node_id") or "")
                if _nid:
                    titles.setdefault(_nid, _name)
    except Exception:
        pass

def _clip40(s):
    # first 40 chars; if a ':' occurs within those 40, cut at the FIRST colon
    # (handles "CODE: subtitle" titles). external_id/node_id values have no
    # colon after prefix-stripping, so this is a no-op there.
    s = (s or "").strip()
    head = s[:40]
    i = head.find(":")
    if i >= 0:
        head = head[:i]
    return head.strip()[:40]

def resolve_name(task_id, mission_path, sig8):
    # Rule 1: tasks.yaml name by id/external_id/node_id.
    if task_id:
        _nm = titles.get(str(task_id))
        if _nm:
            return _clip40(_nm)
    # Rule 1b (SWIFTBAR-LIVE-01 round 2, §2.4): task_id recorded but no
    # tasks.yaml title match -- render the id itself. The writer fix
    # (leadv2-dispatch-code.sh dispatch_reserve) now persists the founder's
    # --task-id onto every new ledger row, so this is the common case for a
    # task not yet (or never) tracked in tasks.yaml. Still a name, never a
    # hash.
    if task_id:
        return _clip40(str(task_id))
    # Rules 2/2.5 (mission-file first line / handoff-dir mission title) are
    # DELETED, not patched (SWIFTBAR-LIVE-01 round 2, §2.4): prose is never a
    # name -- scraping it produced exactly the defect this round fixes
    # ("You are implementing task dispatch-14b3b worker confirmed" rendered
    # as a lane's name). `mission_path` stays in the signature/ledger (other
    # consumers still use it) but is no longer read here.
    # Rule 2 (was 3): a hash is not a name either. Return the literal
    # 'unnamed'; the sig8 lives in its own SIG column so it stays greppable.
    return "unnamed"

# ---- S1: active.yaml ---------------------------------------------------
sessions = []
warn_msg = None
try:
    doc = _load_yaml(os.path.join(STATE_DIR, "active.yaml"))
    sessions = doc.get("sessions") or []
    if not isinstance(sessions, list):
        sessions = []
except Exception:
    warn_msg = "active.yaml unreadable"

# ---- S4: dispatch ledger, tail -n 400, last row per task_sig wins -------
# R5: the ledger grows unbounded; tail -n 400 is a documented coverage cap
# (no silent caps). Most-recent row per sig8 wins.
ledger = {}  # sig8 -> {arm, handle, state, created_epoch}
if LEDGER_FILE and os.path.exists(LEDGER_FILE):
    try:
        with open(LEDGER_FILE, "r") as fh:
            lines = fh.readlines()[-400:]
        for line in lines:
            line = line.strip()
            if not line:
                continue
            # minimal JSON field extraction (avoid importing json per-row cost
            # is negligible, but stay dependency-light)
            import json
            try:
                row = json.loads(line)
            except Exception:
                continue
            sig = row.get("task_sig") or ""
            if len(sig) < 8:
                continue
            sig8 = sig[:8]
            # SWIFTBAR-LIVE-01 round 4 (§Fix 3): KEY-WISE MERGE, not wholesale
            # assignment. There are TWO writers into this ledger with
            # incompatible schemas: dispatch-code.sh's reserve row carries
            # {task_sig,arm,handle,state,created_epoch,task_id,mission_path};
            # dispatch-ledger.sh's write-terminal row carries
            # {task_sig,founder_task_id,terminal,cause,...} and NO arm/handle/
            # state/created_epoch/task_id. Wholesale `ledger[sig8] = {...}`
            # let the terminal row REPLACE the reserve row for a real product
            # dispatch (product-close always writes a terminal row), blanking
            # task_id (-> "unnamed") AND arm/handle/state/created_epoch. A merge
            # that writes a field ONLY when the incoming value is non-empty keeps
            # the reserve row's fields and lets the terminal row contribute its
            # own (terminal-ness, terminal task_id). R3.1: no writer ever
            # intentionally blanks a field, so a surviving stale field is not a
            # real risk today.
            d = ledger.setdefault(sig8, {})
            for k, v in (
                ("arm", row.get("arm")),
                ("handle", row.get("handle")),
                ("state", row.get("state")),
                ("created_epoch", row.get("created_epoch")),
                ("mission_path", row.get("mission_path") or row.get("mission")),
                # R3: read the id from EITHER key -- reserve rows name it task_id,
                # terminal rows (round 4+) name it founder_task_id; either is the
                # lane name.
                ("task_id", row.get("task_id") or row.get("founder_task_id")),
            ):
                if v not in (None, ""):
                    d[k] = v
            # R3.2: a terminal row has no `state`, but its `terminal` field
            # (landed|parked|refused|dead) IS terminal-ness. Map it into state so
            # is_terminal() still fires for terminal-only rows. is_terminal()
            # (extended this round) accepts these tokens.
            if not row.get("state") and row.get("terminal"):
                d["state"] = row.get("terminal")
    except Exception:
        pass

# ---- build rows --------------------------------------------------------
rows = []        # each: dict(name, kind, display, model, age, cause, cls, max_mtime)
seen_sig8 = set()

def add_row(sig8, kind, phase, model, pid, birth, log_path, last_pulse_epoch,
            created_epoch, ledger_state, handle, arm, task_id, mission_path):
    # gather mtimes
    status, ec, pmodel, j_mtime = provider_meta(handle, arm)
    mtimes = []
    for m in (j_mtime,):
        if m:
            mtimes.append(m)
    lm = None
    if log_path:
        try:
            lm = int(os.path.getmtime(log_path))
            mtimes.append(lm)
        except Exception:
            pass
    if last_pulse_epoch:
        mtimes.append(int(last_pulse_epoch))
    if created_epoch:
        try:
            mtimes.append(int(created_epoch))
        except Exception:
            pass
    # NB: .outcome mtime is deliberately NOT folded into max_mtime. .outcome is a
    # POST-MORTEM signal (leadv2-lane-outcome.sh writes it at worker exit), not a
    # liveness signal; including its fresh mtime would push every finished lane
    # back into live(fresh) (NOW-mtime<120) and so defeat the outcome override.
    # Aging stays based on the lane's real activity (journal/created_epoch).
    max_mtime = max(mtimes) if mtimes else None

    # SWIFTBAR-LIVE-01 round 2 (§2.1): process truth, three signals in priority
    # order. Signal 1 (session pid) only fires for lane rows -- `pid` is always
    # None for ledger-only worker rows (see the add_row call below). Signal 2
    # is NEW: the ledger's `handle` field IS the worker's pid, so a worker row
    # with no session pid recorded can still prove itself alive. Signal 3 is
    # NEW: an argv match survives a handle that was never recorded at all --
    # this is the exact "0 live while a worker runs" reproduction. No pid_birth
    # is recorded alongside `handle` (out of scope this round, see Risks in
    # developer.full.md); a recycled pid over-reports live, which is strictly
    # safer than the current under-report.
    _pid_alive_session = pid_alive(pid, birth)
    # N-7c: signal 2 gains identity. A handle that is alive but whose argv is NOT
    # this lane's worker is trusted only while the row is still fresh (a
    # re-exec/wrapper that drops --task-id dispatch-<sig8>, with recent artifact
    # motion). Age is the SECOND signal: identity or freshness, never a bare pid.
    _handle_pid_alive = (not _pid_alive_session) and pid_alive(handle, None)
    _handle_identity  = _handle_pid_alive and pid_argv_matches_sig(handle, sig8)
    _handle_fresh     = (_handle_pid_alive and not _handle_identity
                         and max_mtime is not None
                         and (NOW - max_mtime) <= HANDLE_TRUST_S)
    _pid_alive_handle = _handle_identity or _handle_fresh
    _argv_alive = (not _pid_alive_session) and (not _pid_alive_handle) and sig_process_alive(sig8)
    _worker_alive = _pid_alive_session or _pid_alive_handle or _argv_alive

    # N-7d: a lane has two acts. Act two (the close/review gate) legitimately
    # freezes the worker's own signals for 20+ minutes, so a lane's silence
    # clock must also see motion inside its docs/handoff/dispatch-<sig8>/ dir,
    # and a live leadv2-dispatch-product-close.sh process must count as proof
    # of life. Per the design's core rule: a PROCESS makes a row live; an
    # ARTIFACT only moves the clock and names the act (never yields live by
    # itself) -- otherwise a stale handoff dir from a killed gate would relive
    # a genuinely dead lane (acceptance 2).
    _close_mtime = close_dir_mtime(sig8)
    _close_alive, _close_pid = close_process_alive(sig8)
    _close_fresh = (_close_mtime is not None
                    and (NOW - _close_mtime) <= CLOSE_FRESH_S)
    alive = _worker_alive or _close_alive
    # motion_mtime feeds the age column and the stale(...) branch ONLY; it
    # must NEVER feed the live(fresh) branch below (that still reads
    # max_mtime) or close-artifact freshness would smuggle its way to live
    # through the side door.
    _motion_candidates = [m for m in (max_mtime, _close_mtime) if m is not None]
    motion_mtime = max(_motion_candidates) if _motion_candidates else None

    # liveness rule (STANDING) — cause never empty, never "?"
    if _pid_alive_session:
        cause, cls = "live", "live"
    elif _pid_alive_handle:
        cause, cls = "live(pid %s)" % handle, "live"
    elif _argv_alive:
        cause, cls = "live(argv)", "live"
    elif _close_alive:
        cause, cls = "live(close pid %s)" % _close_pid, "live"
    elif max_mtime is not None and (NOW - max_mtime) < 120:
        cause, cls = "live(fresh)", "live"
    elif _close_fresh:
        cause = "gate(%s ago)" % age_label(NOW - _close_mtime)
        cls = "dead"
    elif ec not in (None, ""):
        try:
            eci = int(ec)
            if eci == 0:
                cause, cls = "done(exit=0)", "done"
            else:
                cause, cls = "dead(exit=%d)" % eci, "dead"
        except Exception:
            cause, cls = "dead(no-signal)", "dead"
    elif pid not in (None, "", 0):
        cause, cls = "dead(no-process)", "dead"
    elif motion_mtime is not None:
        cause = "stale(%s silent)" % age_label(NOW - motion_mtime)
        cls = "dead"
    else:
        cause, cls = "dead(no-signal)", "dead"

    # SWIFTBAR-LIVE-01 round 4 (§Fix 2): consume the run dir's .outcome so a
    # FINISHED lane is not indistinguishable from a FAILED one. .outcome is
    # written by leadv2-lane-outcome.sh as one of {completed, died-with-work,
    # died-clean}; lane_outcome() whitelists those and returns "" for
    # absent/junk. Apply ONLY to already-terminal rows (cls in dead|done): a
    # live process always wins, even if a stale .outcome sits in a reused run
    # dir (R2.2). cls stays three-valued (live|done|dead); a completed lane
    # becomes done(completed) (green, excluded from the red count) and a
    # died-clean lane becomes dead(died-clean) (red) -- distinguished by cause
    # text, not a new class. A terminal row with NO outcome keeps its
    # process-derived class and gains a "?" suffix on the cause so "unknown"
    # is visible, never silently mislabelled as died-clean.
    outcome = lane_outcome(handle, arm)
    if cls in ("dead", "done"):
        if outcome == "completed":
            cause, cls = "done(completed)", "done"
        elif outcome == "died-with-work":
            cause, cls = "dead(work-left)", "dead"
        elif outcome == "died-clean":
            cause, cls = "dead(died-clean)", "dead"
        elif "?" not in cause:
            cause = cause + "?"

    terminal = is_terminal(status, ledger_state)
    # terminal last-resort-stale reinterpretation: a ledger-only terminal row
    # (no pid, no exit code, only an old timestamp) lands on the stale("...")
    # branch purely for lack of any signal. Reinterpret that one branch as
    # done — but ONLY there: dead(exit=N)/dead(no-process)/dead(no-signal)
    # are real failure evidence and must stay dead. Sits after `terminal` is
    # computed and before the age-out so old-terminal still drops.
    if terminal and cls == "dead" and cause.startswith("stale("):
        cause = "done(%s)" % (ledger_state or status or "terminal")
        cls = "done"
    # age-out: terminal + silent > 7200s -> drop. Non-terminal never dropped
    # (a 9h silent lane stays visible as stale). Uses motion_mtime (§3.6): a
    # lane whose close gate is still writing must not age out on the same
    # clock the table's age/stale text now reads.
    if terminal:
        ref = motion_mtime if motion_mtime is not None else 0
        if ref and (NOW - ref) > 7200:
            return None

    # N-7d: PHASE/STATE names the act -- worker (worker signal alive), gate
    # (close signal alive or its artifacts are fresh), done (terminal, neither
    # of the above), else unknown. Folded into the existing single-field
    # `display` (no new TSV column -> no downstream awk $N shift).
    if _worker_alive:
        act = "worker"
    elif _close_alive or _close_fresh:
        act = "gate"
    elif cls in ("done", "dead"):
        act = "done"
    else:
        act = "-"

    # R2 (fix round 3): display by kind. A lane shows its phase; a worker shows
    # its ledger state. The old `phase or ledger_state` fallback conflated the
    # two -- exactly the "single lane or full 9-phase?" confusion. A lane with
    # no phase honestly renders "-".
    if kind == "lane":
        display = phase or "-"
    else:
        display = ledger_state or "-"
    if act != "-":
        display = act if display == "-" else "%s·%s" % (display, act)
    mdl = model or pmodel or arm or "-"
    # age column reads motion_mtime (§3.6): close-gate motion keeps the age
    # fresh even while the worker's own signals are frozen for act two.
    age = age_label(NOW - motion_mtime) if motion_mtime is not None else "-"
    return {
        "name": resolve_name(task_id, mission_path, sig8),
        "kind": kind,
        "display": display,
        "model": mdl,
        "age": age,
        "cause": cause,
        "cls": cls,
        "max_mtime": motion_mtime,
        "sig": sig8,
        "outcome": outcome,
        "alive": alive,
    }

for s in sessions:
    tid = str(s.get("task_id") or "")
    if not tid:
        continue
    sig8 = tid[:8]
    seen_sig8.add(sig8)
    le = ledger.get(sig8, {})
    handle = le.get("handle") or ""
    arm = le.get("arm") or ""
    ledger_state = le.get("state") or ""
    created_epoch = le.get("created_epoch")
    _tid = tid or le.get("task_id") or ""
    _mpath = le.get("mission_path") or ""
    log_path = s.get("log_path") or s.get("pulse_log") or ""
    r = add_row(sig8, "lane", s.get("phase"), s.get("lead_model"),
                s.get("pid"), s.get("pid_birth"), log_path,
                iso_to_epoch(s.get("last_pulse_at")) or iso_to_epoch(s.get("started_at")),
                created_epoch, ledger_state, handle, arm, _tid, _mpath)
    if r:
        rows.append(r)

# ledger-only rows: task_sig present in ledger, NOT in active.yaml, non-terminal
for sig8, le in ledger.items():
    if sig8 in seen_sig8:
        continue
    ledger_state = le.get("state") or ""
    handle = le.get("handle") or ""
    arm = le.get("arm") or ""
    if ledger_state in ("closed",):
        continue
    _tid = le.get("task_id") or ""
    _mpath = le.get("mission_path") or ""
    r = add_row(sig8, "worker", None, None, None, None, None, None,
                le.get("created_epoch"), ledger_state, handle, arm, _tid, _mpath)
    if r:
        rows.append(r)

if warn_msg and not rows:
    rows = [{
        "name": "warn", "kind": "-", "display": "active.yaml", "model": "-",
        "age": "-", "cause": warn_msg, "cls": "dead", "max_mtime": None, "sig": "",
        "alive": False,
    }]

# SWIFTBAR-LIVE-01 round 2 (§2.3): defensive invariant, belt and braces. A row
# whose `alive` signal fired must never be classified as anything but live,
# even if a future refactor of the cause/cls chain in add_row disagrees. This
# is the SAME class of bug that hid a running worker under "6 скрыто по
# возрасту" -- the invariant re-asserts it here, structurally, so it can never
# reoccur silently.
for _r in rows:
    if _r.get("alive") and _r["cls"] != "live":
        _r["cause"] = "live(invariant: %s)" % _r["cause"]
        _r["cls"] = "live"

# live_n is computed BEFORE the TTL drop: live rows are never dropped (R3),
# so pre-drop and post-drop are identical for it.
#
# dead_n is computed AFTER the TTL drop (N-7b): an all-time archive count is
# not an alarm count. A dead lane older than DEAD_TTL has already been removed
# from the table and counted into _aged, so the badge's red number must match
# what the table actually shows. DEAD_TTL (LEADV2_STATUS_DEAD_TTL_S, default
# 3600s) is the window -- the same window the drop loop applies to dead rows,
# and the same notion the header already uses for done ("done в последний час")
# and for the hidden-by-age line. Collapse only touches done rows (below), so
# pre/post-collapse is irrelevant for the dead count.
#
# SWIFTBAR-LIVE-01 round 3 (§2.4): "dead" and "done" are distinct classes;
# dead_n honors that distinction. Belt-and-braces (matching the invariant at
# the row-construction guard above): a completed outcome is never a red, even
# if a future refactor of the cause/cls chain re-conflated them.
live_n = sum(1 for r in rows if r["cls"] == "live")

# STATUS-SURFACE-R5-01 (defect 2, C2): TTL drop. A terminal row (done/dead)
# disappears after its window; live rows survive at ANY age (R3). Age basis =
# max_mtime when present, else the ledger created_epoch; a row with NEITHER is
# never dropped (unknown age != old). Runs AFTER live_n (live rows are never
# dropped, so pre/post is identical for it) and BEFORE dead_n (N-7b: dead_n is
# now post-drop, in-window) and BEFORE the collapse rule.
def _age_of(r):
    m = r.get("max_mtime")
    if m is not None:
        try:
            return int(m)
        except Exception:
            return None
    return None

_aged = 0
_kept = []
for r in rows:
    if r["cls"] == "live":
        _kept.append(r)
        continue
    _age = _age_of(r)
    if _age is None:
        # no mtime -> fall back to created_epoch is impossible here (not in the
        # row); a terminal row with no age signal is kept, not guessed away.
        _kept.append(r)
        continue
    _ttl = DONE_TTL if r["cls"] == "done" else DEAD_TTL
    if (NOW - _age) > _ttl:
        _aged += 1
        continue
    _kept.append(r)
rows = _kept
# N-7b: dead_n now lives AFTER the TTL drop (see comment above live_n) so the
# red number counts only dead rows still in-window (and never a completed lane).
dead_n = sum(1 for r in rows
             if r["cls"] == "dead" and r.get("outcome") != "completed")
# SWIFTBAR-LIVE-01 round 3 (§2.4): same conflation as dead_n above -- this
# counted "not live" (done AND dead) post-TTL-drop rows under the name
# DONE_RECENT, so a fleet with both dead and done rows reported the SAME
# number for #DEAD and #DONE_RECENT. Restrict to cls == "done" to match what
# the header text ("N done в последний час") and the variable name claim.
done_recent = sum(1 for r in rows if r["cls"] == "done")

# R3 (fix round 3): collapse terminal/done rows so a wall of 90 finished rows is
# structurally impossible. Keep the NEWEST 10 done rows, fold the rest into ONE
# summary line. Live rows and non-terminal stale/dead rows (real failure
# evidence) are NEVER collapsed.
_done_idx = [i for i, r in enumerate(rows) if r["cls"] == "done"]
if len(_done_idx) > 10:
    def _mk(r):
        m = r.get("max_mtime")
        try:
            return int(m) if m is not None else 0
        except Exception:
            return 0
    _kept2 = set(sorted(_done_idx, key=lambda i: _mk(rows[i]), reverse=True)[:10])
    _dropped = len(_done_idx) - 10
    _new = []
    for i, r in enumerate(rows):
        if r["cls"] == "done" and i not in _kept2:
            continue
        _new.append(r)
    _new.append({
        "name": "+ %d done earlier today" % _dropped,
        "kind": "-", "display": "-", "model": "-", "age": "-",
        "cause": "collapsed", "cls": "done", "max_mtime": None, "sig": "",
    })
    rows = _new

out = ["#LIVE %d" % live_n, "#DEAD %d" % dead_n,
       "#DONE_RECENT %d" % done_recent, "#AGED_OUT %d" % _aged]
# R5-01 round 2: when active.yaml could not be read, flag it for the bash
# layer so the header stops rendering a calm "0 live" and the menu-bar title
# carries ⚠. Machine-readable: '#WARN <human message>'.
if warn_msg:
    out.append("#WARN " + warn_msg)
for r in rows:
    # TSV order: name kind display model age cause cls sig -- cls stays field-7
    # (.10s.sh counts live rows via the rendered STATE column, and the statusline
    # oneline live-detection depends on `live` appearing in cause). sig is
    # appended AFTER cls (STATUS-SURFACE-R5-01, C1d) so the old field offsets are
    # unchanged.
    out.append("\t".join([
        str(r["name"]), str(r["kind"]), str(r["display"]),
        str(r["model"]), str(r["age"]), str(r["cause"]), str(r["cls"]),
        str(r.get("sig", "")),
        # SWIFTBAR-LIVE-01 round 4 (§Fix 2): outcome appended after sig (field
        # 9, field 10 in multi-project after the PROJ prepend) so no existing
        # field offset shifts -- every TSV-consuming awk reads $<=9.
        str(r.get("outcome", "")),
    ]))
sys.stdout.write("\n".join(out) + "\n")
PYEOF
}

LANES=""
LIVE_N=0
DEAD_N=0
DONE_RECENT_N=0
AGED_OUT_N=0
WARN_MSG=""
LANE_ROWS=""
LANE_COUNT=0

_run_lanes_for_project() {
  # args: state_dir ledger_file tasks_yaml handoff_dir  -> prints raw LANES
  # (control lines + TSV rows) for that one project, via the shared
  # _ss_lanes_py block. Zero side effects on any global.
  LEADV2_SS_STATE_DIR="$1" \
  LEADV2_SS_LEDGER_FILE="$2" \
  LEADV2_SS_RUNS_ROOT="$RUNS_ROOT" \
  LEADV2_SS_NOW="$NOW" \
  LEADV2_SS_TASKS_YAML="$3" \
  LEADV2_SS_HANDOFF_DIR="$4" \
  LEADV2_SS_DONE_TTL="$DONE_TTL" \
  LEADV2_SS_DEAD_TTL="$DEAD_TTL" \
  LEADV2_SS_HANDLE_TRUST_S="$HANDLE_TRUST_S" \
  LEADV2_SS_CLOSE_FRESH_S="$CLOSE_FRESH_S" \
  LEADV2_SS_CLOSE_SCAN_MAX="$CLOSE_SCAN_MAX" \
  LEADV2_SS_PS_SNAPSHOT="$PS_SNAPSHOT" \
  _ss_lanes_py
}

if ! command -v python3 >/dev/null 2>&1; then
  LANES="$(printf 'warn\tactive.yaml\tpython3\t-\tpython3 missing - active.yaml not parsed\tdead\n')"
  DEAD_N=1
  LANE_ROWS="$LANES"
  LANE_COUNT=1
elif [ "$MULTI_PROJECT" -eq 1 ]; then
  # ── Multi-project aggregation (SWIFTBAR-LIVE-01) ──────────────────────────
  _mp_idx=0
  while [ "$_mp_idx" -lt "${#PROJ_SLUGS[@]}" ]; do
    _mp_slug="${PROJ_SLUGS[$_mp_idx]}"
    _mp_sd="${PROJ_STATE_DIRS[$_mp_idx]}"
    _mp_root="${PROJ_REPO_ROOTS[$_mp_idx]}"
    _mp_ledger="${LEDGER_DIR}/${_mp_slug}.jsonl"
    _mp_tasks=""
    [ -f "${_mp_root}/docs/tasks.yaml" ] && _mp_tasks="${_mp_root}/docs/tasks.yaml"
    _mp_handoff=""
    [ -d "${_mp_root}/docs/handoff" ] && _mp_handoff="${_mp_root}/docs/handoff"
    _mp_lanes="$(_run_lanes_for_project "$_mp_sd" "$_mp_ledger" "$_mp_tasks" "$_mp_handoff")"

    _mp_live="$(printf '%s\n' "$_mp_lanes" | sed -n 's/^#LIVE //p' | head -1)"
    _mp_dead="$(printf '%s\n' "$_mp_lanes" | sed -n 's/^#DEAD //p' | head -1)"
    _mp_done="$(printf '%s\n' "$_mp_lanes" | sed -n 's/^#DONE_RECENT //p' | head -1)"
    _mp_aged="$(printf '%s\n' "$_mp_lanes" | sed -n 's/^#AGED_OUT //p' | head -1)"
    _mp_warn="$(printf '%s\n' "$_mp_lanes" | sed -n 's/^#WARN //p' | head -1)"
    case "$_mp_live" in ''|*[!0-9]*) _mp_live=0 ;; esac
    case "$_mp_dead" in ''|*[!0-9]*) _mp_dead=0 ;; esac
    case "$_mp_done" in ''|*[!0-9]*) _mp_done=0 ;; esac
    case "$_mp_aged" in ''|*[!0-9]*) _mp_aged=0 ;; esac

    if [ -n "$_mp_warn" ]; then
      # STATUS-SURFACE R10 (SWIFTBAR-LIVE-01): a per-project WARN degrades
      # only THIS project's rows -- one synthetic dead row, table continues.
      _mp_rows="$(printf 'warn\t-\t%s\t-\t-\twarn\tdead\t\n' "$_mp_warn")"
      _mp_dead=$(( _mp_dead + 1 ))
    else
      _mp_rows="$(printf '%s\n' "$_mp_lanes" | grep -v '^#' || true)"
    fi
    if [ -n "$_mp_rows" ]; then
      LANE_ROWS="${LANE_ROWS}$(printf '%s\n' "$_mp_rows" | sed "s/^/${_mp_slug}\t/")
"
    fi
    LIVE_N=$(( LIVE_N + _mp_live ))
    DEAD_N=$(( DEAD_N + _mp_dead ))
    DONE_RECENT_N=$(( DONE_RECENT_N + _mp_done ))
    AGED_OUT_N=$(( AGED_OUT_N + _mp_aged ))
    _mp_idx=$(( _mp_idx + 1 ))
  done
  unset _mp_idx _mp_slug _mp_sd _mp_root _mp_ledger _mp_tasks _mp_handoff _mp_lanes \
        _mp_live _mp_dead _mp_done _mp_aged _mp_warn _mp_rows
  LANE_ROWS="$(printf '%s\n' "$LANE_ROWS" | grep -v '^ *$' || true)"
  LANE_COUNT=0
  if [ -n "$LANE_ROWS" ]; then
    LANE_COUNT="$(printf '%s\n' "$LANE_ROWS" | grep -c . || true)"
  fi
else
  LANES="$(_run_lanes_for_project "$STATE_DIR" "$LEDGER_FILE" "$TASKS_YAML" "$HANDOFF_DIR")"

  # parse the control lines + rows out of LANES
  if [ -n "$LANES" ]; then
    LIVE_N="$(printf '%s\n' "$LANES" | sed -n 's/^#LIVE //p' | head -1)"
    DEAD_N="$(printf '%s\n' "$LANES" | sed -n 's/^#DEAD //p' | head -1)"
    DONE_RECENT_N="$(printf '%s\n' "$LANES" | sed -n 's/^#DONE_RECENT //p' | head -1)"
    AGED_OUT_N="$(printf '%s\n' "$LANES" | sed -n 's/^#AGED_OUT //p' | head -1)"
    WARN_MSG="$(printf '%s\n' "$LANES" | sed -n 's/^#WARN //p' | head -1)"
    case "$LIVE_N" in ''|*[!0-9]*) LIVE_N=0 ;; esac
    case "$DEAD_N" in ''|*[!0-9]*) DEAD_N=0 ;; esac
    case "$DONE_RECENT_N" in ''|*[!0-9]*) DONE_RECENT_N=0 ;; esac
    case "$AGED_OUT_N" in ''|*[!0-9]*) AGED_OUT_N=0 ;; esac
  fi
  # drop every control line (#…) so only TSV rows remain
  LANE_ROWS="$(printf '%s\n' "$LANES" | grep -v '^#' || true)"
  LANE_COUNT=0
  if [ -n "$LANE_ROWS" ]; then
    LANE_COUNT="$(printf '%s\n' "$LANE_ROWS" | grep -c . || true)"
  fi
fi

# ── Render ─────────────────────────────────────────────────────────────────
# emit_oneline / emit_lanes_table are factored out so --all can compose the
# lanes table with the round-4 sections. Their output is byte-identical to the
# pre-round-4 renderer (the regression contract: bare invocation must not drift).
emit_oneline() {
  local head lane_str
  case "$SUP_STATE" in
    on)     head="sup:ON(${SUP_SHORT})" ;;
    stale)  head="sup:STALE(${SUP_SHORT})" ;;
    *)      head="sup:OFF(${SUP_SHORT})" ;;
  esac
  lane_str=""
  if [ "$LANE_COUNT" -gt 0 ] && [ "$MULTI_PROJECT" -eq 1 ]; then
    lane_str="$(printf '%s\n' "$LANE_ROWS" | awk -F '\t' '
      { printf "%s%s/%s %s %s %s %s", (NR>1?" | ":""), $1, $2, $3, $4, $6, $7 }
      END { printf "\n" }')"
    lane_str="$(printf '%s' "$lane_str" | tr -d '\n')"
  elif [ "$LANE_COUNT" -gt 0 ]; then
    lane_str="$(printf '%s\n' "$LANE_ROWS" | awk -F '\t' '
      { printf "%s%s %s %s %s %s", (NR>1?" | ":""), $1, $2, $3, $5, $6 }
      END { printf "\n" }')"
    lane_str="$(printf '%s' "$lane_str" | tr -d '\n')"
  fi
  if [ -n "$lane_str" ]; then
    printf '%s | lanes %d: %s\n' "$head" "$LANE_COUNT" "$lane_str"
  else
    printf '%s | lanes %d\n' "$head" "$LANE_COUNT"
  fi
}

emit_lanes_table() {
  case "$SUP_STATE" in
    on)     printf 'supervisor: ON   (%s)\n' "$SUP_WHY" ;;
    stale)  printf 'supervisor: STALE (%s)\n' "$SUP_WHY" ;;
    *)      printf 'supervisor: OFF  (%s)\n' "$SUP_WHY" ;;
  esac
  # STATUS-SURFACE-R5-01 round 2: when active.yaml could not be read the lane
  # list does NOT reflect reality, so the header must not render a calm
  # "N live" count -- it renders an explicit warning and the menu-bar title
  # carries ⚠ (see leadv2-status-surface.10s.sh). First token stays `lanes` so
  # the section parser keeps matching; the ⚠ glyph is the breakage signal.
  if [ "$ZERO_PROJECTS" -eq 1 ]; then
    printf 'lanes (⚠ no project state under %s)\n' "$ZERO_PROJECTS_BASE"
    return 0
  fi
  if [ -n "$WARN_MSG" ]; then
    printf 'lanes (⚠ active.yaml не прочитан — список не отражает реальность)\n'
    printf '  %s\n' "$WARN_MSG"
    return 0
  fi
  # STATUS-SURFACE-R5-01 (C2/C1d): header carries the live + recent-terminal
  # counts and, only when rows were aged out, how many were hidden -- so a drop
  # is never silent. First token stays `lanes` (section parser + statusline).
  # SWIFTBAR-LIVE-01: multi-project header additionally carries the project
  # count so "lanes" stays the parseable first token in every mode.
  # SWIFTBAR-LIVE-01 round 3 (§2.4): the header is now the SOLE producer of
  # live/dead counts -- leadv2-status-surface.10s.sh used to re-derive its own
  # LIVE_N/DEAD_N by awk-slicing this rendered table, so the two disagreed
  # ("🔴 3 / 🟢 0" badge vs "1 live" header, same render). DEAD_N is computed
  # above from the same per-lane state LIVE_N comes from -- it was just never
  # printed. Printing it here means the badge's sed-parse reads this exact
  # number instead of re-deriving one.
  if [ "$MULTI_PROJECT" -eq 1 ]; then
    if [ "$AGED_OUT_N" -gt 0 ]; then
      printf 'lanes (%d live, %d dead, %d done в последний час, %d скрыто по возрасту · %d projects)\n' \
        "$LIVE_N" "$DEAD_N" "$DONE_RECENT_N" "$AGED_OUT_N" "${#PROJ_SLUGS[@]}"
    else
      printf 'lanes (%d live, %d dead, %d done в последний час · %d projects)\n' \
        "$LIVE_N" "$DEAD_N" "$DONE_RECENT_N" "${#PROJ_SLUGS[@]}"
    fi
  elif [ "$AGED_OUT_N" -gt 0 ]; then
    printf 'lanes (%d live, %d dead, %d done в последний час, %d скрыто по возрасту)\n' \
      "$LIVE_N" "$DEAD_N" "$DONE_RECENT_N" "$AGED_OUT_N"
  else
    printf 'lanes (%d live, %d dead, %d done в последний час)\n' "$LIVE_N" "$DEAD_N" "$DONE_RECENT_N"
  fi
  if [ "$LANE_COUNT" -eq 0 ]; then
    printf '  (none)\n'
  elif [ "$MULTI_PROJECT" -eq 1 ]; then
    printf '  %-14s %-28s %-6s %-18s %-7s %-5s %-18s %s\n' "PROJ" "NAME" "TYPE" "PHASE/STATE" "MODEL" "AGE" "STATE" "SIG"
    printf '%s\n' "$LANE_ROWS" | awk -F '\t' '{ printf "  %-14s %-28s %-6s %-18s %-7s %-5s %-18s %s\n", $1, $2, $3, $4, $5, $6, $7, $9 }'
  else
    printf '  %-28s %-6s %-18s %-7s %-5s %-18s %s\n' "NAME" "TYPE" "PHASE/STATE" "MODEL" "AGE" "STATE" "SIG"
    printf '%s\n' "$LANE_ROWS" | awk -F '\t' '{ printf "  %-28s %-6s %-18s %-7s %-5s %-18s %s\n", $1, $2, $3, $4, $5, $6, $8 }'
  fi
}

# ── Round 4 sections ───────────────────────────────────────────────────────
# Each section is independently renderable and machine-readable: the header's
# first token carries the count the widget parses (questions (N) / due: n /
# urgent: n), so the widget never re-parses the human lanes table for these.
# ZERO network, ZERO LLM, ZERO calls to leadv2-quota-status.sh (the only path
# that may run it is --refresh-limits; see render_refresh_limits).

# Pending founder questions. Sources (LEAD-ANCHOR-01, verified on disk):
#   control-plane  ${STATE_DIR}/questions/*.yaml  (status==pending)
#   legacy-handoff <handoff>/*/questions-async/*-pending.yaml with NO sibling
#                  <qid>-answered.yaml
# Question text is founder/LLM-authored: strip '|' (SwiftBar param delimiter)
# and collapse newlines BEFORE emitting (R4 §5.5).
render_questions() {
  local qdir handoff
  qdir="${LEADV2_STATUS_QUESTIONS_DIR:-${STATE_DIR}/questions}"
  handoff="${LEADV2_STATUS_HANDOFF_DIR:-}"
  if [ -z "$handoff" ]; then
    _r4h_top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    [ -n "$_r4h_top" ] && [ -d "${_r4h_top}/docs/handoff" ] && handoff="${_r4h_top}/docs/handoff"
  fi
  unset _r4h_top 2>/dev/null || true
  LEADV2_R4_QDIR="$qdir" LEADV2_R4_HANDOFF="$handoff" python3 2>/dev/null <<'PYEOF'
import os, sys, glob
qdir = os.environ.get("LEADV2_R4_QDIR", "")
handoff = os.environ.get("LEADV2_R4_HANDOFF", "")

# ---- R5-01 round 2: PyYAML-optional YAML reader (VERBATIM COPY of the one in
# the _ss_lanes_py heredoc above). SwiftBar's minimal-PATH python3 has no
# PyYAML, so without this the pending-question count silently under-reports.
# Duplicated rather than sourced from a shared .py to avoid adding a runtime
# artifact to this read path; keep both copies in sync. See the lanes heredoc
# for the full design notes.
def _mini_yaml(text):
    def _unclosed(v):
        j, L = 0, len(v)
        while j < L:
            c = v[j]
            if c == "'":
                k = j + 1
                while k < L:
                    if v[k] == "'":
                        if k + 1 < L and v[k + 1] == "'":
                            k += 2; continue
                        return None
                    k += 1
                return "'"
            if c == '"':
                k = j + 1
                while k < L:
                    if v[k] == "\\":
                        k += 2; continue
                    if v[k] == '"':
                        return None
                    k += 1
                return '"'
            j += 1
        return None

    def _vsub(body):
        if body.startswith("- "):
            inner = body[2:]
            return inner.split(":", 1)[1] if ":" in inner else inner
        return body.split(":", 1)[1] if ":" in body else body

    raw = text.replace("\r\n", "\n").split("\n")
    lines = []
    i, n = 0, len(raw)
    while i < n:
        line = raw[i]
        m = 0
        while m < len(line) and line[m] == " ":
            m += 1
        if m < len(line) and line[m] == "\t":
            raise ValueError("tab indentation unsupported")
        body = line[m:]
        if body == "" or body.startswith("#"):
            i += 1; continue
        q = _unclosed(_vsub(body))
        if q is None:
            lines.append((m, body)); i += 1; continue
        parts = [body]; i += 1; closed = False
        while i < n:
            parts.append(raw[i].lstrip(" "))
            if _unclosed(_vsub(" ".join(parts))) is None:
                closed = True; i += 1; break
            i += 1
        if not closed:
            raise ValueError("unterminated quoted scalar")
        lines.append((m, " ".join(parts)))

    def _scalar(v):
        v = v.strip()
        if v == "":
            return None
        if v[:1] in ("[", "{"):
            # Reached only if a caller forgot to route through _flow_parse first
            # (every real call site below does). Fail loud rather than garbage.
            raise ValueError("inline flow collection unsupported")
        if len(v) >= 2 and v[0] == v[-1] and v[0] in ("'", '"'):
            if v[0] == "'":
                return v[1:-1].replace("''", "'")
            s, out, k, L = v[1:-1], [], 0, len(v) - 2
            while k < L:
                c = s[k]
                if c == "\\" and k + 1 < L:
                    n = s[k + 1]
                    if n == "n": out.append("\n"); k += 2
                    elif n == "t": out.append("\t"); k += 2
                    elif n == '"': out.append('"'); k += 2
                    elif n == "'": out.append("'"); k += 2
                    elif n == "\\": out.append("\\"); k += 2
                    elif n == " ": k += 2  # folded line continuation (merge artifact)
                    elif n == "u" and k + 6 <= L:
                        try: out.append(chr(int(s[k + 2:k + 6], 16))); k += 6
                        except ValueError: out.append(c); k += 1
                    elif n == "x" and k + 4 <= L:
                        try: out.append(chr(int(s[k + 2:k + 4], 16))); k += 4
                        except ValueError: out.append(c); k += 1
                    else: out.append(c); k += 1
                else:
                    out.append(c); k += 1
            return "".join(out)
        low = v.lower()
        if low in ("null", "~", ""):
            return None
        if low == "true":
            return True
        if low == "false":
            return False
        try:
            return int(v)
        except Exception:
            pass
        try:
            return float(v)
        except Exception:
            pass
        return v

    # ---- SWIFTBAR-R4 RC-3: flow-style collections ------------------------
    # `key: [a, b]`, `key: [{k: v}, {k: v}]`, and `- {k: v, k2: v}` (a block
    # sequence item written as a flow mapping). Without this, an operator's
    # question `options:` written as a flow sequence of flow mappings -- the
    # only shape the real writer emits -- silently vanished (dropped to ""),
    # under-reporting the pending-question count as 0 instead of raising.
    def _flow_ws(s, pos):
        while pos < len(s) and s[pos] in " \t":
            pos += 1
        return pos

    def _flow_quoted(s, pos):
        q = s[pos]; pos += 1
        out = []
        if q == "'":
            while pos < len(s):
                if s[pos] == "'":
                    if pos + 1 < len(s) and s[pos + 1] == "'":
                        out.append("'"); pos += 2; continue
                    return "".join(out), pos + 1
                out.append(s[pos]); pos += 1
            raise ValueError("unterminated quoted scalar in flow value")
        while pos < len(s):
            c = s[pos]
            if c == "\\" and pos + 1 < len(s):
                nx = s[pos + 1]
                if nx == "n": out.append("\n")
                elif nx == "t": out.append("\t")
                elif nx == '"': out.append('"')
                elif nx == "'": out.append("'")
                elif nx == "\\": out.append("\\")
                else: out.append(nx)
                pos += 2; continue
            if c == '"':
                return "".join(out), pos + 1
            out.append(c); pos += 1
        raise ValueError("unterminated quoted scalar in flow value")

    def _flow_bare(s, pos, stop):
        start = pos
        while pos < len(s) and s[pos] not in stop:
            pos += 1
        return s[start:pos].strip(), pos

    def _flow_value(s, pos):
        pos = _flow_ws(s, pos)
        if pos >= len(s):
            raise ValueError("unexpected end of flow value")
        c = s[pos]
        if c == "[":
            return _flow_seq(s, pos)
        if c == "{":
            return _flow_map(s, pos)
        if c in ("'", '"'):
            raw, pos = _flow_quoted(s, pos)
            return raw, pos
        raw, pos = _flow_bare(s, pos, ",]}\n")
        if raw == "":
            raise ValueError("empty scalar in flow value")
        return _scalar(raw), pos

    def _flow_seq(s, pos):
        pos += 1  # consume '['
        arr = []
        pos = _flow_ws(s, pos)
        if pos < len(s) and s[pos] == "]":
            return arr, pos + 1
        while True:
            val, pos = _flow_value(s, pos)
            arr.append(val)
            pos = _flow_ws(s, pos)
            if pos >= len(s):
                raise ValueError("unterminated flow sequence")
            if s[pos] == ",":
                pos = _flow_ws(s, pos + 1); continue
            if s[pos] == "]":
                return arr, pos + 1
            raise ValueError("expected ',' or ']' in flow sequence")

    def _flow_map(s, pos):
        pos += 1  # consume '{'
        d = {}
        pos = _flow_ws(s, pos)
        if pos < len(s) and s[pos] == "}":
            return d, pos + 1
        while True:
            pos = _flow_ws(s, pos)
            if pos < len(s) and s[pos] in ("'", '"'):
                key, pos = _flow_quoted(s, pos)
            else:
                key, pos = _flow_bare(s, pos, ":,{}[]'\"")
            if key == "":
                raise ValueError("empty key in flow mapping")
            pos = _flow_ws(s, pos)
            if pos >= len(s) or s[pos] != ":":
                raise ValueError("expected ':' in flow mapping")
            val, pos = _flow_value(s, pos + 1)
            d[key] = val
            pos = _flow_ws(s, pos)
            if pos >= len(s):
                raise ValueError("unterminated flow mapping")
            if s[pos] == ",":
                pos = _flow_ws(s, pos + 1); continue
            if s[pos] == "}":
                return d, pos + 1
            raise ValueError("expected ',' or '}' in flow mapping")

    def _flow_parse(v):
        val, pos = _flow_value(v, 0)
        if v[pos:].strip() != "":
            raise ValueError("trailing content after flow value")
        return val

    def _map(lines, pos, indent):
        d = {}
        while pos < len(lines):
            ind, body = lines[pos]
            if ind < indent:
                break
            if ind > indent:
                raise ValueError("unexpected indent in mapping")
            if body == "-" or body.startswith("- "):
                raise ValueError("sequence item where mapping key expected")
            key, sep, val = body.partition(":")
            if sep != ":":
                raise ValueError("expected 'key:'")
            key = key.strip()
            if key == "":
                raise ValueError("empty key")
            val = val.strip()
            pos += 1
            if val == "":
                nind, nbody = (lines[pos] if pos < len(lines) else (None, None))
                if nind is not None and (nind > indent or
                        (nind == indent and (nbody == "-" or nbody.startswith("- ")))):
                    child, pos = _node(lines, pos)
                    d[key] = child
                else:
                    d[key] = None
            elif val[:1] in ("[", "{"):
                d[key] = _flow_parse(val)
            elif val[:1] in ("|", ">"):
                # block scalar (| literal / > folded, optional -/+ chomp).
                # Consume every deeper-indented logical line as content so the
                # parser never chokes on a machine-written block field. Exact
                # value is unused by the renderers (they read scalar keys), so
                # best-effort folding is fine; the contract is: consume the
                # span, never raise.
                buf = []
                while pos < len(lines) and lines[pos][0] > indent:
                    buf.append(lines[pos][1]); pos += 1
                d[key] = " ".join(buf) if val[:1] == ">" else "\n".join(buf)
            elif val.startswith("- "):
                raise ValueError("inline sequence unsupported")
            else:
                # plain (or single-line quoted) scalar. A PLAIN scalar may fold
                # across following more-indented lines (YAML plain-scalar
                # continuation); quoted multi-line is already one logical line.
                v = val
                if not (len(val) >= 2 and val[0] == val[-1] and val[0] in ("'", '"')):
                    while pos < len(lines) and lines[pos][0] > indent:
                        v = v + " " + lines[pos][1]; pos += 1
                d[key] = _scalar(v)
        return d, pos

    def _seq(lines, pos, indent):
        arr = []
        while pos < len(lines):
            ind, body = lines[pos]
            if ind < indent:
                break
            if ind > indent:
                raise ValueError("unexpected indent in sequence")
            if body == "-":
                pos += 1
                nind = lines[pos][0] if pos < len(lines) else None
                if nind is not None and nind > indent:
                    child, pos = _node(lines, pos); arr.append(child)
                else:
                    arr.append(None)
                continue
            if not body.startswith("- "):
                break
            pos += 1
            rest = body[2:].strip()
            if rest == "":
                nind = lines[pos][0] if pos < len(lines) else None
                if nind is not None and nind > indent:
                    child, pos = _node(lines, pos); arr.append(child)
                else:
                    arr.append(None)
                continue
            if rest[:1] in ("[", "{"):
                arr.append(_flow_parse(rest))
            elif ":" in rest:
                vindent = indent + 2
                sub = [(vindent, rest)] + lines[pos:]
                item, csub = _map(sub, 0, vindent)
                arr.append(item)
                pos += csub - 1
            else:
                arr.append(_scalar(rest))
        return arr, pos

    def _node(lines, pos):
        if pos >= len(lines):
            return None, pos
        ind, body = lines[pos]
        if body == "-" or body.startswith("- "):
            return _seq(lines, pos, ind)
        return _map(lines, pos, ind)

    doc, _ = _node(lines, 0)
    if not isinstance(doc, dict):
        raise ValueError("top-level document is not a mapping")
    return doc

def _load_yaml(path):
    try:
        import yaml
    except ImportError:
        with open(path, "r", encoding="utf-8") as fh:
            txt = fh.read()
        if txt.strip() == "":
            return {}
        return _mini_yaml(txt)
    with open(path, "r", encoding="utf-8") as fh:
        return yaml.safe_load(fh) or {}

def parse(path):
    # returns the question dict, or None if unreadable/non-mapping (-> skipped)
    try:
        d = _load_yaml(path)
    except Exception:
        return None
    if not isinstance(d, dict):
        return None
    return d

def labels_of(d):
    out = []
    for o in (d.get("options") or []):
        if isinstance(o, dict):
            lab = o.get("label") or o.get("text") or ""
        else:
            lab = str(o)
        lab = str(lab).replace("|", "").replace("\n", " ").strip()
        if lab:
            out.append(lab)
    return out

items = []  # (qid, text, [labels])
if qdir and os.path.isdir(qdir):
    for qf in sorted(glob.glob(os.path.join(qdir, "*.yaml"))):
        base = os.path.basename(qf)
        qid = base[:-5] if base.endswith(".yaml") else base
        d = parse(qf)
        if d is None or d.get("status") != "pending":
            continue
        text = (d.get("question") or d.get("summary_for_lead") or "")
        text = str(text).replace("|", "").replace("\n", " ").strip()
        items.append((qid, text, labels_of(d)))

if handoff and os.path.isdir(handoff):
    for pf in sorted(glob.glob(os.path.join(handoff, "*", "questions-async", "*-pending.yaml"))):
        qd = os.path.dirname(pf)
        base = os.path.basename(pf)
        qid = base[:-len("-pending.yaml")] if base.endswith("-pending.yaml") else base
        if os.path.isfile(os.path.join(qd, qid + "-answered.yaml")):
            continue
        d = parse(pf) or {}
        text = (d.get("question") or d.get("summary_for_lead") or "")
        text = str(text).replace("|", "").replace("\n", " ").strip()
        items.append((qid, text, labels_of(d)))

sys.stdout.write("questions (%d)\n" % len(items))
for qid, text, labels in items:
    line = "%s  %s" % (qid, text[:80])
    if labels:
        line += "  [%s]" % "|".join(labels)
    sys.stdout.write(line + "\n")
PYEOF
}

# Per-provider limits (SWIFTBAR-LIVE-01 rewrite). Reads ONE small kv file per
# provider under LEADV2_LIMITS_CACHE_DIR — never a network/keychain call on
# this path, so the 10s SwiftBar tick never blocks. Staleness is per-provider
# now (the old block-level "limits (stale Nm)" suffix is gone): a fresh kv
# prints its value verbatim; a stale or missing kv prints the last-known value
# (or a placeholder) plus a short human suffix AND fires
# leadv2-limits-refresh.sh --provider <p> detached, non-blocking, capped by
# that script's own per-provider mkdir lock.
render_limits() {
  local cache_dir refresher
  cache_dir="${LEADV2_LIMITS_CACHE_DIR:-${HOME}/.claude/cache/leadv2-limits.d}"
  refresher="${LEADV2_LIMITS_REFRESH_SH:-${SCRIPT_DIR}/leadv2-limits-refresh.sh}"
  printf 'limits\n'
  local p
  for p in claude glm codex kimi; do
    _render_one_limit "$cache_dir" "$refresher" "$p"
  done
}

# Reads <cache_dir>/<provider>.kv (state/value/stamped/ttl/detail, first '='
# splits) and renders exactly one line, firing a detached non-blocking
# refresh when the row is stale or missing. Never touches the network itself.
_render_one_limit() {
  local cache_dir="$1" refresher="$2" provider="$3"
  local f="${cache_dir}/${provider}.kv"
  local state="" value="" stamped="" ttl="" detail=""
  if [ -f "$f" ]; then
    while IFS='=' read -r k v; do
      case "$k" in
        state)   state="$v" ;;
        value)   value="$v" ;;
        stamped) stamped="$v" ;;
        ttl)     ttl="$v" ;;
        detail)  detail="$v" ;;
      esac
    done < "$f"
  fi
  local fresh=0
  case "$stamped" in
    ''|*[!0-9]*) fresh=0 ;;
    *)
      case "$ttl" in ''|*[!0-9]*) ttl=90 ;; esac
      [ $(( NOW - stamped )) -le "$ttl" ] && fresh=1
      ;;
  esac
  if [ -z "$state" ]; then
    printf '  %s: (получаем…)\n' "$provider"
    _fire_limits_refresh "$refresher" "$provider"
    return 0
  fi
  if [ "$fresh" -eq 1 ]; then
    _print_limit_line "$provider" "$state" "$value" "$detail" ""
  else
    _print_limit_line "$provider" "$state" "$value" "$detail" " (обновляется…)"
    _fire_limits_refresh "$refresher" "$provider"
  fi
}

_fire_limits_refresh() {
  local refresher="$1" provider="$2"
  [ -x "$refresher" ] || return 0
  ( bash "$refresher" --provider "$provider" >/dev/null 2>&1 & ) 2>/dev/null || true
}

_print_limit_line() {
  local provider="$1" state="$2" value="$3" detail="$4" suffix="$5"
  case "$state" in
    ok)
      printf '  %s: %s%s\n' "$provider" "$value" "$suffix"
      ;;
    unauthenticated)
      printf '  %s: %s\n' "$provider" "${detail:-нет валидного OAuth-токена}"
      ;;
    *)
      if [ -n "$value" ]; then
        printf '  %s: %s%s\n' "$provider" "$value" "$suffix"
      else
        printf '  %s: (получаем…)%s\n' "$provider" "$suffix"
      fi
      ;;
  esac
}

# Scheduled-decisions due/overdue count. Source is the cross-repo
# scheduled-decisions-inject.sh hook (emits {"additionalContext": "..."} JSON,
# exit 0 always). Path env-overridable + [ -x ] guarded; absent → omit entirely.
render_due() {
  local hook raw
  hook="${LEADV2_STATUS_SD_HOOK:-${HOME}/Projects/persona-engine/.claude/hooks/scheduled-decisions-inject.sh}"
  [ -x "$hook" ] || return 0
  raw="$("$hook" 2>/dev/null || true)"
  [ -n "$raw" ] || raw="{}"
  printf '%s' "$raw" | python3 -c 'import sys, json
raw = sys.stdin.read()
due = overdue = 0
try:
    ctx = (json.loads(raw) or {}).get("additionalContext") or ""
    for line in ctx.splitlines():
        if line.startswith("[OVERDUE]"):
            overdue += 1; due += 1
        elif line.startswith("[DUE TODAY]") or line.startswith("[CONDITION-BOUND]"):
            due += 1
except Exception:
    pass
print("due: %d overdue: %d" % (due, overdue))'
}

# Urgent alarms from the supervise loop log. Counts [SUPERVISE-URGENT] lines
# newer than 4h, deduped by alarm key (category + subject id, volatile age=
# tokens stripped) so a persistent breach that fired once is not double-counted.
render_alarms() {
  local logf n
  logf="${LEADV2_STATUS_URGENT_LOG:-}"
  if [ -z "$logf" ] && [ -x "${STATE_PATH_SH}" ]; then
    logf="$(bash "${STATE_PATH_SH}" --no-link supervise-loop.log 2>/dev/null || true)"
  fi
  n=0
  if [ -f "$logf" ]; then
    n="$(LEADV2_R4_LOG="$logf" LEADV2_R4_NOW="$NOW" python3 -c 'import os, re, datetime
logf = os.environ["LEADV2_R4_LOG"]; now = int(os.environ["LEADV2_R4_NOW"])
seen = set()
try:
    with open(logf, encoding="utf-8") as fh:
        for line in fh:
            if "[SUPERVISE-URGENT]" not in line:
                continue
            ts_m = re.match(r"^(\S+) \[SUPERVISE-URGENT\]", line)
            if ts_m:
                try:
                    ep = int(datetime.datetime.fromisoformat(ts_m.group(1).rstrip("Z")+"+00:00").timestamp())
                except Exception:
                    ep = None
                if ep is not None and not (0 <= (now - ep) <= 14400):
                    continue
            content = line.split("[SUPERVISE-URGENT]", 1)[1].strip()
            key = " ".join(content.split()[:2])
            key = re.sub(r"age=\S+", "", key).strip() or content
            seen.add(key)
except Exception:
    pass
print(len(seen))' 2>/dev/null || true)"
  fi
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf 'urgent: %d (4h)\n' "$n"
}

# SWIFTBAR-LIVE-01 migration: --refresh-limits is now a thin, BLOCKING alias
# for `leadv2-limits-refresh.sh --provider all --force` (the render path
# itself never blocks -- see render_limits above). Kept for backward compat
# with any caller still invoking `--refresh-limits` directly.
render_refresh_limits() {
  local refresher
  refresher="${LEADV2_LIMITS_REFRESH_SH:-${SCRIPT_DIR}/leadv2-limits-refresh.sh}"
  if [ -x "$refresher" ]; then
    bash "$refresher" --provider all --force 2>/dev/null || true
    printf 'limits refreshed via %s\n' "$refresher"
  else
    printf 'limits refresh unavailable (missing %s)\n' "$refresher"
  fi
}

# ── Dispatch ───────────────────────────────────────────────────────────────
case "$MODE" in
  oneline)        emit_oneline; exit 0 ;;
  default)        emit_lanes_table; exit 0 ;;
  questions)      render_questions; exit 0 ;;
  limits)         render_limits; exit 0 ;;
  due)            render_due; exit 0 ;;
  alarms)         render_alarms; exit 0 ;;
  refresh-limits) render_refresh_limits; exit 0 ;;
  all)
    emit_lanes_table
    printf -- '---\n'
    render_questions
    printf -- '---\n'
    render_limits
    printf -- '---\n'
    render_due
    printf -- '---\n'
    render_alarms
    exit 0
    ;;
esac
