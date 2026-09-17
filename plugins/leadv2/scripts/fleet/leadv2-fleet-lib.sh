#!/usr/bin/env bash
# leadv2-fleet-lib.sh — FLEET-RUNTIME-UNATTENDED-01
#
# Shared, side-effect-free (except for reads of local files) helpers for the
# fleet runtime: disk-floor gate, arm-usability probes, stop-flag check,
# portable mtime. Sourced by leadv2-fleet-runner.sh, leadv2-fleet-guard.sh
# and leadv2-fleet-state.sh — never invoked directly.
#
# Bash 3.2 compatible: no associative arrays, no ${x^^}, no readarray/mapfile.
#
# No `claude` invocation anywhere in this file (mission off-limits): the
# Claude-arm probe reads the local OAuth credential file's expiry field only
# — no network call, no CLI spawn. Never prints a token/credential value.
#
# Env overrides (hermetic tests):
#   LEADV2_FLEET_STATE_ROOT           state dir (default ~/.claude/leadv2-state/fleet)
#   LEADV2_FLEET_STOP_FLAG            stop-flag path (default ~/.claude/leadv2-state/FLEET-STOP)
#   LEADV2_FLEET_ZAI_ENV              GLM key file (default ~/.claude/secrets/zai.env)
#   LEADV2_CLAUDE_CREDENTIALS_FILE    Claude OAuth credential file (default ~/.claude/.credentials.json)
#   LEADV2_FLEET_QUOTA_STATUS_BIN     path to leadv2-quota-status.sh (default: sibling in scripts/)
#   LEADV2_FLEET_ARMS                 space-separated configured arms, default "claude glm"
set -uo pipefail

FLEET_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FLEET_STATE_ROOT="${LEADV2_FLEET_STATE_ROOT:-${HOME}/.claude/leadv2-state/fleet}"
FLEET_STOP_FLAG="${LEADV2_FLEET_STOP_FLAG:-${HOME}/.claude/leadv2-state/FLEET-STOP}"
FLEET_ZAI_ENV="${LEADV2_FLEET_ZAI_ENV:-${HOME}/.claude/secrets/zai.env}"
FLEET_CLAUDE_CREDENTIALS="${LEADV2_CLAUDE_CREDENTIALS_FILE:-${HOME}/.claude/.credentials.json}"
FLEET_QUOTA_STATUS_BIN="${LEADV2_FLEET_QUOTA_STATUS_BIN:-${FLEET_LIB_DIR}/../leadv2-quota-status.sh}"
FLEET_DISK_FLOOR_KB_DEFAULT=2097152   # 2 GiB in KiB — df -Pk reports KiB on both macOS and Linux

fleet_now_epoch() { date +%s; }
fleet_now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Portable mtime-epoch of a path: BSD stat (macOS) vs GNU stat (Linux VPS).
fleet_mtime_epoch() { # <path>
  local p="$1"
  stat -f %m "${p}" 2>/dev/null || stat -c %Y "${p}" 2>/dev/null
}

# Free space, in KiB, of the filesystem containing <path>. POSIX `df -Pk`
# column 4 is portable across macOS/Linux (unlike -h, which is not).
fleet_free_kb() { # <path>
  local p="$1" v
  v="$(df -Pk "${p}" 2>/dev/null | awk 'NR==2 {print $4}')"
  case "${v}" in
    ''|*[!0-9]*) printf '0\n' ;;
    *) printf '%s\n' "${v}" ;;
  esac
}

# Disk-floor gate. 0 = ok to start a new lane. 1 = refuse; prints the named
# reason (one line, "disk_floor free_kb=<n> floor_kb=<n>") to stdout.
fleet_disk_floor_ok() { # <path> [floor_kb]
  local p="$1" floor="${2:-${FLEET_DISK_FLOOR_KB_DEFAULT}}" free
  free="$(fleet_free_kb "${p}")"
  if [[ "${free}" -lt "${floor}" ]]; then
    printf 'disk_floor free_kb=%s floor_kb=%s\n' "${free}" "${floor}"
    return 1
  fi
  return 0
}

# Claude-arm usability: local file read only, no `claude` invocation, no
# network call. Reads `"expiresAt": <ms-epoch>` out of the credential file
# and compares against now. Absent/unreadable file or unparsable field =
# unusable (fail closed, never assume usable). Never prints the file's
# other contents (token/refresh token).
fleet_claude_usable() {
  local f="${FLEET_CLAUDE_CREDENTIALS}" exp_ms now_ms
  [[ -r "${f}" ]] || return 1
  exp_ms="$(grep -o '"expiresAt"[[:space:]]*:[[:space:]]*[0-9]*' "${f}" 2>/dev/null \
            | head -1 | grep -o '[0-9]*$')"
  [[ -n "${exp_ms}" ]] || return 1
  now_ms=$(( $(fleet_now_epoch) * 1000 ))
  [[ "${exp_ms}" -gt "${now_ms}" ]]
}

# GLM-arm usability: the key is a plain file that never expires (mission:
# "does not expire"), so existence + a non-empty ZAI_AUTH_TOKEN= line is the
# whole check. Never prints the token value.
fleet_glm_usable() {
  local f="${FLEET_ZAI_ENV}"
  [[ -r "${f}" ]] || return 1
  grep -q '^ZAI_AUTH_TOKEN=..*' "${f}" 2>/dev/null
}

# Quota-window check for the claude arm only (read-only history.db query;
# no `claude` invocation). GLM has no local quota probe here — its own key
# file never expiring is treated as its availability signal.
fleet_claude_quota_ok() {
  [[ -r "${FLEET_QUOTA_STATUS_BIN}" ]] || return 1
  bash "${FLEET_QUOTA_STATUS_BIN}" --check >/dev/null 2>&1
}

# Is <arm> usable right now (auth/key present AND, for claude, quota open)?
fleet_arm_available() { # <claude|glm>
  case "$1" in
    claude) fleet_claude_usable && fleet_claude_quota_ok ;;
    glm) fleet_glm_usable ;;
    *) return 1 ;;
  esac
}

fleet_configured_arms() { printf '%s\n' "${LEADV2_FLEET_ARMS:-claude glm}"; }

# Prints the first available configured arm and returns 0, or returns 1 if
# every configured arm refuses (the quota_window self-stop condition).
fleet_any_arm_available() {
  local arm
  for arm in $(fleet_configured_arms); do
    if fleet_arm_available "${arm}"; then
      printf '%s\n' "${arm}"
      return 0
    fi
  done
  return 1
}

fleet_stop_flag_present() { [[ -f "${FLEET_STOP_FLAG}" ]]; }
