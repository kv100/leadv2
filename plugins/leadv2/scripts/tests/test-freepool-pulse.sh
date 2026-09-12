#!/usr/bin/env bash
# run-all-triggers: leadv2-freepool-pulse.sh
# Hermetic tests for the founder-facing freepool arm_down consumer.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$SCRIPT_DIR/leadv2-freepool-pulse.sh"
TMP="/private/tmp/freepool-pulse-suite.$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '[TEST] FAIL: %s\n' "$1"; }

write_gate() {
  local path="$1" body="$2"
  printf '%s\n' '#!/usr/bin/env bash' "$body" > "$path"
  chmod +x "$path"
}

DOWN_GATE="$TMP/down.sh"
write_gate "$DOWN_GATE" "printf '%s\\n' '[freepool-liveness] arm_down health=000 reason=unreachable url=http://fixture/health'; exit 1"
out="$(LEADV2_FREEPOOL_PULSE_GATE_BIN="$DOWN_GATE" LEADV2_FREEPOOL_PULSE_TIMEOUT_S=2 bash "$HELPER")"
if [[ "$out" == 'freepool: [freepool-liveness] arm_down health=000 reason=unreachable url=http://fixture/health' ]]; then
  pass 'arm_down is surfaced verbatim with a consumer prefix'
else
  fail "arm_down was not surfaced: <$out>"
fi

SICK_GATE="$TMP/sick.sh"
write_gate "$SICK_GATE" "printf '%s\\n' '[freepool-liveness] gate_broken health=200 reason=models_empty'"
out="$(LEADV2_FREEPOOL_PULSE_GATE_BIN="$SICK_GATE" bash "$HELPER")"
if [[ -z "$out" ]]; then
  pass 'non-arm_down degradation stays silent'
else
  fail "non-arm_down degradation leaked into pulse: <$out>"
fi

HANG_GATE="$TMP/hang.sh"
write_gate "$HANG_GATE" 'sleep 2'
out="$(LEADV2_FREEPOOL_PULSE_GATE_BIN="$HANG_GATE" LEADV2_FREEPOOL_PULSE_TIMEOUT_S=1 bash "$HELPER")"
if [[ -z "$out" ]]; then
  pass 'probe timeout stays silent'
else
  fail "probe timeout leaked output: <$out>"
fi

# ONE-STATUS-MECHANISM-01 (2026-09-13): this section tested the retired
# beat chain and was deleted with it.
printf '[freepool-pulse] PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
