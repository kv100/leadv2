#!/usr/bin/env bash
# leadv2-backlog-pump.sh — BACKLOG-PUMP-01. Observes "capacity is free AND the
# queue is non-empty" and starts work — the mechanism that did not exist
# before this: every dispatch used to be lead-initiated, so throughput tracked
# whatever the lead's attention happened to be on.
#
# QUEUE SOURCE: docs/tasks.yaml via leadv2-tasks-lib.sh — NOT a second
# backlog. docs/ARCHITECTURE.md defines its top task as "next", so this pump
# uses leadv2_tasks_declared_top_n: eligible rows retain that stated plan order.
# It excludes human-needed, claimed, and blocked-by-deps rows.
#
# COMPOSITION (never bypassed, never re-implemented here):
#   - duplicate-signature refusal: leadv2-dispatch-code.sh owns the
#     task-signature ledger. This script calls it for every dispatch and
#     treats rc=2 (duplicate) as "skip, not a slot" — never re-derives sig
#     dedup itself.
#   - quota-driven arm selection (150c42f): leadv2-dispatch-code.sh's router
#     picks glm/sonnet/codex internally. This script's own quota-floor check
#     (below) is a DIFFERENT question — "should the pump start ANYTHING right
#     now" — not "which provider".
#   - lane-shape close requirements (87dac6a): `reap` reuses the identical
#     `git diff --name-only <base>...HEAD` emptiness check
#     leadv2-lane-shape.sh cmd_retro_check already uses, so "produced
#     nothing" is derived the same way in both places.
#   - outcome ledger (lane 0cf52efc, in flight, not yet merged at the time
#     this was written): if a sibling script LEADV2_OUTCOME_LEDGER_BIN (or
#     ${SCRIPT_DIR}/leadv2-outcome-ledger.sh) exists, `reap` prefers its
#     verdict over the git-diff heuristic below — forward-compatible, never
#     assumes its schema.
#
# BOUNDS (mission requirement — state every bound + what happens when it trips):
#   1. Master off switch: LEADV2_BACKLOG_PUMP=1 required to dispatch. Default
#      1; LEADV2_BACKLOG_PUMP=0 restores the pre-pump behaviour in one flip.
#   2. Concurrency cap: LEADV2_BACKLOG_PUMP_MAX (default: active.yaml
#      meta.hard_limit, else 3). At/over cap -> `check` exits 0, no dispatch,
#      logged "at_capacity".
#   3. Quota floor: LEADV2_BACKLOG_PUMP_QUOTA_FLOOR (default 10, percent). No
#      provider bucket has usable_now or remaining_pct >= floor -> `check`
#      refuses everything, logged "quota_floor".
#   4. Judgment-class exclusion: lane=human-needed is never even a candidate
#      (tasks-lib). A candidate that IS dispatched but resolves to arm=opus
#      (leadv2-dispatch-code.sh rc=3) is unclaimed and surfaced via
#      open-threads.md instead of retried — opus arm is lead/founder
#      judgment, never auto-dispatched (matches leadv2-dispatch-code.sh's own
#      documented contract).
#   5. Empty-outcome bound: `reap` requeues a task that closed with zero diff
#      ONCE (leadv2_tasks_unclaim keeps its attempt counter, so normal
#      max_attempts still applies); a SECOND consecutive empty close flips
#      lane to human-needed instead of requeuing again — a task can never
#      spin the pump forever.
#   6. Bounded scan: LEADV2_BACKLOG_PUMP_MAX_CANDIDATES (default 8) per
#      `check` invocation — a pathological queue can't turn one call into an
#      unbounded loop; the next poll cycle continues where this one stopped.
#   7. Lane accounting + async dispatch (fix2, SUPERVISOR-AUDIT-01
#      review-verdict-2 B5/NM1): every dispatch now reserves an active.yaml
#      lane (pid=null placeholder, same low-level register/unregister writer
#      leadv2-fanout.sh's Gate1 self-registration already uses) BEFORE the
#      dispatch call, so a LATER `check` invocation (e.g. the next throttled
#      hook tick) sees consumed capacity instead of re-dispatching past
#      MAX_CONCURRENT. The reservation is released on any non-success
#      dispatch outcome. LEADV2_BACKLOG_PUMP_ASYNC_DISPATCH (default 0) lets
#      a caller bound by a short host timeout (the pump-caller hook) opt
#      into backgrounding the dispatch call itself, via a detached
#      re-invocation of this script (`_async-dispatch`, setsid when
#      available) — the lane reservation is already committed by the time
#      `check` returns either way; only the wait for the dispatch call's own
#      completion is deferred. Default 0 leaves leadv2-supervise-loop.sh's
#      own periodic `check` call fully synchronous, unchanged.
#
# Usage:
#   leadv2-backlog-pump.sh check              # refill up to capacity; safe,
#                                                idempotent, called by
#                                                leadv2-supervise-loop.sh
#   leadv2-backlog-pump.sh dry-run [N]        # print next N candidates +
#                                                reason, priority order, NO
#                                                side effects (default 3)
#   leadv2-backlog-pump.sh status             # enabled/max/active/capacity
#   leadv2-backlog-pump.sh reap <task_id> [--base <ref>]
#                                              # call at lane close: detect
#                                                empty-outcome, requeue/park
#
# Env overrides (test sandboxing): LEADV2_PROJECT_ROOT / CLAUDE_PROJECT_DIR /
# PROJECT_ROOT — repo root. LEADV2_BACKLOG_PUMP_DISPATCH_BIN overrides the
# dispatch entry point (tests). LEADV2_BACKLOG_PUMP_QUOTA_BIN overrides the
# quota reader (tests — avoids coupling to this machine's real live quota).
# LEADV2_JOURNAL_BIN overrides the journal.
# Per-repo override: .claude/leadv2-overrides/backlog-pump.yaml — optional
# keys `enabled`, `max_concurrent`, `quota_floor_pct` (env always wins).

set -uo pipefail   # no -e: refusals must journal and continue, never abort

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="leadv2-backlog-pump"
# Absolute self-path (not a trusted ${BASH_SOURCE[0]}, which may be relative
# depending on how the caller invoked us) — used for the detached
# `_async-dispatch` re-invocation, fix2 below.
SELF="${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]}")"

