#!/usr/bin/env bash
# leadv2-freepool-pulse.sh — founder-facing freepool arm health consumer.
#
# Emits only a confirmed arm_down liveness result. All other outcomes are
# silent so a missing or broken observer cannot fabricate a provider outage.
# The caller owns the pulse/status rendering; this helper owns the bounded
# probe and the exact arm_down filter.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="${LEADV2_FREEPOOL_PULSE_GATE_BIN:-${SCRIPT_DIR}/lib/leadv2-freepool-gate.sh}"
TIMEOUT_S="${LEADV2_FREEPOOL_PULSE_TIMEOUT_S:-5}"

[[ -f "$GATE" ]] || exit 0
[[ "$TIMEOUT_S" =~ ^[1-9][0-9]*$ ]] || TIMEOUT_S=5

REPORT="$(timeout -k 1 "${TIMEOUT_S}" bash "$GATE" liveness 2>/dev/null || true)"
LINE="$(printf '%s\n' "$REPORT" | sed -n '/\[freepool-liveness\] arm_down /p' | head -n1)"
[[ -n "$LINE" ]] || exit 0

printf 'freepool: %s\n' "$LINE"
