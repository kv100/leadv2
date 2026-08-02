#!/usr/bin/env bash
# Bounded, append-only cooldown memory for dispatch arms.  Source this file;
# it intentionally does not change shell options and every public API fails open.

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
  local now="${LEADV2_ARM_COOLDOWN_NOW_EPOCH:-}"
  case "$now" in
    ''|*[!0-9]*) date -u +%s 2>/dev/null || printf '0' ;;
    *) printf '%s' "$now" ;;
  esac
}

_arm_cooldown_iso_epoch() {
  local iso="${1:-}" normalized epoch
  normalized="${iso%%.*}"
  normalized="${normalized%Z}Z"
  epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$normalized" +%s 2>/dev/null || true)"
  if [ -z "$epoch" ]; then
    epoch="$(date -u -d "$normalized" +%s 2>/dev/null || true)"
  fi
  case "$epoch" in ''|*[!0-9]*) printf '0' ;; *) printf '%s' "$epoch" ;; esac
}

_arm_cooldown_epoch_iso() {
  local epoch="${1:-0}" iso
  iso="$(date -u -r "$epoch" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true)"
  if [ -z "$iso" ]; then
    iso="$(date -u -d "@${epoch}" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true)"
  fi
  printf '%s' "${iso:-1970-01-01T00:00:00Z}"
}

_arm_cooldown_seconds() {
  local value="${1:-}" fallback="${2:-0}"
  case "$value" in ''|*[!0-9]*) printf '%s' "$fallback" ;; *) printf '%s' "$value" ;; esac
}

_arm_cooldown_reason() {
  local reason="${1:-unknown}"
  reason="$(printf '%s' "$reason" | tr -c 'A-Za-z0-9_.-' '-')"
  printf '%s' "${reason:-unknown}"
}

# arm_cooldown_record <arm> <reason> [advisory_until_iso]
arm_cooldown_record() {
  local arm="${1:-}" reason advisory now default min max effective advisory_epoch label src dir file reprobe line job
  _arm_cooldown_valid_arm "$arm" || return 0
  reason="$(_arm_cooldown_reason "${2:-unknown}")"
  advisory="${3:-na}"
  [ -n "$advisory" ] || advisory="na"
  now="$(_arm_cooldown_now_epoch)"
  default="$(_arm_cooldown_seconds "${LEADV2_ARM_COOLDOWN_S:-900}" 900)"
  min="$(_arm_cooldown_seconds "${LEADV2_ARM_COOLDOWN_MIN_S:-60}" 60)"
  max="$(_arm_cooldown_seconds "${LEADV2_ARM_COOLDOWN_MAX_S:-3600}" 3600)"
  [ "$min" -le "$max" ] || min="$max"
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
  dir="$(_arm_cooldown_dir)"; file="${dir}/${arm}.state"
  mkdir -p "$dir" 2>/dev/null || return 0
  job="${LEADV2_ARM_COOLDOWN_JOB:-}"
  line="$(_arm_cooldown_epoch_iso "$now") ARM_COOLDOWN arm=${arm} reason=${reason} reprobe_at=${reprobe} cooldown_s=${effective} advisory_until=${advisory} advisory=${label} src=${src}"
  [ -n "$job" ] && line="${line} job=${job}"
  printf '%s\n' "$line" >> "$file" 2>/dev/null || return 0
  printf '%s\n' "$line" >&2
  return 0
}

# arm_cooldown_state <arm> — exactly one verdict, always success.
arm_cooldown_state() {
  local arm="${1:-}" file line reprobe reason now epoch
  _arm_cooldown_valid_arm "$arm" || { printf 'clear\n'; return 0; }
  file="$(_arm_cooldown_dir)/${arm}.state"
  [ -r "$file" ] || { printf 'clear\n'; return 0; }
  line="$(grep -E " ARM_COOLDOWN arm=${arm} " "$file" 2>/dev/null | tail -n 1)" || true
  [ -n "$line" ] || { printf 'clear\n'; return 0; }
  reprobe="$(printf '%s\n' "$line" | sed -n 's/.* reprobe_at=\([^ ]*\).*/\1/p')"
  reason="$(printf '%s\n' "$line" | sed -n 's/.* reason=\([^ ]*\).*/\1/p')"
  epoch="$(_arm_cooldown_iso_epoch "$reprobe")"; now="$(_arm_cooldown_now_epoch)"
  if [ "$epoch" -gt "$now" ] 2>/dev/null; then
    printf 'cooling %s %s\n' "$reprobe" "${reason:-unknown}"
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