log()     { printf -- '[%s] %s\n' "$SCRIPT_NAME" "$*" >&2; }
log_err() { printf -- '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2; }

# ── fail-closed root resolution (same order as leadv2-supervise.sh) ────────
PROJECT_ROOT=""
if [[ -n "${LEADV2_PROJECT_ROOT:-}" ]]; then
  PROJECT_ROOT="$LEADV2_PROJECT_ROOT"
elif [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  PROJECT_ROOT="$CLAUDE_PROJECT_DIR"
elif _lv2bp_top="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)"; then
  PROJECT_ROOT="$_lv2bp_top"
fi
if [[ -z "$PROJECT_ROOT" ]]; then
  log_err "root_error: could not resolve project root — set LEADV2_PROJECT_ROOT or CLAUDE_PROJECT_DIR"
  exit 1
fi
export LEADV2_PROJECT_ROOT="$PROJECT_ROOT"
export PROJECT_ROOT

# shellcheck source=leadv2-tasks-lib.sh
source "${SCRIPT_DIR}/leadv2-tasks-lib.sh"

# shellcheck source=leadv2-active-registry.sh
# active-registry.sh sets -e at its own top; this script's contract (see
# header comment above) is "no -e: refusals must journal and continue, never
# abort". `source` runs in THIS shell, so its `set -euo pipefail` would
# otherwise leak into every line below it — restore `set +e` immediately.
source "${SCRIPT_DIR}/leadv2-active-registry.sh"
set +e

JOURNAL_BIN="${LEADV2_JOURNAL_BIN:-${SCRIPT_DIR}/leadv2-journal.sh}"
DISPATCH_BIN="${LEADV2_BACKLOG_PUMP_DISPATCH_BIN:-${SCRIPT_DIR}/leadv2-dispatch-code.sh}"
JOURNAL_TASK="backlog-pump"

jemit() {  # $1=type $2..=text — never fails the caller
  local jtype="$1"; shift
  local line="$*"
  if [[ -f "${JOURNAL_BIN}" ]]; then
    bash "${JOURNAL_BIN}" append "${JOURNAL_TASK}" "${jtype}" "${line}" >/dev/null 2>&1 || true
  fi
  log "${line}"
}

OVERRIDE_YAML="${PROJECT_ROOT}/.claude/leadv2-overrides/backlog-pump.yaml"

_override() {  # $1=key $2=default -> value
  local key="$1" default="$2"
  [[ -f "$OVERRIDE_YAML" ]] || { printf '%s' "$default"; return; }
  local v
  v="$(grep -E "^[[:space:]]*${key}[[:space:]]*:" "$OVERRIDE_YAML" 2>/dev/null | head -1 \
       | sed -E "s/^[[:space:]]*${key}[[:space:]]*:[[:space:]]*//" \
       | sed -E "s/^['\"]//; s/['\"][[:space:]]*\$//" | tr -d '\r')"
  [[ -n "$v" && "$v" != "null" ]] && printf '%s' "$v" || printf '%s' "$default"
}

# ── config resolution: env > per-repo override > default ───────────────────
PUMP_ENABLED="${LEADV2_BACKLOG_PUMP:-$(_override enabled 1)}"

ACTIVE_YAML="$(PROJECT_ROOT="$PROJECT_ROOT" "${SCRIPT_DIR}/leadv2-state-path.sh" active.yaml 2>/dev/null)"

_active_hard_limit() {
  [[ -n "$ACTIVE_YAML" && -f "$ACTIVE_YAML" ]] || { printf '3'; return; }
  python3 -c "
import yaml, sys
try:
    d = yaml.safe_load(open(sys.argv[1])) or {}
except Exception:
    print(3); sys.exit(0)
print((d.get('meta') or {}).get('hard_limit', 3))
" "$ACTIVE_YAML" 2>/dev/null || printf '3'
}

# C-1 (LANE-CONCURRENCY-IN-PLUGIN, 2026-08-02): floor/ceiling are plugin-owned.
# The founder's ceiling (6) is enforced HERE in the plugin — not in active.yaml
# (meta.hard_limit, currently 5, which is the FANOUT cap) and not in a per-repo
# override. A per-repo yaml is exactly the kind of value that drifted before.
# resolved_max keeps today's chain (env > override max_concurrent > active.yaml
# hard_limit > 3); the clamp to [FLOOR, CEILING] is the new part. Any resolved
# value above CEILING is clamped and journalled once (R7: the deliberate
# pump/fanout cap divergence is visible, never silent).
CEILING="${LEADV2_BACKLOG_PUMP_CEILING:-6}"
FLOOR="${LEADV2_BACKLOG_PUMP_FLOOR:-3}"
QUOTA_FLOOR="${LEADV2_BACKLOG_PUMP_QUOTA_FLOOR:-$(_override quota_floor_pct 10)}"
QUOTA_FLOOR_BELOW="${LEADV2_BACKLOG_PUMP_QUOTA_FLOOR_BELOW:-2}"
RESERVATION_TTL_S="${LEADV2_BACKLOG_PUMP_RESERVATION_TTL_S:-600}"
REFUSAL_QUIET_S="${LEADV2_BACKLOG_PUMP_REFUSAL_QUIET_S:-900}"
MAX_CANDIDATES_BASE="${LEADV2_BACKLOG_PUMP_MAX_CANDIDATES:-8}"
# Numeric guard: a non-numeric override would abort Bash arithmetic under
# set -u. Fall back to the default rather than honor a malformed value.
[[ "$CEILING" =~ ^[0-9]+$ ]] || CEILING=6
[[ "$FLOOR" =~ ^[0-9]+$ ]] || FLOOR=3
[[ "$QUOTA_FLOOR" =~ ^[0-9]+$ ]] || QUOTA_FLOOR=10
[[ "$QUOTA_FLOOR_BELOW" =~ ^[0-9]+$ ]] || QUOTA_FLOOR_BELOW=2
[[ "$RESERVATION_TTL_S" =~ ^[0-9]+$ ]] || RESERVATION_TTL_S=600
[[ "$REFUSAL_QUIET_S" =~ ^[0-9]+$ ]] || REFUSAL_QUIET_S=900
[[ "$MAX_CANDIDATES_BASE" =~ ^[0-9]+$ ]] || MAX_CANDIDATES_BASE=8

_resolve_max_concurrent() {
  local resolved source_name
  resolved="${LEADV2_BACKLOG_PUMP_MAX:-$(_override max_concurrent "$(_active_hard_limit)")}"
  [[ "$resolved" =~ ^[0-9]+$ ]] || resolved=3
  if [[ -n "${LEADV2_BACKLOG_PUMP_MAX:-}" ]]; then
    source_name="env"
  elif [[ -f "$OVERRIDE_YAML" ]] && grep -qE '^[[:space:]]*max_concurrent[[:space:]]*:' "$OVERRIDE_YAML" 2>/dev/null; then
    source_name="override"
  else
    source_name="active.yaml"
  fi
  if (( resolved > CEILING )); then
    jemit decision "pump_ceiling_clamp resolved=${resolved} ceiling=${CEILING} source=${source_name}"
    resolved="$CEILING"
  elif (( resolved < FLOOR )); then
    resolved="$FLOOR"
  fi
  printf '%s' "$resolved"
}
MAX_CONCURRENT="$(_resolve_max_concurrent)"

# Pump-owned cache + sidecar map. CACHE_DIR mirrors the empty-streak cache's
# project-scoped ${PROJECT_ROOT}/.claude/cache location.
CACHE_DIR="${PROJECT_ROOT}/.claude/cache/backlog-pump"
LANE_MAP_DIR="${CACHE_DIR}/backlog-pump-lane-map"
LIVENESS_BIN="${LEADV2_BACKLOG_PUMP_LIVENESS_BIN:-${SCRIPT_DIR}/leadv2-lane-liveness.sh}"
LIVENESS_CACHE_S="${LEADV2_BACKLOG_PUMP_LIVENESS_CACHE_S:-15}"
QUOTA_SHAPE_BIN="${SCRIPT_DIR}/lib/leadv2-quota-shape.py"

_active_count() {  # raw active.yaml session count — a COMPONENT of the live count
  [[ -n "$ACTIVE_YAML" && -f "$ACTIVE_YAML" ]] || { printf '0'; return; }
  python3 -c "
import yaml, sys
try:
    d = yaml.safe_load(open(sys.argv[1])) or {}
except Exception:
    print(0); sys.exit(0)
print(len(d.get('sessions') or []))
" "$ACTIVE_YAML" 2>/dev/null || printf '0'
}

_active_task_ids() {
  [[ -n "$ACTIVE_YAML" && -f "$ACTIVE_YAML" ]] || return 0
  python3 -c "
import yaml, sys
try:
    d = yaml.safe_load(open(sys.argv[1])) or {}
except Exception:
    sys.exit(0)
for s in (d.get('sessions') or []):
    tid = s.get('task_id')
    if tid: print(tid)
" "$ACTIVE_YAML" 2>/dev/null
}

# ── C-1: live lane counting (replaces _active_count as the truth source) ────
# _active_count() above is 0 by construction for the dominant dispatch path:
# leadv2-dispatch-code.sh never registers an active.yaml session, so every lane
# it spawns is structurally invisible to a count built on active.yaml. A floor
# built on _active_count() computes cap=3-0=3 while 4 lanes run and
# over-dispatches. The live count is the UNION of two identity spaces joined by
# a pump-owned sidecar map:
#   - leadv2-lane-liveness.sh lanes (id = dispatch-<sig8>): child_of == null and
#     verdict not dead:* occupy a slot (alive / starting / silent:* all count;
#     only terminal dead:silent_*_abandoned frees a slot).
#   - active.yaml reservations (id = task_id): counted when not yet joined to a
#     lane id and younger than RESERVATION_TTL_S; swept when older.
# Quota reader outage -> fail OPEN (pass); lane-count outage -> fail CLOSED
# (refuse the tick). Deliberately opposite: unknown quota risks one job, an
# unknown count risks over-dispatch (R1).

# Newest mtime among handoff lane dirs — the count-cache invalidation key. A
# brand-new lane bumps this and invalidates a stale count within the 15 s window.
_lane_cache_signature() {
  local newest=0 t d
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    t="$(stat -f %m "$d" 2>/dev/null || stat -c %Y "$d" 2>/dev/null || echo 0)"
    [[ "$t" =~ ^[0-9]+$ ]] || t=0
    (( t > newest )) && newest=$t
  done < <(find "${PROJECT_ROOT}/docs/handoff" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
  printf '%s' "$newest"
}

# Prints liveness JSON on stdout (cached 15 s, mtime-keyed), or returns 1 and
# sets LANE_LIVENESS_FAILED=1 on a fresh-call failure (no usable cache).
_resolve_liveness_json() {
  LANE_LIVENESS_FAILED=0
  local cache="${CACHE_DIR}/liveness.json" sigfile="${CACHE_DIR}/liveness.sig" tsfile="${CACHE_DIR}/liveness.ts"
  local sig now cached_sig cached_ts
  sig="$(_lane_cache_signature)"
  now="$(date +%s)"
  if [[ -f "$cache" && -f "$sigfile" && -f "$tsfile" ]]; then
    cached_sig="$(cat "$sigfile" 2>/dev/null || printf 'none')"
    cached_ts="$(cat "$tsfile" 2>/dev/null || printf '0')"
    [[ "$cached_ts" =~ ^[0-9]+$ ]] || cached_ts=0
    if [[ "$cached_sig" == "$sig" ]] && (( now - cached_ts < LIVENESS_CACHE_S )); then
      cat "$cache" 2>/dev/null && return 0
    fi
  fi
  local raw rc=0
  # --no-codex: the codex probe is a network call; codex lanes still appear via
  #   their handoff dir like every other lane. Bound the scan at 20 s; `timeout`
  #   is GNU coreutils (absent on stock macOS) -> fall back to gtimeout, else
  #   run unbounded (the liveness binary self-limits) rather than fail closed
  #   on a host that simply lacks the helper.
  local tbin=""
  if command -v timeout >/dev/null 2>&1; then tbin="timeout"
  elif command -v gtimeout >/dev/null 2>&1; then tbin="gtimeout"; fi
  if [[ -n "$tbin" ]]; then
    raw="$("$tbin" 20 bash "$LIVENESS_BIN" --all --json --no-codex 2>/dev/null)" || rc=$?
  else
    raw="$(bash "$LIVENESS_BIN" --all --json --no-codex 2>/dev/null)" || rc=$?
  fi
  if [[ "$rc" -ne 0 || -z "$raw" ]]; then
    LANE_LIVENESS_FAILED=1
    return 1
  fi
  mkdir -p "$CACHE_DIR" 2>/dev/null || true
  printf '%s' "$raw" >"$cache" 2>/dev/null || true
  printf '%s' "$sig" >"$sigfile" 2>/dev/null || true
  printf '%s' "$now" >"$tsfile" 2>/dev/null || true
  printf '%s' "$raw"
}

# Prints three lines: count | space-joined names | comma-joined stale reservations
# (tid=age_s). Lane ids and unjoined fresh reservations both count toward total.
# Returns nonzero (-> caller fails CLOSED) when the liveness JSON is unparseable:
# an uncountable queue must not become an over-dispatch (R1).
_live_lane_count() {
  local lj
  lj="$(_resolve_liveness_json)" || return 1
  python3 - "$lj" "$ACTIVE_YAML" "$LANE_MAP_DIR" "$RESERVATION_TTL_S" "$(date +%s)" <<'PY'
import json, sys, os, re, datetime
lj, ay, mapdir, ttl, now = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5])

# Source 1: live liveness lanes. Strict — a malformed/shape-wrong payload from
# our own liveness binary is a "stop, don't guess" condition, not a zero count.
try:
    d = json.loads(lj)
except Exception:
    sys.exit(2)   # unparseable liveness -> fail closed
arr = d.get('lanes') if isinstance(d, dict) else d
if not isinstance(arr, list):
    sys.exit(2)   # unexpected shape -> fail closed
names = []
live_ids = set()
for l in arr:
    if not isinstance(l, dict):
        continue
    if l.get('child_of'):              # child lanes ride a parent's slot
        continue
    v = str(l.get('verdict') or '')
    # Only the PROVEN-terminal family frees a slot. Other dead:* verdicts
    # (e.g. dead:log_stat_failed) are probe errors -> uncertain -> count the
    # slot as occupied (safer: never over-dispatch on an uncertain liveness).
    if v.startswith('dead:silent_'):
        continue
    lid = l.get('lane')
    if lid:
        names.append(str(lid))
        live_ids.add(str(lid))

# Source 2: active.yaml reservations not yet joined to a live lane id.
stale = []
if ay and os.path.exists(ay):
    try:
        import yaml
        ad = yaml.safe_load(open(ay)) or {}
        for s in (ad.get('sessions') or []):
            tid = s.get('task_id')
            if not tid:
                continue
            mapfile = os.path.join(mapdir, str(tid).replace('/', '_'))
            if os.path.exists(mapfile):
                # Joined only if its mapped lane is CURRENTLY live — a stale map
                # whose lane has died must not suppress a fresh reservation.
                try:
                    mapped = open(mapfile).read().strip()
                except Exception:
                    mapped = ''
                if mapped in live_ids:
                    continue
            sa = s.get('started_at') or ''
            ep = None
            m = re.match(r'(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})', sa)
            if m:
                try:
                    ep = int(datetime.datetime(*(int(m.group(i)) for i in range(1, 7)),
                                               tzinfo=datetime.timezone.utc).timestamp())
                except Exception:
                    ep = None
            if ep is None:
                names.append('res:' + str(tid))   # unparseable age -> count (fail safe)
                continue
            age = now - ep
            if age < ttl:
                names.append('res:' + str(tid))
            else:
                stale.append('%s=%d' % (tid, age))
    except Exception:
        pass   # active.yaml unreadable: reservations uncounted (under-count, safer)
print(len(names))
print(' '.join(names))
print(','.join(stale))
PY
}

