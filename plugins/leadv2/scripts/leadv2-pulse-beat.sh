#!/usr/bin/env bash
# scripts/leadv2-pulse-beat.sh — PULSE-IN-SINGLE-LEAD-01
#
# Drives the SAME composer (leadv2-broad-status.sh) that
# the (now-retired) supervisor loop's beat branch used to call, for a session
# that is running single-lead mode instead of the supervisor loop. Never renders
# anything itself and never writes founder-status.md directly — this is
# purely a "dispatch, then compose" driver, same order as the loop
# (the now-retired supervisor loop, formerly lines 842-852): the backlog pump runs first and its
# dispatched-count is exported into the beat before the composer sees it.
#
# Kill-switch: LEADV2_SINGLE_LEAD_BEAT=0 makes every invocation a no-op
# (rc=0, no pump call, no composer call, no state touched). This is the
# rollback for the whole feature — the hook that calls this script also
# checks the same var first, so the composer is never reached from either
# caller when it's off.
#
# Invocations:
#   --check   background-safe: honours the throttle + loop-liveness gate,
#             never fails a caller (always rc=0)
#   --now     bypasses the throttle, runs synchronously, exit = composer rc;
#             PLUGIN-PAPERCUTS-01: --check accepts --owner=<repo>:<lane> (or
#             LEADV2_BEAT_OWNER_TAG) to stamp the spawned watcher's argv so a
#             reparented orphan is attributable; default derives it from the
#             project root + checked-out branch
#   --due     predicate only: prints due|not-due|loop-owns, exits 0/1
set -uo pipefail
trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:---check}"

# PLUGIN-PAPERCUTS-01 (defect 1): the detached --now watcher is reparented to
# launchd and its argv is the ONLY thing identifying who owns it (repo + lane)
# — a bare "pulse-beat.sh --now" made a safe orphan sweep impossible (measured
# 2026-08-31: fixture-root loops no repo, no lane, unkillable-by-attribution).
# The owner tag is pinned by the caller (--owner=<repo>:<lane> as $2, or
# LEADV2_BEAT_OWNER_TAG) or derived from PROJECT_ROOT + git branch below.
OWNER_TAG_IN="${LEADV2_BEAT_OWNER_TAG:-}"
if [[ -z "$OWNER_TAG_IN" && "${2:-}" == --owner=* ]]; then
  OWNER_TAG_IN="${2#--owner=}"
fi

[[ "${LEADV2_SINGLE_LEAD_BEAT:-1}" == "0" ]] && { [[ "$MODE" == "--due" ]] && { printf -- 'disabled\n'; exit 1; }; exit 0; }

PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)}}"
if [[ -z "$PROJECT_ROOT" ]]; then
  [[ "$MODE" == "--due" ]] && printf -- 'no-root\n'
  exit 0
fi
export LEADV2_PROJECT_ROOT="$PROJECT_ROOT"

# PLUGIN-PAPERCUTS-01 (defect 1): owner-stamp derivation, evaluated lazily at
# spawn (one basename + one `git branch` per actual watcher, not per hook
# fire). Explicit input wins and is charset-guarded (it goes into a
# ps-visible argv); a detached HEAD degrades to repo-only, which still
# narrows a sweep.
_beat_owner_tag() {
  local _tag="${OWNER_TAG_IN:-}" _repo _lane
  if [[ -n "$_tag" ]]; then
    [[ "$_tag" =~ ^[A-Za-z0-9._/-]+(:[A-Za-z0-9._/-]+)?$ ]] || _tag=""
    printf '%s' "$_tag"
    return 0
  fi
  _repo="$(basename "$PROJECT_ROOT" 2>/dev/null)" || return 0
  _lane="$(git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null || true)"
  if [[ -n "$_lane" ]]; then
    printf '%s:%s' "$_repo" "$_lane"
  else
    printf '%s' "$_repo"
  fi
}

STATE_PATH_SH="$SCRIPT_DIR/leadv2-state-path.sh"
PUMP_SH="${LEADV2_BACKLOG_PUMP_BIN:-${SCRIPT_DIR}/leadv2-backlog-pump.sh}"
BROAD_STATUS_SH="${LEADV2_BROAD_STATUS_BIN:-${SCRIPT_DIR}/leadv2-broad-status.sh}"
LOG_FILE="$(PROJECT_ROOT="$PROJECT_ROOT" "$STATE_PATH_SH" supervise-loop.log 2>/dev/null || true)"
[[ -z "$LOG_FILE" ]] && LOG_FILE="${PROJECT_ROOT}/docs/leadv2/supervise-loop.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

