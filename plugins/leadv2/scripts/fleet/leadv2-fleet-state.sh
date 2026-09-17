#!/usr/bin/env bash
# leadv2-fleet-state.sh — FLEET-RUNTIME-UNATTENDED-01
#
# Writes and reads ONE flat key=value state file per fleet instance. `read`
# is the founder-facing surface: at most five lines, no jq required. This
# script never invokes `claude` and is not a supervisor — it only persists
# facts the runner/guard scripts record.
#
# Storage: ${LEADV2_FLEET_STATE_ROOT:-~/.claude/leadv2-state/fleet}/<name>.state
# Format: plain `key=value` lines. Read via grep/cut (never `source`d — a
# state file is data, not code, even though it is ours).
#
# Usage:
#   leadv2-fleet-state.sh init        --name <instance>
#   leadv2-fleet-state.sh read        --name <instance>
#   leadv2-fleet-state.sh read-raw    --name <instance>   # all fields, for tests/debugging
#   leadv2-fleet-state.sh set-status  --name <instance> --status alive|stopped --reason <r> [--mode normal|degraded:<arm>]
#   leadv2-fleet-state.sh set-field   --name <instance> --field <f> --value <v>
#   leadv2-fleet-state.sh inc-field   --name <instance> --field <f> [--by N]
#
# Fields: status, reason, mode, lanes_in_flight, landed_today,
#         rows_filed_today, consecutive_no_landing, day, stalled, last_change
#
# `day` (YYYY-MM-DD) backs the "today" rollover (round-2 fix M3): every load
# compares the stored day to the current one and zeroes landed_today /
# rows_filed_today when they differ, so a fleet that runs past midnight does
# not keep reporting yesterday's counts as today's forever.
#
# Locking: mkdir-based (portable, no flock dependency on macOS). The lock
# dir carries the holder's pid (round-2 fix M7); a lock is broken only when
# its pid is provably dead, with a 30s-no-pid-file fallback for robustness.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=leadv2-fleet-lib.sh
. "${SCRIPT_DIR}/leadv2-fleet-lib.sh"

_fs_file() { printf '%s/%s.state\n' "${FLEET_STATE_ROOT}" "$1"; }
_fs_lock() { printf '%s/%s.state.lock\n' "${FLEET_STATE_ROOT}" "$1"; }

_fs_acquire() { # <lockdir> -> blocks up to ~5s; breaks a lock whose recorded pid is dead
  local lock="$1" tries=0 age lpid
  while ! mkdir "${lock}" 2>/dev/null; do
    tries=$((tries + 1))
    if [[ -d "${lock}" ]]; then
      lpid="$(cat "${lock}/pid" 2>/dev/null)"
      if [[ -n "${lpid}" ]]; then
        if ! kill -0 "${lpid}" 2>/dev/null; then
          rm -rf "${lock}" 2>/dev/null
          continue
        fi
      else
        # No pid file (race, or a lock dir predating this fix) — fall back
        # to the age-based break so a genuinely abandoned lock cannot wedge
        # every writer forever.
        age=$(( $(fleet_now_epoch) - $(fleet_mtime_epoch "${lock}") ))
        if [[ "${age}" -gt 30 ]]; then
          rm -rf "${lock}" 2>/dev/null
          continue
        fi
      fi
    fi
    if [[ "${tries}" -ge 50 ]]; then
      echo "leadv2-fleet-state.sh: FATAL could not acquire lock ${lock}" >&2
      return 1
    fi
    sleep 0.1
  done
  echo $$ > "${lock}/pid" 2>/dev/null || true
  return 0
}

_fs_release() { rm -rf "$1" 2>/dev/null || true; }

_fs_get() { # <file> <field> -> value or ""
  local f="$1" k="$2"
  [[ -r "${f}" ]] || return 0
  grep -m1 "^${k}=" "${f}" 2>/dev/null | cut -d= -f2-
}

_fs_write_all() { # <file> <status> <reason> <mode> <lif> <landed> <rows> <streak> <day> <stalled> <last_change>
  local tmp="$1.tmp.$$"
  {
    printf 'status=%s\n' "$2"
    printf 'reason=%s\n' "$3"
    printf 'mode=%s\n' "$4"
    printf 'lanes_in_flight=%s\n' "$5"
    printf 'landed_today=%s\n' "$6"
    printf 'rows_filed_today=%s\n' "$7"
    printf 'consecutive_no_landing=%s\n' "$8"
    printf 'day=%s\n' "$9"
    printf 'stalled=%s\n' "${10}"
    printf 'last_change=%s\n' "${11}"
  } > "${tmp}"
  mv -f "${tmp}" "$1"
}

