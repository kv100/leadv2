#!/usr/bin/env bash
# lib/leadv2-alarm-dedupe.sh — TRANSITION-based alarm dedupe (SUPERVISOR-
# HARDENING-01 item 5). An alarm line is emitted only when (key -> value)
# DIFFERS from the persisted last value for that key. A breach that persists
# across many polls therefore fires exactly once; when it clears and
# re-breaches, the value transitions and it fires again. This is the single
# shared shape that stops the four known-noisy emitters
# (STUCK-ALARM-HAS-NO-DEDUP-01, STUCK-ALARM-FALSE-FLEET-DEATH-01,
# TRUTH_RED trust-score, TRUTH_RED engine-error-volume) re-firing every poll
# without writing the dedupe rule four times.
#
# WHY TRANSITION NOT PRESENCE: the existing per-call `--since loop` delta in
# leadv2-supervise.sh is an UPSTREAM, per-invocation dedupe (one call's events
# vs the previous call's). It does nothing across invocations of the same
# loop, which is where the repeat-fire noise lives. This lib is a WRITE-TIME
# gate AT THE EMITTER, persisted across cycles. They compose; do not remove
# the upstream one.
#
# KEY RULE (the single easiest way to get this wrong): the value is the
# SEMANTIC value, never the rendered line. A rendered line carries a
# timestamp and would transition every poll, silently defeating the whole
# point. Callers pass `key`, `semantic value`, `rendered line` separately.
#
# STATE: one file per key under <control-plane>/.alarm-state/<sanitised-key>,
# content = last semantic value string. Atomic replace (tmp + mv). Keys are
# derived from task ids / probe ids (untrusted-ish input) and are sanitised
# to [A-Za-z0-9._-] before path join — a raw key would be a path-traversal
# write.
#
# CONCURRENCY: single-writer per key. The supervise loop is the only writer
# for the alarm keys it owns (truth_red:*, job_stalled:*, lane_no_artifact:*);
# the watchdog (item 2) writes only the disjoint `loop_silent` key. Disjoint
# key spaces ⇒ no lock is needed. (SUPERVISOR-HARDENING-01 self-check §4.)
#
# Env:
#   LEADV2_ALARM_STATE_DIR — absolute override of the .alarm-state dir (tests)
#   LEADV2_STATE_ROOT / PROJECT_ROOT / CLAUDE_PROJECT_DIR — control-plane root
#     resolution, threaded to leadv2-state-path.sh (same order as the loop).
#
# Surfaces:
#   leadv2_alarm_transition <key> <value>
#       exit 0 = FIRE (and record the new value); exit 1 = SUPPRESS (unchanged).
#       For bash callers that build one line at a time.
#   leadv2_alarm_filter   (stdin batch mode)
#       stdin rows: <key><TAB><value><TAB><line>
#       stdout    : the <line> of every row that FIRED this pass (survivors).
#       The wiring surface for the python emitters: they print candidate rows
#       to stdout, bash pipes the batch through this once per cycle. One
#       subprocess per cycle, one implementation of the semantics.
#
# Sourcing this file defines the functions; it performs no I/O at source time.

set -o pipefail

# Resolve the .alarm-state directory once per process (memoised).
_leadv2_alarm_state_dir() {
  [[ -n "${LEADV2_ALARM_STATE_DIR:-}" ]] && { printf '%s' "$LEADV2_ALARM_STATE_DIR"; return; }
  local resolver _self _dir
  if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -f "${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-state-path.sh" ]]; then
    resolver="${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-state-path.sh"
  else
    _self="${BASH_SOURCE[0]:-$0}"
    _dir="$(cd "$(dirname "$_self")" && pwd)"
    resolver="${_dir}/../leadv2-state-path.sh"
  fi
  if [[ -x "$resolver" ]]; then
    local root
    root="$(PROJECT_ROOT="${PROJECT_ROOT:-${LEADV2_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-}}}" "$resolver" root 2>/dev/null || true)"
    [[ -n "$root" ]] && { printf '%s/.alarm-state' "$root"; return; }
  fi
  # Last-resort fallback (tests / no control plane): a tmp dir.
  printf '%s/leadv2-alarm-state' "${TMPDIR:-/tmp}"
}

# Sanitise an alarm key to a safe path component. Strips anything outside
# [A-Za-z0-9._-] (collapses path separators and `..`). Keys come from task
# ids / probe ids and are NOT trusted filenames.
_leadv2_alarm_sanitize_key() {
  local k="${1:-}"
  # Collapse every char outside [A-Za-z0-9._-] to '_'. Slashes and `..` become
  # underscores, so the result can never escape the state dir — this is the
  # path-traversal defence; it is NOT relying on the leading-dot strip below.
  k="${k//[^A-Za-z0-9._-]/_}"
  # Strip a leading run of dots/underscores so the file is visible and never
  # hidden (and never starts with '.', a defensive second layer).
  while [[ "$k" == [._]* ]]; do k="${k:1}"; done
  [[ -z "$k" ]] && k="anon"
  printf '%s' "$k"
}