BEAT_S="${LEADV2_SINGLE_LEAD_BEAT_S:-1800}"
[[ "$BEAT_S" =~ ^[0-9]+$ ]] || BEAT_S=1800

STATE_DIR="$(PROJECT_ROOT="$PROJECT_ROOT" "$STATE_PATH_SH" --no-link root 2>/dev/null || true)"
[[ -z "$STATE_DIR" ]] && STATE_DIR="${PROJECT_ROOT}/docs/leadv2"
mkdir -p "$STATE_DIR" 2>/dev/null || true
BEAT_LAST_FILE="${STATE_DIR}/.pulse-beat-last"
BEAT_LOCK_FILE="${STATE_DIR}/.pulse-beat.lock"
LOOP_SENTINEL="${STATE_DIR}/.supervise-loop.json"

# ── PULSE-EMPTY-BOARD-01: transition state, cheap enough to poll on every
#    hook fire (this script's --check is already called once per tool call
#    via hooks/leadv2-single-lead-beat.sh). Three files:
#    .pulse-live-count-last — last COMMITTED count of "running" lanes, used
#      to detect a drop (>=1 -> 0 is the loud case, any drop is "a lane
#      reached terminal state").
#    .pulse-review-watermark — mtime cursor: `find -newer` against this
#      file's own mtime finds review-gate.md writes since the last commit.
#    .pulse-review-pending.jsonl — one JSON line per newly-seen verdict,
#      appended by the commit step, consumed (read + truncated) exactly once
#      by the render that actually fires. ──────────────────────────────────
LIVE_COUNT_LAST_FILE="${STATE_DIR}/.pulse-live-count-last"
REVIEW_WATERMARK_FILE="${STATE_DIR}/.pulse-review-watermark"
REVIEW_PENDING_FILE="${STATE_DIR}/.pulse-review-pending.jsonl"

_now_epoch() { date +%s; }

# ── loop-liveness: if the real supervise loop owns this beat, never
#    double-drive the composer (R2). Same primitive as
#    leadv2-supervisor-pump-caller.sh. ─────────────────────────────────────
_loop_is_live() {
  [[ -f "$LOOP_SENTINEL" ]] || return 1
  python3 -c "
import sys, json, os
try:
    with open(sys.argv[1], encoding='utf-8') as fh:
        d = json.load(fh) or {}
    pid = d.get('pid')
    if pid is None:
        sys.exit(1)
    os.kill(int(pid), 0)
    sys.exit(0)
except Exception:
    sys.exit(1)
" "$LOOP_SENTINEL" 2>/dev/null
}

# _lv2_current_live_count -> prints an integer count of lanes whose
# leadv2-lane-heartbeat.sh verdict is exactly "running" (the only verdict
# that means "alive right now" — same rule leadv2-beat-owner.sh uses).
# Prints nothing on any failure — fail-open: callers must treat empty as
# "unknown", never as zero (a zero here must be a REAL zero, never a
# swallowed error masquerading as one).
_lv2_current_live_count() {
  local hb_sh="${LEADV2_LANE_HEARTBEAT_BIN:-${SCRIPT_DIR}/leadv2-lane-heartbeat.sh}"
  [[ -x "$hb_sh" ]] || return 0
  local json
  json="$( (LEADV2_PROJECT_ROOT="$PROJECT_ROOT" bash "$hb_sh" status --all --json 2>/dev/null || true) )"
  [[ -n "$json" ]] || return 0
  python3 -c "
import sys, json
try:
    rows = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)
if not isinstance(rows, list):
    sys.exit(0)
print(sum(1 for r in rows if isinstance(r, dict) and r.get('status') == 'running'))
" "$json" 2>/dev/null
}

