#!/usr/bin/env bash
# lib/leadv2-refusal-classify.sh — N-5: refusal classification for the review gate.
#
# ONE function, sourced only by leadv2-dispatch-product-close.sh (and its test harness).
# This is a private, synced COPY of the two refusal-marker regexes in
# leadv2-dispatch-code.sh's refusal_reason() (~line 1339), not a shared `source` of that
# file -- the N-5 task's LANE_WRITES deliberately excludes leadv2-dispatch-code.sh (three
# other lanes are active in it). If either regex changes, update both.
# keep in sync with leadv2-dispatch-code.sh:1339 refusal_reason()
#
# Deliberately `set -uo pipefail`, never `-e` -- a sourced `-e` leaks into and silently
# overrides the caller's own `set -uo pipefail` (SILENT-DEATH-01, see
# leadv2-dispatch-code.sh / leadv2-dispatch-product-close.sh's matching comments).
set -uo pipefail

# classify_arm_failure <rc> <stderr-file> [<stdout-file>] -> prints exactly one token:
#   refused_peak_hours   | LEADV2_DISPATCH_REFUSED: peak_hours
#   refused_quota        | LEADV2_DISPATCH_REFUSED: <other marker>, GLM REROUTE, or rc 75
#   refused_channel_down | rc 77 (probe/run channel-down admission, e.g. kimi-coder.sh)
#   ran                  | not a refusal -- the arm ran (well or badly); rc/output still
#                           need the caller's own provider_error/empty_response/
#                           no_verdict_marker classification, never assumed here.
classify_arm_failure() { # <rc> <err-file> <out-file>
  local rc="${1:-}" err_file="${2:-}" out_file="${3:-}"
  local combined
  combined="$(cat "${out_file}" 2>/dev/null || true)"$'\n'"$(cat "${err_file}" 2>/dev/null || true)"

  # rc 77: probe/channel-down admission (kimi-coder.sh probe, or any launcher's own
  # documented "channel unreachable" contract) -- never a content/provider failure.
  if [[ "${rc}" == "77" ]]; then
    printf 'refused_channel_down'
    return 0
  fi

  local marker
  marker="$(printf '%s\n' "${combined}" | sed -n 's/.*LEADV2_DISPATCH_REFUSED:[[:space:]]*\([A-Za-z0-9._-][A-Za-z0-9._-]*\).*/\1/p' | head -1)"
  if [[ -n "${marker}" && ( "${rc}" == "1" || "${rc}" == "2" || "${rc}" == "75" ) ]]; then
    if [[ "${marker}" == "peak_hours" ]]; then
      printf 'refused_peak_hours'
    else
      printf 'refused_quota'
    fi
    return 0
  fi

  # Compatibility only for older GLM quota gates that predate the explicit marker.
  if [[ "${rc}" == "1" && "${combined}" == *"[glm-quota-gate] REROUTE"* ]]; then
    printf 'refused_quota'
    return 0
  fi

  # rc 75: lock/secret/usage admission refusal (glm-coder.sh lock busy, kimi-coder.sh
  # lock/secret/usage) without a marker in the captured output -- still a refusal, not a
  # provider error, per the existing kimi rc-75 contract (KIMI-CHANNEL-01b).
  if [[ "${rc}" == "75" ]]; then
    printf 'refused_quota'
    return 0
  fi

  printf 'ran'
  return 0
}