# Sets globals LANE_COUNT, LANE_NAMES. Sweeps stale reservations (R2/TTL).
# Returns 1 (LANE_COUNT empty) when the liveness probe failed — caller fails closed.
_read_lane_state() {
  LANE_COUNT=""; LANE_NAMES=""
  local out
  out="$(_live_lane_count)" || return 1
  LANE_COUNT="$(printf '%s' "$out" | sed -n '1p')"
  LANE_NAMES="$(printf '%s' "$out" | sed -n '2p')"
  local stale; stale="$(printf '%s' "$out" | sed -n '3p')"
  if [[ -n "$stale" ]]; then
    local _ifs="$IFS"; IFS=','
    local pair tid age_s
    for pair in $stale; do
      [[ -z "$pair" ]] && continue
      tid="${pair%%=*}"; age_s="${pair#*=}"
      _pump_release_lane "$tid"
      jemit decision "pump_swept_stale_reservation task=${tid} age_s=${age_s}"
    done
    IFS="$_ifs"
  fi
  return 0
}

# Below-floor sentinel read by the pump-caller hook to shorten its throttle
# (180 s -> 45 s) so an idle session recovers toward the floor in one lead turn,
# not 3 min. The file's own mtime ages it out if the pump stops touching it.
_set_below_floor_sentinel() {  # $1=1 set, else clear
  local bf="${1:-0}"
  local f="${CACHE_DIR}/backlog-pump-below-floor"
  mkdir -p "$CACHE_DIR" 2>/dev/null || true
  if [[ "$bf" == "1" ]]; then
    : >"$f" 2>/dev/null || true
  else
    rm -f "$f" 2>/dev/null || true
  fi
}