# _lv2_peek_lane_drop -> rc0 iff the live-lane count has dropped since the
# last COMMIT (never mutates state — safe to call from --due, which only
# reports and must never itself consume the transition it is asked about).
_lv2_peek_lane_drop() {
  local current last
  current="$(_lv2_current_live_count)"
  [[ "$current" =~ ^[0-9]+$ ]] || return 1
  last=""
  [[ -f "$LIVE_COUNT_LAST_FILE" ]] && last="$(cat "$LIVE_COUNT_LAST_FILE" 2>/dev/null || true)"
  [[ "$last" =~ ^[0-9]+$ ]] || return 1
  (( current < last ))
}

# _lv2_commit_lane_count -> advances the committed baseline to the current
# count. Idempotent; a read failure leaves the baseline untouched (fail-open
# — never lets a bad read reset the baseline to an unknown value).
_lv2_commit_lane_count() {
  local current
  current="$(_lv2_current_live_count)"
  [[ "$current" =~ ^[0-9]+$ ]] || return 0
  printf -- '%s' "$current" > "${LIVE_COUNT_LAST_FILE}.tmp.$$" 2>/dev/null \
    && mv -f "${LIVE_COUNT_LAST_FILE}.tmp.$$" "$LIVE_COUNT_LAST_FILE" 2>/dev/null || true
}

# _lv2_peek_review_landings -> rc0 iff >=1 docs/handoff/*/review-gate.md was
# written after the watermark's own mtime. Never mutates. Cold start (no
# watermark file yet) is "nothing pending" (R1 pattern used everywhere else
# in this file: first-run never retroactively fires on pre-existing state).
_lv2_peek_review_landings() {
  local handoff_dir="${PROJECT_ROOT}/docs/handoff"
  [[ -d "$handoff_dir" ]] || return 1
  [[ -f "$REVIEW_WATERMARK_FILE" ]] || return 1
  local hit
  hit="$(find "$handoff_dir" -maxdepth 2 -name 'review-gate.md' -newer "$REVIEW_WATERMARK_FILE" 2>/dev/null | head -n1)"
  [[ -n "$hit" ]]
}

# _lv2_commit_review_landings -> appends one JSON line per newly-seen
# review-gate.md to REVIEW_PENDING_FILE and advances the watermark to now.
# Idempotent (re-running with nothing new is a cheap no-op); bounded to 50
# files per call since this runs on every real beat.
_lv2_commit_review_landings() {
  local handoff_dir="${PROJECT_ROOT}/docs/handoff"
  [[ -d "$handoff_dir" ]] || return 0
  if [[ ! -f "$REVIEW_WATERMARK_FILE" ]]; then
    : > "$REVIEW_WATERMARK_FILE" 2>/dev/null || true
    return 0
  fi
  local f status detail crit high med low task_id
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    status="$(sed -n 's/^status:[[:space:]]*//p' "$f" 2>/dev/null | head -n1)"
    [[ -n "$status" ]] || status="unknown"
    detail=""
    case "$status" in
      fail)
        crit="$(sed -n 's/^critical:[[:space:]]*//p' "$f" 2>/dev/null | head -n1)"
        high="$(sed -n 's/^high:[[:space:]]*//p' "$f" 2>/dev/null | head -n1)"
        med="$(sed -n 's/^medium:[[:space:]]*//p' "$f" 2>/dev/null | head -n1)"
        low="$(sed -n 's/^low:[[:space:]]*//p' "$f" 2>/dev/null | head -n1)"
        detail="$(printf -- '%s\n' \
          "${crit:+$crit crit}" "${high:+$high high}" "${med:+$med med}" "${low:+$low low}" \
          | grep -v '^$' | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
        ;;
      blocked|unreviewed)
        detail="$(sed -n 's/^reason:[[:space:]]*//p' "$f" 2>/dev/null | head -n1)"
        ;;
    esac
    task_id="$(basename "$(dirname "$f")")"
    python3 -c "
import json, sys
print(json.dumps({'task': sys.argv[1], 'status': sys.argv[2], 'detail': sys.argv[3]}))
" "$task_id" "$status" "$detail" >> "$REVIEW_PENDING_FILE" 2>/dev/null || true
  done < <(find "$handoff_dir" -maxdepth 2 -name 'review-gate.md' -newer "$REVIEW_WATERMARK_FILE" 2>/dev/null | head -n 50)
  touch "$REVIEW_WATERMARK_FILE" 2>/dev/null || true
}