_fs_today() { date -u +%Y-%m-%d; }

_fs_load_or_default() { # <file> -> sets globals _S_STATUS.._S_LAST, rolls landed/rows over on a new day (M3)
  local today
  today="$(_fs_today)"
  _S_STATUS="$(_fs_get "$1" status)"; [[ -n "${_S_STATUS}" ]] || _S_STATUS="alive"
  _S_REASON="$(_fs_get "$1" reason)"
  _S_MODE="$(_fs_get "$1" mode)"; [[ -n "${_S_MODE}" ]] || _S_MODE="normal"
  _S_LIF="$(_fs_get "$1" lanes_in_flight)"; [[ -n "${_S_LIF}" ]] || _S_LIF=0
  _S_LANDED="$(_fs_get "$1" landed_today)"; [[ -n "${_S_LANDED}" ]] || _S_LANDED=0
  _S_ROWS="$(_fs_get "$1" rows_filed_today)"; [[ -n "${_S_ROWS}" ]] || _S_ROWS=0
  _S_STREAK="$(_fs_get "$1" consecutive_no_landing)"; [[ -n "${_S_STREAK}" ]] || _S_STREAK=0
  _S_DAY="$(_fs_get "$1" day)"; [[ -n "${_S_DAY}" ]] || _S_DAY="${today}"
  _S_STALLED="$(_fs_get "$1" stalled)"; [[ -n "${_S_STALLED}" ]] || _S_STALLED=0
  _S_LAST="$(_fs_get "$1" last_change)"; [[ -n "${_S_LAST}" ]] || _S_LAST="-"
  if [[ "${_S_DAY}" != "${today}" ]]; then
    _S_LANDED=0
    _S_ROWS=0
    _S_DAY="${today}"
  fi
}

cmd_init() { # --name X
  local name="" file lock
  while [[ $# -gt 0 ]]; do case "$1" in --name) name="$2"; shift 2 ;; *) shift ;; esac; done
  [[ -n "${name}" ]] || { echo "init: --name required" >&2; return 2; }
  mkdir -p "${FLEET_STATE_ROOT}"
  file="$(_fs_file "${name}")"; lock="$(_fs_lock "${name}")"
  _fs_acquire "${lock}" || return 1
  _fs_write_all "${file}" alive "" normal 0 0 0 0 "$(_fs_today)" 0 "$(fleet_now_iso)"
  _fs_release "${lock}"
}

cmd_read() { # --name X  -> exactly 5 lines
  local name="" file line1
  while [[ $# -gt 0 ]]; do case "$1" in --name) name="$2"; shift 2 ;; *) shift ;; esac; done
  [[ -n "${name}" ]] || { echo "read: --name required" >&2; return 2; }
  file="$(_fs_file "${name}")"
  _fs_load_or_default "${file}"
  if [[ "${_S_STATUS}" == "stopped" ]]; then
    line1="status: stopped (reason: ${_S_REASON:-unknown})"
  elif [[ "${_S_MODE}" == degraded:* ]]; then
    line1="status: alive (degraded: ${_S_MODE#degraded:})"
  else
    line1="status: alive"
  fi
  printf '%s\n' "${line1}"
  printf 'lanes_in_flight: %s\n' "${_S_LIF}"
  printf 'landed_today: %s\n' "${_S_LANDED}"
  printf 'rows_filed_today: %s\n' "${_S_ROWS}"
  printf 'last_change: %s\n' "${_S_LAST}"
}

cmd_read_raw() { # --name X -> all fields, for tests
  local name="" file
  while [[ $# -gt 0 ]]; do case "$1" in --name) name="$2"; shift 2 ;; *) shift ;; esac; done
  file="$(_fs_file "${name}")"
  [[ -r "${file}" ]] && cat "${file}"
}

cmd_set_status() { # --name X --status alive|stopped --reason r [--mode m]
  local name="" status="" reason="" mode="" file lock
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --status) status="$2"; shift 2 ;;
      --reason) reason="$2"; shift 2 ;;
      --mode) mode="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  [[ -n "${name}" && -n "${status}" ]] || { echo "set-status: --name and --status required" >&2; return 2; }
  mkdir -p "${FLEET_STATE_ROOT}"
  file="$(_fs_file "${name}")"; lock="$(_fs_lock "${name}")"
  _fs_acquire "${lock}" || return 1
  _fs_load_or_default "${file}"
  [[ -n "${mode}" ]] && _S_MODE="${mode}"
  _fs_write_all "${file}" "${status}" "${reason}" "${_S_MODE}" \
    "${_S_LIF}" "${_S_LANDED}" "${_S_ROWS}" "${_S_STREAK}" "${_S_DAY}" "${_S_STALLED}" "$(fleet_now_iso)"
  _fs_release "${lock}"
}

cmd_set_field() { # --name X --field f --value v
  local name="" field="" value="" file lock
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --field) field="$2"; shift 2 ;;
      --value) value="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  [[ -n "${name}" && -n "${field}" ]] || { echo "set-field: --name and --field required" >&2; return 2; }
  mkdir -p "${FLEET_STATE_ROOT}"
  file="$(_fs_file "${name}")"; lock="$(_fs_lock "${name}")"
  _fs_acquire "${lock}" || return 1
  _fs_load_or_default "${file}"
  case "${field}" in
    lanes_in_flight) _S_LIF="${value}" ;;
    landed_today) _S_LANDED="${value}" ;;
    rows_filed_today) _S_ROWS="${value}" ;;
    consecutive_no_landing) _S_STREAK="${value}" ;;
    mode) _S_MODE="${value}" ;;
    stalled) _S_STALLED="${value}" ;;
    *) _fs_release "${lock}"; echo "set-field: unknown field ${field}" >&2; return 2 ;;
  esac
  _fs_write_all "${file}" "${_S_STATUS}" "${_S_REASON}" "${_S_MODE}" \
    "${_S_LIF}" "${_S_LANDED}" "${_S_ROWS}" "${_S_STREAK}" "${_S_DAY}" "${_S_STALLED}" "$(fleet_now_iso)"
  _fs_release "${lock}"
}