# ── C-1: refusal dedupe (legibility — A1/A5) ────────────────────────────────
# State: reason|digest|first_iso|first_epoch|count in ${CACHE_DIR}/backlog-pump-refusal-state.
# digest = sha1(reason + 5%-bucketed measured numbers) so ordinary drift does
# not defeat the dedupe but a material change re-emits. pump_dispatched and
# pump_starved are NEVER suppressed (call jemit directly).
_refuse_with_dedupe() {  # $1=reason  $2..=measured key=value pairs (e.g. "glm=32% codex=83% floor=10% live=2")
  local reason="$1"; shift
  local nums="$*"
  local bucketed digest
  bucketed="$(printf '%s' "$nums" | python3 -c '
import sys, re
def b(m):
    try:
        return "%s=%d%%" % (m.group(1), int(round(float(m.group(2)) / 5.0) * 5))
    except Exception:
        return m.group(0)
sys.stdout.write(re.sub(r"([a-zA-Z_]+)=([0-9.]+)%?", b, sys.stdin.read()))
' 2>/dev/null)" || bucketed="$nums"
  digest="$(printf '%s|%s' "$reason" "$bucketed" | shasum | awk '{print $1}')"
  local state="${CACHE_DIR}/backlog-pump-refusal-state"
  local now_iso now_epoch
  now_iso="$(date -u +%Y-%m-%dT%H:%MZ)"
  now_epoch="$(date +%s)"
  # State: reason|digest|burst_first_iso|burst_first_epoch|count_since_emit
  # A "burst" is the run of identical refusals since the last EMITTED line.
  local pr="" pd="" bf_iso="$now_iso" bf_epoch="$now_epoch" count=0
  if [[ -f "$state" ]]; then
    IFS='|' read -r pr pd bf_iso bf_epoch count <"$state" 2>/dev/null || true
  fi
  [[ "$bf_iso" =~ ^[0-9] ]] || bf_iso="$now_iso"
  [[ "$bf_epoch" =~ ^[0-9]+$ ]] || bf_epoch="$now_epoch"
  local is_new=0
  [[ "$reason" != "$pr" || "$digest" != "$pd" ]] && is_new=1
  # A reason/digest change starts a FRESH burst — never carry the previous
  # burst's counter or timestamp into the new reason's first line.
  if [[ "$is_new" == "1" ]]; then
    bf_iso="$now_iso"; bf_epoch="$now_epoch"; count=0
  fi
  count=$((count + 1))   # THIS occurrence is part of the burst
  local expired=0
  (( now_epoch - bf_epoch >= REFUSAL_QUIET_S )) && expired=1
  if [[ "$is_new" == "1" || "$expired" == "1" ]]; then
    # New reason, or the quiet window elapsed since this burst began: emit ONE
    # line carrying the burst's count + the measured numbers, then reset.
    jemit decision "pump_refused reason=${reason} ${nums} repeats=${count} since=${bf_iso}"
    printf '%s|%s|%s|%s|%s' "$reason" "$digest" "$now_iso" "$now_epoch" "0" >"$state" 2>/dev/null || true
  else
    # Same reason+digest inside the quiet window: suppress the journal write
    # (a broken parse and a real exhaustion still render identically to the
    # next reader, but the journal no longer floods 4x/minute for hours).
    printf '%s|%s|%s|%s|%s' "$reason" "$digest" "$bf_iso" "$bf_epoch" "$count" >"$state" 2>/dev/null || true
    log "pump_refused (suppressed) reason=${reason} ${nums} repeats=${count} since=${bf_iso}"
  fi
}

