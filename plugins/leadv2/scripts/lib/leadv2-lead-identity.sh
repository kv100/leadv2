#!/usr/bin/env bash
# leadv2-lead-identity.sh — resolves a per-lead-process identity for lane
# accounting (lead_session_id), so lead_session_lane_cap groups lanes by the
# real OS process instead of every session falling through to a shared
# "direct" bucket (D6-REGISTRY-LANE-OWNERSHIP-01).
#
# API:
#   leadv2_lead_session_id   # stdout: lead-<durable-pid>-<birth-hash>, or
#                             # "direct" on any resolution failure (fail-open)
#
# Built on _lv2_durable_pid()/_lv2_pid_birth() (leadv2-active-registry.sh:809,
# :860), already proven in production for that registry's own session_id.
# Do not re-implement PID-walk/birth-read logic here -- source, don't copy.
#
# Isolation: leadv2-active-registry.sh does `set -euo pipefail` at its top
# level, which would otherwise leak into callers (leadv2-inbox.sh,
# leadv2-broad-status.sh) that deliberately run without -e so a resolution
# failure degrades gracefully instead of aborting the whole beat. The source
# + resolve happens inside a subshell so those options never escape this
# function.
#
# Fail-open: any error prints "direct" and logs one stderr line -- never a
# hard failure, since callers use this in registration hot paths.

if [[ -n "${_LV2_LEAD_IDENTITY_LOADED:-}" ]]; then
  return 0 2>/dev/null || true
fi
_LV2_LEAD_IDENTITY_LOADED=1
# ${BASH_SOURCE[0]:-$0}: bash keeps this lib's own path; zsh (no BASH_SOURCE)
# degrades to the sourcing script's $0, which may sit one level up -- the
# registry source then fails to resolve and the resolver fails open to
# "direct" with its stderr warning, never a hard error.
_LV2_LEAD_IDENTITY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

leadv2_lead_session_id() {
  (
    if ! declare -F _lv2_durable_pid >/dev/null 2>&1 || ! declare -F _lv2_pid_birth >/dev/null 2>&1; then
      _lv2_li_registry="${_LV2_LEAD_IDENTITY_DIR}/../leadv2-active-registry.sh"
      [[ -f "${_lv2_li_registry}" ]] && source "${_lv2_li_registry}" 2>/dev/null
    fi
    set +e +u +o pipefail

    id="direct"
    if declare -F _lv2_durable_pid >/dev/null 2>&1 && declare -F _lv2_pid_birth >/dev/null 2>&1; then
      pid="$(_lv2_durable_pid 2>/dev/null)"
      if [[ -n "${pid}" ]]; then
        birth="$(_lv2_pid_birth "${pid}" 2>/dev/null)"
        if [[ -n "${birth}" && "${birth}" != "unknown" ]]; then
          birth_hash="$(printf '%s' "${birth}" | cksum | awk '{print $1}')"
          if [[ -n "${birth_hash}" ]]; then
            # birth_hash, NOT hash: `hash` is zsh's command-table parameter.
            id="lead-${pid}-${birth_hash}"
          fi
        fi
      fi
    fi

    if [[ "${id}" == "direct" ]]; then
      echo "[leadv2-lead-identity] WARNING: resolver unavailable or failed, falling back to direct" >&2
    fi
    printf -- '%s' "${id}"
  )
}