# Core: returns 0 if (key->value) is a TRANSITION (fires), 1 if unchanged.
# Records the new value atomically on fire. Pure bash, single-writer-per-key.
_leadv2_alarm_fire() {
  local key="$1" value="$2"
  local state_dir file last
  state_dir="$(_leadv2_alarm_state_dir)"
  file="${state_dir}/$(_leadv2_alarm_sanitize_key "$key")"
  mkdir -p "$state_dir" 2>/dev/null || return 1
  last=""
  [[ -f "$file" ]] && last="$(cat "$file" 2>/dev/null || true)"
  if [[ "$last" == "$value" ]]; then
    return 1   # unchanged → suppress
  fi
  # Atomic replace: tmp in same dir, then mv.
  local tmp
  tmp="${file}.$$.$RANDOM.tmp"
  printf '%s' "$value" >"$tmp" 2>/dev/null && mv -f "$tmp" "$file" 2>/dev/null
  return 0     # transition → fire
}

leadv2_alarm_transition() {
  local key="${1:-}" value="${2:-}"
  [[ -z "$key" ]] && return 1
  _leadv2_alarm_fire "$key" "$value"
}

# ── Presence tracking: the recovery edge (A5) ─────────────────────────────
# Pure transition dedupe has a hole: when a breach CLEARS, the emitter stops
# emitting the row, so the lib never sees a value change — and the next
# re-breach with the SAME value is suppressed (RED persisted, RED re-fires →
# suppressed). To make "clear then re-breach fire again" work, each emitter
# marks every key it observes this cycle, then SWEEPS its keyspace: any key
# observed last cycle but absent this cycle gets its state written to a CLEAR
# sentinel, so the next re-appearance transitions CLEAR→RED and fires.
#
# Seen markers are namespaced per keyspace (`<sanitised>.seen.<keyspace>`) so
# emitters running at different cadences (5s events vs 300s pulse) on the same
# keyspace never clobber each other's presence set. ONLY the authoritative
# emitter for a keyspace should sweep (see supervise-loop wiring).
_leadv2_alarm_seen_file() {  # <state_dir> <sanitised_key> <keyspace>
  printf '%s/%s.seen.%s' "$1" "$2" "$3"
}

# Like leadv2_alarm_filter, but ALSO records each observed key as seen this
# cycle (tagged keyspace+cycle). Use from the authoritative emitter; follow
# with leadv2_alarm_sweep <keyspace> <cycle>.
leadv2_alarm_filter_seen() {
  local keyspace="${1:-default}" cycle="${2:-0}"
  local state_dir file skey key value line
  state_dir="$(_leadv2_alarm_state_dir)"
  mkdir -p "$state_dir" 2>/dev/null || true
  while IFS=$'\t' read -r key value line; do
    if [[ -z "$value" && -z "$line" ]]; then
      printf '%s\n' "${key}${value:+	${value}}${line}"
      continue
    fi
    skey="$(_leadv2_alarm_sanitize_key "$key")"
    printf '%s' "$cycle" >"$(_leadv2_alarm_seen_file "$state_dir" "$skey" "$keyspace")" 2>/dev/null || true
    if _leadv2_alarm_fire "$key" "$value"; then
      printf '%s\n' "$line"
    fi
  done
}

# Sweep: for every key observed in <keyspace> whose last-seen cycle != this
# cycle, write CLEAR to its state file (so a re-appearance fires). Idempotent.
# Run once per cycle AFTER leadv2_alarm_filter_seen, from the authoritative
# emitter only.
leadv2_alarm_sweep() {
  local keyspace="${1:-default}" cycle="${2:-0}"
  local state_dir seen state_file skey last
  state_dir="$(_leadv2_alarm_state_dir)"
  [[ -d "$state_dir" ]] || return 0
  for seen in "$state_dir"/*.seen."$keyspace"; do
    [[ -e "$seen" ]] || continue
    last="$(cat "$seen" 2>/dev/null || true)"
    [[ "$last" == "$cycle" ]] && continue
    # Derive the state file by stripping the ".seen.<keyspace>" suffix.
    skey="${seen##*/}"
    skey="${skey%.seen.$keyspace}"
    state_file="${state_dir}/${skey}"
    # Write CLEAR atomically only if not already CLEAR (avoid needless writes).
    [[ -f "$state_file" && "$(cat "$state_file" 2>/dev/null || true)" == "CLEAR" ]] && continue
    local tmp="${state_file}.swp.$$"
    printf 'CLEAR' >"$tmp" 2>/dev/null && mv -f "$tmp" "$state_file" 2>/dev/null || true
  done
  return 0
}

# Batch filter mode. stdin: <key>\t<value>\t<line> per row. stdout: the
# <line> of every row that fired. Rows with fewer than 3 fields are passed
# through unchanged (defensive — never silently drop an alarm).
leadv2_alarm_filter() {
  local key value line
  while IFS=$'\t' read -r key value line; do
    if [[ -z "$value" && -z "$line" ]]; then
      # Only one or two fields — no dedupe signal; emit to be safe.
      printf '%s\n' "${key}${value:+	${value}}${line}"
      continue
    fi
    if _leadv2_alarm_fire "$key" "$value"; then
      printf '%s\n' "$line"
    fi
  done
}