# Serialize checks per project so concurrent supervise ticks cannot both see
# and consume the same free slot. mkdir is an atomic portable lock primitive.
PUMP_LOCK_DIR="/tmp/leadv2-backlog-pump-$(printf '%s' "$PROJECT_ROOT" | shasum | awk '{print $1}').lock"
PUMP_LOCK_HELD=0
_release_pump_lock() {
  [[ "$PUMP_LOCK_HELD" == "1" ]] && rmdir "$PUMP_LOCK_DIR" 2>/dev/null || true
  PUMP_LOCK_HELD=0
}
_acquire_pump_lock() {
  if mkdir "$PUMP_LOCK_DIR" 2>/dev/null; then
    PUMP_LOCK_HELD=1
    trap _release_pump_lock EXIT
    return 0
  fi
  return 1
}

# Fail closed when Git reports an unfinished merge/rebase/cherry-pick or
# unmerged index entries. Refusing a refill is safer than an ambiguous tree.
_tree_mid_conflict() {
  git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local ref
  for ref in MERGE_HEAD REBASE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
    git -C "$PROJECT_ROOT" rev-parse -q --verify "$ref" >/dev/null 2>&1 && return 0
  done
  git -C "$PROJECT_ROOT" ls-files -u 2>/dev/null | grep -q . && return 0
  return 1
}

# ── quota headroom: at least one provider bucket's BINDING WINDOW must clear
# the floor. C-1: the old gate read usable_now/remaining_pct at the bucket TOP
# level — those keys live INSIDE each provider's binding window, so it fell
# through every loop and refused unconditionally while every provider sat at
# 33–84 % remaining. The shape now lives once in scripts/lib/leadv2-quota-shape.py
# (mirroring leadv2-router-v2.py:bucket_usable_now); fail-open is preserved: an
# unparseable/unreachable payload PASSES (a quota-reader outage must not become a
# dispatch outage). Sets QUOTA_NUMS for the journal on any reachable verdict.
_quota_ok() {  # $1=floor (defaults to QUOTA_FLOOR) -> rc 0 ok, nonzero refuse
  local floor="${1:-$QUOTA_FLOOR}"
  QUOTA_NUMS=""
  local qbin="${LEADV2_BACKLOG_PUMP_QUOTA_BIN:-${SCRIPT_DIR}/leadv2-quota-live.sh}"
  if [[ ! -x "$QUOTA_SHAPE_BIN" ]]; then
    return 0   # shape module absent (stripped env) -> fail-open
  fi
  local json out rc=0
  if [[ -x "$qbin" ]]; then
    json="$(bash "$qbin" json 2>/dev/null)" || json=""
    out="$(printf '%s' "$json" | python3 "$QUOTA_SHAPE_BIN" gate --floor "$floor" --stdin 2>/dev/null)" || rc=$?
  else
    out="$(python3 "$QUOTA_SHAPE_BIN" gate --floor "$floor" --stdin </dev/null 2>/dev/null)" || rc=$?
  fi
  QUOTA_NUMS="$(printf '%s' "$out" | sed -E 's/ floor=.*//; s/ verdict=.*//' 2>/dev/null)"
  # The gate's EXIT CODE is the verdict: 0 = pass, 1 = refuse (it fail-opens
  # internally and returns 0 on unparseable/unreachable). So decide on rc, not
  # on string matching: rc=1 refuses; rc=0 PASSES; any other rc (helper crashed
  # / printed nothing) fail-OPENS to pass — a quota-reader outage must not
  # become a dispatch outage (the bug that ran all night). NB: capturing out via
  # $(...) would otherwise wipe the output on the rc=1 refuse and invert the
  # verdict, so rc is captured explicitly and never used to blank `out`.
  case "$rc" in
    1) return 1 ;;
    *) return 0 ;;
  esac
}