# _lv2_format_review_pending <file> -> "N ревью → FAIL (3 high), BLOCKED
# (provider_error)" or empty if the file has nothing parseable. Never
# raises — a malformed line is skipped, not fatal (R5 pattern, same as the
# composer's provider-health reads).
_lv2_format_review_pending() {
  local file="$1"
  [[ -s "$file" ]] || return 0
  python3 -c "
import json, sys
items = []
try:
    with open(sys.argv[1], encoding='utf-8') as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                items.append(json.loads(line))
            except Exception:
                continue
except OSError:
    pass
if not items:
    sys.exit(0)
parts = []
for it in items:
    status = str(it.get('status', 'unknown')).upper()
    detail = (it.get('detail') or '').strip()
    parts.append(f'{status} ({detail})' if detail else status)
print(f'{len(items)} ревью → ' + ', '.join(parts))
" "$file" 2>/dev/null
}

# _prepare_transition_env -> commits the lane-count + review-landing state
# EXACTLY ONCE per beat and exports LEADV2_BROAD_STATUS_REVIEW_DELTA for the
# composer to fold into its delta line. Idempotent via the
# LEADV2_BEAT_TRANSITIONS_PREPARED sentinel: the --check path calls this
# synchronously (under the flock, before spawning) so the commit — which is
# what makes a second near-simultaneous --check see "nothing new" and stay
# silent — happens under the SAME mutual-exclusion primitive that already
# guarantees only one spawn wins; the spawned --now child inherits the
# sentinel + already-built env var and skips recomputing it. A direct manual
# --now call (no parent --check) commits it itself.
_prepare_transition_env() {
  [[ "${LEADV2_BEAT_TRANSITIONS_PREPARED:-0}" == "1" ]] && return 0
  _lv2_commit_lane_count
  _lv2_commit_review_landings
  local review_delta=""
  if [[ -f "$REVIEW_PENDING_FILE" ]]; then
    review_delta="$(_lv2_format_review_pending "$REVIEW_PENDING_FILE")"
    : > "$REVIEW_PENDING_FILE" 2>/dev/null || true
  fi
  export LEADV2_BROAD_STATUS_REVIEW_DELTA="$review_delta"
  export LEADV2_BEAT_TRANSITIONS_PREPARED=1
}

_due() {
  # 0 = due, 1 = not due (throttle), 2 = loop owns the beat
  if _loop_is_live; then
    return 2
  fi
  # PULSE-EMPTY-BOARD-01: a pending transition (lane drop or a landed
  # review verdict) is due immediately, bypassing the clock throttle. Peek
  # only — never consumes here, so a pure `--due` probe cannot swallow a
  # transition a real caller hasn't acted on yet.
  if _lv2_peek_lane_drop || _lv2_peek_review_landings; then
    return 0
  fi
  local now last
  now="$(_now_epoch)"
  last=0
  [[ -f "$BEAT_LAST_FILE" ]] && last="$(cat "$BEAT_LAST_FILE" 2>/dev/null || echo 0)"
  [[ "$last" =~ ^[0-9]+$ ]] || last=0
  (( now - last >= BEAT_S ))
}

if [[ "$MODE" == "--due" ]]; then
  if _loop_is_live; then
    printf -- 'loop-owns\n'; exit 1
  elif _due; then
    printf -- 'due\n'; exit 0
  else
    printf -- 'not-due\n'; exit 1
  fi
fi

if [[ "$MODE" != "--now" ]]; then
  # --check: loop-liveness + throttle gate BEFORE touching anything.
  if _loop_is_live; then
    exit 0
  fi
  if ! _due; then
    exit 0
  fi
fi

# R1: stamp the throttle clock BEFORE doing any work, so a hung composer
# cannot cause a beat storm on the next --check.
printf -- '%s' "$(_now_epoch)" > "${BEAT_LAST_FILE}.tmp.$$" 2>/dev/null \
  && mv -f "${BEAT_LAST_FILE}.tmp.$$" "$BEAT_LAST_FILE" 2>/dev/null || true

