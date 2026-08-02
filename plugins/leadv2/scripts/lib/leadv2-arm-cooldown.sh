#!/usr/bin/env bash
# Bounded, append-only cooldown memory for dispatch arms.  Source this file;
# it intentionally does not change shell options and every public API fails open.

# ── N1B hard bounds (NOT env-derived) ────────────────────────────────────────
# The whole point of this library: an arm's availability must be decided by a
# value no environment variable can push outside a range fixed in reviewed
# source. ARM_COOLDOWN_HARD_MAX_S is that fixed ceiling. An operator may LOWER
# it via LEADV2_ARM_COOLDOWN_MAX_S (a shorter cooldown only re-probes sooner,
# always safe) but can never RAISE it past 3600. Changing 3600 requires editing
# this file -- a reviewed commit with a symlink-visible diff -- which is the
# exact review gate a LEADV2_* export bypasses. 3600, not larger, because the
# cooldown is a transient-provider-condition memory: re-probing a refused arm
# costs one cheap call; running the fleet on a fallback arm for longer costs a
# working day of the wrong model. One hour is the longest window in which the
# re-probe is still obviously the cheaper mistake.
ARM_COOLDOWN_HARD_MAX_S=3600
ARM_COOLDOWN_HARD_MIN_S=1

# Source the portable lock helper if it is reachable via the library's own
# sibling path (../leadv2-portable-lock.sh relative to this file). Ordering aid
# ONLY -- correctness (the reader's max-reprobe_at scan) is independent of the
# lock, so a missing helper degrades silently to an unlocked append and nothing
# breaks. The lock helper changes no shell options (one global + fns). We source
# ONLY the relative sibling path -- never an env-selected path -- so no env var
# can cause arbitrary code to execute here.
command -v lv2_lock_wait >/dev/null 2>&1 || {
  if [ -n "${BASH_SOURCE[0]:-}" ] && [ -r "${BASH_SOURCE[0]%/*}/../leadv2-portable-lock.sh" ]; then
    source "${BASH_SOURCE[0]%/*}/../leadv2-portable-lock.sh" 2>/dev/null || true
  fi
}

_arm_cooldown_dir() {
  printf '%s' "${LEADV2_ARM_COOLDOWN_DIR:-${HOME:-}/.claude/cache/arm-cooldown}"
}

_arm_cooldown_valid_arm() {
  case "${1:-}" in
    ''|*[!A-Za-z0-9_.-]*) return 1 ;;
    *) return 0 ;;
  esac
}

_arm_cooldown_now_epoch() {
  local now canon
  now="${LEADV2_ARM_COOLDOWN_NOW_EPOCH:-}"
  canon="$(_arm_cooldown_int "$now")"
  if [ -n "$canon" ]; then printf '%s' "$canon"; return 0; fi
  date -u +%s 2>/dev/null || printf '0'
}

# _arm_cooldown_int <raw> -> canonical base-10 integer, or "" if unusable.
# Strips leading zeros (08->8, 000->0) so $(( )) / [ -gt ] never read octal,
# and rejects anything non-digit or longer than 10 digits (signed-32 overflow).
# This is the ONE sanitizer every numeric that reaches arithmetic passes through.
_arm_cooldown_int() {
  local v="${1:-}"
  case "$v" in ''|*[!0-9]*) printf ''; return 0 ;; esac
  [ "${#v}" -le 10 ] || { printf ''; return 0; }
  v="${v#"${v%%[!0]*}"}"
  printf '%s' "${v:-0}"
}

_arm_cooldown_seconds() {  # <value> <fallback> -> canonical base-10 int
  local canon
  canon="$(_arm_cooldown_int "${1:-}")"
  [ -n "$canon" ] && { printf '%s' "$canon"; return 0; }
  canon="$(_arm_cooldown_int "${2:-0}")"
  printf '%s' "${canon:-0}"
}

_arm_cooldown_iso_epoch() {
  local iso="${1:-}" normalized epoch
  normalized="${iso%%.*}"
  normalized="${normalized%Z}Z"
  epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$normalized" +%s 2>/dev/null || true)"
  if [ -z "$epoch" ]; then
    epoch="$(date -u -d "$normalized" +%s 2>/dev/null || true)"
  fi
  # route through the sanitizer so a parsed epoch is base-10 canonical too
  epoch="$(_arm_cooldown_int "$epoch")"
  printf '%s' "${epoch:-0}"
}