_mission_for_task() {  # $1=task_id -> mission text (title + note), empty if not found
  local tid="$1" row
  row="$(leadv2_tasks_by_id "$tid" 2>/dev/null)" || { printf ''; return; }
  python3 -c "
import yaml, sys
items = yaml.safe_load(sys.argv[1]) or []
it = items[0] if items else {}
# NB2 fix (SUPERVISOR-AUDIT-01 fix-round-3): persona-engine's live tasks.yaml
# rows carry no literal 'title' column at all (0/372) -- 282/296 queued rows
# instead carry 'intent', a human-written one-liner (same schema gap
# leadv2-fanout.sh's task_title() already works around). Falling back to
# intent here is what makes the pump's dispatched mission text non-empty for
# that generator's rows instead of silently becoming the bare task id.
title = it.get('title') or it.get('intent') or ''
note = it.get('note', '')
origin = it.get('origin', '')
parts = [p for p in (title, note) if p]
if origin:
    parts.append(f'(origin: {origin})')
print(' — '.join(parts) if parts else title)
" "$row" 2>/dev/null
}

# ── active.yaml lane reservation (fix2, SUPERVISOR-AUDIT-01 review-verdict-2
# B5/NM1) ─────────────────────────────────────────────────────────────────
# Uses leadv2-active-registry.sh's low-level register/unregister/update_pid
# ops directly (bypassing leadv2_active_register(), which always fills
# pid=<caller's own durable pid> and has no null-pid mode) so a pump
# dispatch can reserve a lane with a pid=null placeholder BEFORE the worker
# exists — the SAME writer, and the same placeholder-then-update shape,
# leadv2-fanout.sh's single-worker funnel already uses for its own
# dispatch-code.sh launches.
_pump_reserve_lane() {  # $1=task_id -> rc 0 reserved, nonzero=failed (fail closed, no dispatch)
  local tid="$1" yaml_file lockfile session_id ts branch pulse_log
  yaml_file="$(_leadv2_yaml_file)"
  lockfile="$(_leadv2_yaml_lockfile)"
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  branch="$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || printf -- 'unknown')"
  session_id="p-$(date -u +%Y%m%dT%H%M%SZ)-null-$$"
  pulse_log="docs/handoff/backlog-pump-${tid}/pulse.md"
  _leadv2_yaml_py_lock \
    "$lockfile" "$yaml_file" register \
    "$session_id" "$tid" "$PROJECT_ROOT" "$branch" "$ts" \
    "spawning" "backlog-pump" "null" "null" "null" \
    "true" "$ts" "$pulse_log" "" ""
}

_pump_update_lane_pid() {  # $1=task_id $2=pid_or_null -- best-effort, never fails the caller
  local tid="$1" pid_val="$2" yaml_file lockfile
  yaml_file="$(_leadv2_yaml_file)"
  lockfile="$(_leadv2_yaml_lockfile)"
  [[ -f "$yaml_file" ]] || return 0
  _leadv2_yaml_py_lock "$lockfile" "$yaml_file" update_pid "$tid" "$pid_val" >/dev/null 2>&1 || true
}

_pump_release_lane() {  # $1=task_id -- never fails the caller
  leadv2_active_unregister "$1" >/dev/null 2>&1 || true
}

# cmd_async_dispatch — runs the actual dispatch call + its outcome handling
# (pid-fill on success, task-unclaim + lane-release on anything else). The
# lane reservation for $1 must ALREADY exist (written by the caller via
# _pump_reserve_lane) before this runs. Callable either inline (synchronous
# default) or as a detached re-invocation of this script (async opt-in,
# MODE=_async-dispatch below) -- same function, same outcome semantics
# either way, so the two modes can never drift apart.
# rc: 0 = dispatched, nonzero = not (lane + claim already released).
cmd_async_dispatch() {  # $1=task_id $2=mission $3=lane $4=priority $5=rank (last 3 optional, logging only)
  local tid="$1" mission="$2" lane="${3:-}" priority="${4:-}" rank="${5:-}"
  local rc=0 dc_out=""
  dc_out="$(bash "$DISPATCH_BIN" "$mission" --kind "backlog-pump" 2>&1)" || rc=$?

  case "$rc" in
    0)
      # Only the sonnet arm's handle is a real OS pid (dispatch-code.sh
      # normalizes it to bare "PID=<n>"); glm/codex handles are provider-
      # internal run/job ids, not killable pids -- leave pid=null for those
      # (same convention leadv2-fanout.sh's funnel uses for this exact case).
      local handle pid_val extracted_pid lane_sig
      handle="$(printf '%s\n' "$dc_out" | sed -n 's/.*worker_spawned .*handle=\(.*\)$/\1/p' | tail -1)"
      pid_val="null"
      extracted_pid="$(printf '%s' "$handle" | sed -n 's/^PID=\([0-9][0-9]*\).*/\1/p')"
      [[ -n "$extracted_pid" ]] && pid_val="$extracted_pid"
      # C-1 sidecar join: parse the dispatch-<sig8> id dispatch-code.sh already
      # prints on this same worker_spawned line and record task_id->lane_id so
      # _live_lane_count() can stop counting this task as an unjoined
      # reservation. Pump-owned sidecar (NOT an active.yaml schema change) so it
      # cannot collide with W-1's registry work. No new contract from W-1: if
      # dispatch-code.sh stops printing this line, the map degrades to
      # "unjoined reservation" and the TTL sweep handles it — never over-dispatch.
      lane_sig="$(printf '%s\n' "$dc_out" | sed -n 's/.*worker_spawned .* task=\([^ ]*\).*/\1/p' | tail -1)"
      if [[ -n "$lane_sig" ]]; then
        mkdir -p "$LANE_MAP_DIR" 2>/dev/null || true
        printf '%s' "dispatch-${lane_sig}" >"${LANE_MAP_DIR}/${tid//\//_}" 2>/dev/null || true
      fi
      _pump_update_lane_pid "$tid" "$pid_val"
      jemit decision "pump_dispatched task=${tid} lane=${lane} priority=${priority} reason=declared_plan_order rank=${rank}"
      return 0
      ;;
    2)
      jemit decision "pump_skip task=${tid} reason=duplicate_task_signature"
      leadv2_tasks_unclaim "$tid" >/dev/null 2>&1 || true
      _pump_release_lane "$tid"
      return 2
      ;;
    3)
      jemit decision "pump_deferred_to_founder task=${tid} reason=opus_arm_requires_judgment"
      leadv2_tasks_unclaim "$tid" >/dev/null 2>&1 || true
      _pump_release_lane "$tid"
      _surface_to_founder "$tid" "requires judgment (opus arm) — pump will not auto-start this"
      return 3
      ;;
    *)
      jemit decision "pump_skip task=${tid} reason=spawn_failed rc=${rc}"
      leadv2_tasks_unclaim "$tid" >/dev/null 2>&1 || true
      _pump_release_lane "$tid"
      return 1
      ;;
  esac
}