cmd_inc_field() { # --name X --field f [--by N]
  local name="" field="" by=1 file lock cur
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --field) field="$2"; shift 2 ;;
      --by) by="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  [[ -n "${name}" && -n "${field}" ]] || { echo "inc-field: --name and --field required" >&2; return 2; }
  mkdir -p "${FLEET_STATE_ROOT}"
  file="$(_fs_file "${name}")"; lock="$(_fs_lock "${name}")"
  _fs_acquire "${lock}" || return 1
  _fs_load_or_default "${file}"
  case "${field}" in
    lanes_in_flight) cur="${_S_LIF}"; _S_LIF=$((cur + by)) ;;
    landed_today) cur="${_S_LANDED}"; _S_LANDED=$((cur + by)) ;;
    rows_filed_today) cur="${_S_ROWS}"; _S_ROWS=$((cur + by)) ;;
    consecutive_no_landing) cur="${_S_STREAK}"; _S_STREAK=$((cur + by)) ;;
    stalled) cur="${_S_STALLED}"; _S_STALLED=$((cur + by)) ;;
    *) _fs_release "${lock}"; echo "inc-field: unknown field ${field}" >&2; return 2 ;;
  esac
  _fs_write_all "${file}" "${_S_STATUS}" "${_S_REASON}" "${_S_MODE}" \
    "${_S_LIF}" "${_S_LANDED}" "${_S_ROWS}" "${_S_STREAK}" "${_S_DAY}" "${_S_STALLED}" "$(fleet_now_iso)"
  _fs_release "${lock}"
}

main() {
  local sub="${1:-}"; shift || true
  case "${sub}" in
    init) cmd_init "$@" ;;
    read) cmd_read "$@" ;;
    read-raw) cmd_read_raw "$@" ;;
    set-status) cmd_set_status "$@" ;;
    set-field) cmd_set_field "$@" ;;
    inc-field) cmd_inc_field "$@" ;;
    *) echo "usage: leadv2-fleet-state.sh {init|read|read-raw|set-status|set-field|inc-field} --name <instance> ..." >&2; return 2 ;;
  esac
}

main "$@"