_arm_cooldown_epoch_iso() {
  local epoch canon iso
  canon="$(_arm_cooldown_int "${1:-0}")"; canon="${canon:-0}"
  iso="$(date -u -r "$canon" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true)"
  if [ -z "$iso" ]; then
    iso="$(date -u -d "@${canon}" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true)"
  fi
  printf '%s' "${iso:-1970-01-01T00:00:00Z}"
}

_arm_cooldown_reason() {
  local reason="${1:-unknown}"
  reason="$(printf '%s' "$reason" | tr -c 'A-Za-z0-9_.-' '-')"
  printf '%s' "${reason:-unknown}"
}

# arm_cooldown_record <arm> <reason> [advisory_until_iso]
arm_cooldown_record() {
  local arm="${1:-}" reason advisory now default min max effective advisory_epoch label src dir file reprobe line job lockf
  _arm_cooldown_valid_arm "$arm" || return 0
  reason="$(_arm_cooldown_reason "${2:-unknown}")"
  advisory="${3:-na}"
  [ -n "$advisory" ] || advisory="na"
  now="$(_arm_cooldown_now_epoch)"
  # N1B clamp order: max is bounded by the HARD ceiling BEFORE it is used as
  # anyone's ceiling. An operator may lower the ceiling; never raise it.
  max="$(_arm_cooldown_seconds "${LEADV2_ARM_COOLDOWN_MAX_S:-3600}" 3600)"
  [ "$max" -gt "$ARM_COOLDOWN_HARD_MAX_S" ] && max="$ARM_COOLDOWN_HARD_MAX_S"
  [ "$max" -lt "$ARM_COOLDOWN_HARD_MIN_S" ] && max="$ARM_COOLDOWN_HARD_MIN_S"
  min="$(_arm_cooldown_seconds "${LEADV2_ARM_COOLDOWN_MIN_S:-60}" 60)"
  [ "$min" -lt "$ARM_COOLDOWN_HARD_MIN_S" ] && min="$ARM_COOLDOWN_HARD_MIN_S"
  [ "$min" -gt "$max" ] && min="$max"
  default="$(_arm_cooldown_seconds "${LEADV2_ARM_COOLDOWN_S:-900}" 900)"
  [ "$default" -lt "$min" ] && default="$min"
  [ "$default" -gt "$max" ] && default="$max"
  effective="$default"; label="ignored"; src="default"
  if [ "$advisory" != "na" ]; then
    advisory_epoch="$(_arm_cooldown_iso_epoch "$advisory")"
    if [ "$advisory_epoch" -gt "$now" ] 2>/dev/null; then
      effective=$((advisory_epoch - now))
      [ "$effective" -lt "$min" ] && effective="$min"
      [ "$effective" -gt "$default" ] && effective="$default"
      [ "$effective" -gt "$max" ] && effective="$max"
      src="parsed"
      [ "$effective" -lt "$default" ] && label="shortened"
    fi
  fi
  reprobe="$(_arm_cooldown_epoch_iso $((now + effective)))"
  # N1B guard: a record is either well-formed or it is not written; there is no
  # third state. If reprobe fails to parse to a non-empty future ISO for ANY
  # reason (present or future), fall back to now+min and mark src=fallback so an
  # empty/garbage reprobe_at can never read as "clear" right after a refusal.
  if [ -z "$reprobe" ] || [ "$(_arm_cooldown_iso_epoch "$reprobe")" -le "$now" ]; then
    effective="$min"; src="fallback"
    reprobe="$(_arm_cooldown_epoch_iso $((now + effective)))"
  fi
  dir="$(_arm_cooldown_dir)"; file="${dir}/${arm}.state"
  mkdir -p "$dir" 2>/dev/null || return 0
  job="${LEADV2_ARM_COOLDOWN_JOB:-}"
  line="$(_arm_cooldown_epoch_iso "$now") ARM_COOLDOWN arm=${arm} reason=${reason} reprobe_at=${reprobe} cooldown_s=${effective} advisory_until=${advisory} advisory=${label} src=${src}"
  [ -n "$job" ] && line="${line} job=${job}"
  # N1B ordering: take the existing portable lock when available (fail-open --
  # the lock buys ORDERING, not atomicity; a single sub-PIPE_BUF append is
  # atomic on APFS/ext4, and a cooldown lib that refuses to record a refusal is
  # worse than one that occasionally records out of order). Correctness against
  # a stalled/late writer comes from the reader's max-reprobe_at scan, not here.
  lockf="${file}.lock"
  (
    if command -v lv2_lock_wait >/dev/null 2>&1; then
      lv2_lock_wait "${lockf}" 2 2>/dev/null || true
    fi
    printf '%s\n' "$line" >> "$file" 2>/dev/null || exit 1
  ) 9>"${lockf}" 2>/dev/null || true
  printf '%s\n' "$line" >&2
  return 0
}