cmd_status() {
  local active cap names
  if _read_lane_state; then
    active="$LANE_COUNT"
    names="$LANE_NAMES"
  else
    # Liveness probe failed: fall back to the raw active.yaml count and say so,
    # never invent active=0 while lanes are visibly working (A2).
    active="$(_active_count)"
    names="(liveness_unavailable active.yaml_fallback)"
  fi
  cap=$(( MAX_CONCURRENT - active ))
  (( cap < 0 )) && cap=0
  printf 'enabled=%s max_concurrent=%s active=%s capacity=%s quota_floor=%s%% floor=%s ceiling=%s lanes=%s\n' \
    "$PUMP_ENABLED" "$MAX_CONCURRENT" "$active" "$cap" "$QUOTA_FLOOR" "$FLOOR" "$CEILING" "$names"
}

cmd_dry_run() {
  local n="${1:-3}"
  local active cap
  if _read_lane_state; then active="$LANE_COUNT"; else active="$(_active_count)"; fi
  cap=$(( MAX_CONCURRENT - active ))
  (( cap < 0 )) && cap=0
  local raw
  raw="$(leadv2_tasks_declared_top_n "$MAX_CANDIDATES_BASE" 2>/dev/null || true)"
  if [[ -z "$raw" ]]; then
    printf 'queue empty — nothing would start\n'
    return 0
  fi
  local i=0
  while IFS=$'\t' read -r lane priority iid title; do
    [[ "$lane" == "-" ]] && lane=""  # NB2: "-" is tasks-lib.sh's empty-lane marker
    [[ -z "$iid" ]] && continue
    i=$((i + 1))
    (( i > n )) && break
    if (( i <= cap )); then
      printf '%d. %s [%s/%s] %s — would dispatch: next in declared plan order, capacity available (%d/%d slots free)\n' \
        "$i" "$iid" "$lane" "$priority" "$title" "$cap" "$MAX_CONCURRENT"
    else
      printf '%d. %s [%s/%s] %s — would NOT dispatch yet: no free capacity (%d/%d in use)\n' \
        "$i" "$iid" "$lane" "$priority" "$title" "$active" "$MAX_CONCURRENT"
    fi
  done <<<"$raw"
}

cmd_check() {
  if [[ "$PUMP_ENABLED" != "1" ]]; then
    log "disabled (LEADV2_BACKLOG_PUMP=0) — no-op"
    return 0
  fi

  if ! _acquire_pump_lock; then
    jemit decision "pump_refused reason=check_in_progress"
    return 0
  fi

  if _tree_mid_conflict; then
    jemit decision "pump_refused reason=tree_mid_conflict"
    return 0
  fi

  local active cap
  if ! _read_lane_state; then
    # Fail CLOSED on counting (R1): an unknown count risks over-dispatch. The
    # quota reader outage fails open; the count outage fails closed — opposite,
    # deliberately.
    _refuse_with_dedupe lane_count_unavailable "floor=${QUOTA_FLOOR}pct"
    return 0
  fi
  active="$LANE_COUNT"
  cap=$(( MAX_CONCURRENT - active ))
  if (( cap <= 0 )); then
    _set_below_floor_sentinel 0
    _refuse_with_dedupe at_ceiling "live=${active} ceiling=${MAX_CONCURRENT} source=plugin_default"
    return 0
  fi

  # C-1 floor: when fewer than FLOOR lanes run, keep them alive until quota is
  # genuinely near-exhausted (QUOTA_FLOOR_BELOW, default 2%), not merely below a
  # comfort margin, and widen the candidate scan so a queue whose first rows all
  # lose claim races cannot leave the floor unmet.
  local below_floor=0 eff_floor="$QUOTA_FLOOR" eff_max_cand="$MAX_CANDIDATES_BASE"
  if (( active < FLOOR )); then
    below_floor=1
    eff_floor="$QUOTA_FLOOR_BELOW"
    local _floor_scan=$(( FLOOR * 3 ))
    (( _floor_scan > eff_max_cand )) && eff_max_cand="$_floor_scan"
  fi

  if ! _quota_ok "$eff_floor"; then
    if (( below_floor == 1 )); then
      _refuse_with_dedupe quota_floor "${QUOTA_NUMS} floor=${eff_floor}pct live=${active} bar=below_floor"
    else
      _refuse_with_dedupe quota_floor "${QUOTA_NUMS} floor=${QUOTA_FLOOR}pct live=${active}"
    fi
    return 0
  fi

  local raw
  raw="$(leadv2_tasks_declared_top_n "$eff_max_cand" 2>/dev/null || true)"
  if [[ -z "$raw" ]]; then
    if (( below_floor == 1 )); then
      # An idle session with an empty queue and one with a broken gate must NOT
      # render identically (A3 vs A1). pump_starved is never dedupe-suppressed.
      _set_below_floor_sentinel 0
      jemit decision "pump_starved reason=queue_empty live=${active} floor=${FLOOR}"
    else
      log "queue empty — nothing to pump"
    fi
    return 0
  fi

  # Below-floor recovery: signal the pump-caller hook to shorten its throttle so
  # the floor is re-checked in ~45 s, not 3 min.
  _set_below_floor_sentinel "$below_floor"

  local running_ids; running_ids="$(_active_task_ids)"
  local examined=0 dispatched=0
  # Bound #7: off by default -- leadv2-supervise-loop.sh's own periodic
  # `check` call stays fully synchronous, unchanged.
  local ASYNC_DISPATCH="${LEADV2_BACKLOG_PUMP_ASYNC_DISPATCH:-0}"

  while IFS=$'\t' read -r lane priority iid title; do
    [[ "$lane" == "-" ]] && lane=""  # NB2: "-" is tasks-lib.sh's empty-lane marker
    [[ -z "$iid" ]] && continue
    (( cap <= 0 )) && break
    examined=$((examined + 1))
    (( examined > eff_max_cand )) && break

    if grep -qxF "$iid" <<<"$running_ids" 2>/dev/null; then
      log "skip ${iid}: already running (race guard)"
      continue
    fi

    if ! leadv2_tasks_claim "$iid" --by "backlog-pump" >/dev/null 2>&1; then
      jemit decision "pump_skip task=${iid} reason=claim_race"
      continue
    fi

    # Bound #7: reserve the active.yaml lane BEFORE any dispatch attempt --
    # a failed reservation is treated as a capacity refusal (fail closed),
    # never as "proceed without a registry row" (that fail-open shape is the
    # exact defect NB1 flags in leadv2-fanout.sh; not repeated here).
    if ! _pump_reserve_lane "$iid" >/dev/null 2>&1; then
      jemit decision "pump_skip task=${iid} reason=lane_reserve_failed"
      leadv2_tasks_unclaim "$iid" >/dev/null 2>&1 || true
      continue
    fi

    local mission; mission="$(_mission_for_task "$iid")"
    if [[ -z "$mission" ]]; then
      mission="$title"
    fi

    if [[ "$ASYNC_DISPATCH" == "1" ]]; then
      # Properly async (fix2 NM1): the lane above is already committed: only
      # the dispatch call's own completion is deferred, via a detached
      # re-invocation of this script so a host-timeout-bound caller (the
      # pump-caller hook) never waits on it. setsid (when available) detaches
      # from the caller's process group so a later host kill of the caller
      # cannot also kill this in-flight child.
      if command -v setsid >/dev/null 2>&1; then
        setsid bash "$SELF" _async-dispatch "$iid" "$mission" "$lane" "$priority" "$examined" </dev/null >/dev/null 2>&1 &
      else
        bash "$SELF" _async-dispatch "$iid" "$mission" "$lane" "$priority" "$examined" </dev/null >/dev/null 2>&1 &
      fi
      disown
      dispatched=$((dispatched + 1))
      cap=$((cap - 1))
      continue
    fi

    if cmd_async_dispatch "$iid" "$mission" "$lane" "$priority" "$examined"; then
      dispatched=$((dispatched + 1))
      cap=$((cap - 1))
    fi
  done <<<"$raw"

  log "check complete: examined=${examined} dispatched=${dispatched} live=${active} remaining_capacity=${cap} below_floor=${below_floor}"
}