# BROAD-STATUS-RELAY-SCOPE-01 (round 2, HIGH-2): the session that armed this
# beat becomes its recorded owner ONLY if it actually has a live dispatched
# lane -- otherwise ownership would just be "whoever's --check won the
# throttle race", which is the original incident (a focused session with no
# lanes claims the beat and starves everyone else). Written when the hook
# told us which session armed it AND that session qualifies; any other case
# (no LEADV2_BEAT_OWNER_SESSION, resolver missing, no live lane) leaves the
# owner file untouched rather than recording an unqualified or empty owner.
# The read side (leadv2-beat-owner.sh's ladder) is authoritative regardless
# -- a bug in this write-side check can only under-grant, never over-grant,
# ownership, since a stale/absent owner file still resolves to "unresolved"
# (full relay) there.
if [[ -n "${LEADV2_BEAT_OWNER_SESSION:-}" ]]; then
  BEAT_OWNER_SH="${SCRIPT_DIR}/leadv2-beat-owner.sh"
  if [[ -f "$BEAT_OWNER_SH" ]]; then
    # shellcheck source=/dev/null
    source "$BEAT_OWNER_SH"
    if command -v leadv2_session_has_live_lane >/dev/null 2>&1 \
      && leadv2_session_has_live_lane "$LEADV2_BEAT_OWNER_SESSION" "$STATE_DIR" "$PROJECT_ROOT" 2>/dev/null; then
      BEAT_OWNER_FILE="${STATE_DIR}/.pulse-beat-owner"
      printf -- '%s %s' "$LEADV2_BEAT_OWNER_SESSION" "$(_now_epoch)" > "${BEAT_OWNER_FILE}.tmp.$$" 2>/dev/null \
        && mv -f "${BEAT_OWNER_FILE}.tmp.$$" "$BEAT_OWNER_FILE" 2>/dev/null || true
    fi
  fi
fi

_run_beat() {
  export LEADV2_BROAD_STATUS_DISPATCHED="unavailable"
  if [[ "${LEADV2_BACKLOG_PUMP:-1}" == "1" && -x "$PUMP_SH" ]]; then
    local pump_out dispatched_n
    pump_out="$(bash "$PUMP_SH" check 2>&1)" || true
    [[ -z "$pump_out" ]] || printf -- '%s\n' "$pump_out" >>"$LOG_FILE"
    dispatched_n="$(printf -- '%s\n' "$pump_out" \
      | sed -n 's/.*check complete:.*dispatched=\([0-9][0-9]*\).*/\1/p' | tail -n1)"
    export LEADV2_BROAD_STATUS_DISPATCHED="${dispatched_n:-unavailable}"
  fi
  local rc=0
  if [[ -x "$BROAD_STATUS_SH" ]]; then
    bash "$BROAD_STATUS_SH" >>"$LOG_FILE" 2>&1 || rc=$?
  else
    printf -- '%s [BROAD_STATUS] failure: composer unavailable (single-lead beat)\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$LOG_FILE"
    rc=1
  fi
  unset LEADV2_BROAD_STATUS_DISPATCHED
  return $rc
}

if [[ "$MODE" == "--now" ]]; then
  _prepare_transition_env
  _run_beat
  exit $?
fi

# --check: non-blocking flock so a second concurrent trigger just returns.
exec 9>"$BEAT_LOCK_FILE" || exit 0
if command -v flock >/dev/null 2>&1; then
  flock -n 9 || exit 0
fi

# PULSE-EMPTY-BOARD-01 coalescing: commit the transition state HERE, still
# under the flock — this is what makes a second --check that races in a
# moment later see "nothing new" (peek finds the baseline already
# advanced) and fall through to the normal throttle, instead of also
# winning a (by-then-released) flock and spawning a second render. The
# exported env is inherited by the --now child spawned below.
_prepare_transition_env

SELF="${BASH_SOURCE[0]}"
# PLUGIN-PAPERCUTS-01 (defect 1): stamp repo+lane into the watcher argv so a
# reparented orphan is attributable (and sweepable) safely. ${OWNER_TAG:+…}
# keeps an unresolvable tag byte-identical to the pre-fix bare spawn; the tag
# charset excludes spaces, so it cannot word-split.
OWNER_TAG="$(_beat_owner_tag)"
if command -v setsid >/dev/null 2>&1; then
  setsid nohup bash "$SELF" --now ${OWNER_TAG:+"--owner=$OWNER_TAG"} >/dev/null 2>&1 &
else
  nohup bash "$SELF" --now ${OWNER_TAG:+"--owner=$OWNER_TAG"} >/dev/null 2>&1 &
fi
disown 2>/dev/null || true
exit 0