# arm_cooldown_state <arm> — exactly one verdict, always success.
# Output grammar is FROZEN: `cooling <reprobe_iso> <reason>` or the bare token
# `clear`. leadv2-codex-lockout.sh / leadv2-glm-quota-gate.sh awk '{print $2}'
# this output -- field order must not change.
arm_cooldown_state() {
  local arm="${1:-}" file line reprobe reason now epoch
  local latest_epoch=0 latest_reprobe="" latest_reason="" cand
  _arm_cooldown_valid_arm "$arm" || { printf 'clear\n'; return 0; }
  file="$(_arm_cooldown_dir)/${arm}.state"
  [ -r "$file" ] || { printf 'clear\n'; return 0; }
  # N1B semantics: an arm is cooling if ANY record carries a future
  # reprobe_at; the verdict reports the LATEST such reprobe_at + its reason.
  # Append order is irrelevant -- a stalled writer's shorter record can no
  # longer shorten a live cooldown. Bounded to the last 200 records (200
  # refusals of one arm inside one hour is far past anything real). Lines whose
  # reprobe_at does not parse are skipped, never answered from.
  while IFS= read -r line; do
    case "$line" in *" ARM_COOLDOWN arm=${arm} "*) ;; *) continue ;; esac
    cand="$(printf '%s\n' "$line" | sed -n 's/.* reprobe_at=\([^ ]*\).*/\1/p')"
    [ -n "$cand" ] || continue
    epoch="$(_arm_cooldown_iso_epoch "$cand")"
    [ "$epoch" -gt 0 ] 2>/dev/null || continue
    if [ "$epoch" -gt "$latest_epoch" ]; then
      latest_epoch="$epoch"; latest_reprobe="$cand"
      latest_reason="$(printf '%s\n' "$line" | sed -n 's/.* reason=\([^ ]*\).*/\1/p')"
    fi
  done < <(tail -n 200 "$file" 2>/dev/null)
  now="$(_arm_cooldown_now_epoch)"
  if [ "$latest_epoch" -gt 0 ] && [ "$latest_epoch" -gt "$now" ] 2>/dev/null; then
    printf 'cooling %s %s\n' "$latest_reprobe" "${latest_reason:-unknown}"
  else
    printf 'clear\n'
  fi
  return 0
}

arm_cooldown_clear() {
  local arm="${1:-}" file
  _arm_cooldown_valid_arm "$arm" || return 0
  file="$(_arm_cooldown_dir)/${arm}.state"
  mkdir -p "$(_arm_cooldown_dir)" 2>/dev/null || return 0
  : > "$file" 2>/dev/null || true
  return 0
}

# One durable observability line; it never participates in gating.
arm_cooldown_ladder_note() {
  local arm="${1:-}" reason reprobe dir line
  _arm_cooldown_valid_arm "$arm" || return 0
  reason="$(_arm_cooldown_reason "${2:-unknown}")"; reprobe="${3:-na}"
  dir="$(_arm_cooldown_dir)"; mkdir -p "$dir" 2>/dev/null || return 0
  line="$(_arm_cooldown_epoch_iso "$(_arm_cooldown_now_epoch)") ARM_COOLDOWN_LADDER arm=${arm} reason=${reason} reprobe_at=${reprobe}"
  printf '%s\n' "$line" >> "${dir}/${arm}.journal" 2>/dev/null || true
  printf '%s\n' "$line" >&2
  return 0
}