_surface_to_founder() {  # $1=task_id $2=reason -> append to open-threads.md
  local iid="$1" reason="$2"
  local threads; threads="$(PROJECT_ROOT="$PROJECT_ROOT" "${SCRIPT_DIR}/leadv2-state-path.sh" open-threads.md 2>/dev/null)"
  [[ -n "$threads" ]] || return 0
  printf -- '- [ ] %s — backlog-pump: task %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$iid" "$reason" >>"$threads" 2>/dev/null || true
}

# ── reap: detect empty-outcome close, bound the retry, never spin forever ──
EMPTY_STREAK_DIR="${PROJECT_ROOT}/.claude/cache/backlog-pump-empty-streak"

cmd_reap() {
  local tid="${1:?reap requires <task_id>}"; shift || true
  local base="main"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base) base="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  # Forward-compat: prefer the outcome ledger's own verdict once it exists.
  local outcome_bin="${LEADV2_OUTCOME_LEDGER_BIN:-${SCRIPT_DIR}/leadv2-outcome-ledger.sh}"
  local is_empty=""
  if [[ -x "$outcome_bin" ]]; then
    local v
    v="$(bash "$outcome_bin" status "$tid" 2>/dev/null || true)"
    case "$v" in
      *empty*|*produced_nothing*) is_empty=1 ;;
      *) is_empty="" ;;
    esac
  fi

  if [[ -z "$is_empty" ]]; then
    local files
    files="$(git -C "$PROJECT_ROOT" diff --name-only "${base}...HEAD" 2>/dev/null || true)"
    [[ -z "$files" ]] && is_empty=1
  fi

  if [[ -z "$is_empty" ]]; then
    log "reap ${tid}: non-empty outcome — nothing to do"
    return 0
  fi

  mkdir -p "$EMPTY_STREAK_DIR" 2>/dev/null || true
  local streak_file="${EMPTY_STREAK_DIR}/${tid//\//_}"
  local streak=0
  [[ -f "$streak_file" ]] && streak="$(cat "$streak_file" 2>/dev/null || echo 0)"
  streak=$((streak + 1))

  if (( streak >= 2 )); then
    jemit decision "pump_reap task=${tid} outcome=empty streak=${streak} action=parked_human_needed"
    leadv2_tasks_update "$tid" --key lane --value human-needed >/dev/null 2>&1 || true
    _surface_to_founder "$tid" "closed empty ${streak}x in a row — parked, will not auto-retry"
    rm -f "$streak_file" 2>/dev/null || true
  else
    jemit decision "pump_reap task=${tid} outcome=empty streak=${streak} action=requeued"
    leadv2_tasks_unclaim "$tid" >/dev/null 2>&1 || true
    printf '%s' "$streak" >"$streak_file" 2>/dev/null || true
  fi
}

# ── dispatch ─────────────────────────────────────────────────────────────────
MODE="${1:-check}"
shift || true
case "$MODE" in
  check)    cmd_check "$@" ;;
  dry-run)  cmd_dry_run "$@" ;;
  status)   cmd_status "$@" ;;
  reap)     cmd_reap "$@" ;;
  # Internal only (fix2, SUPERVISOR-AUDIT-01 B5/NM1): the detached-child
  # target of cmd_check's async-dispatch branch. Not a public subcommand --
  # never invoke directly outside a test harness (the lane reservation it
  # assumes must already exist).
  _async-dispatch) cmd_async_dispatch "$@" ;;
  -h|--help)
    printf 'Usage: %s check|dry-run [N]|status|reap <task_id> [--base <ref>]\n' "$SCRIPT_NAME" >&2
    ;;
  *)
    log_err "unknown mode: $MODE"
    exit 1
    ;;
esac
