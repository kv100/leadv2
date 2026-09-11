#!/usr/bin/env bash
# run-all-triggers: leadv2-freepool-pulse.sh leadv2-pulse-beat.sh
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

PULSE_REPO="$TMP/pulse-repo"
PULSE_STATE="$TMP/pulse-state"
PULSE_CAPTURE="$TMP/pulse-capture"
mkdir -p "$PULSE_REPO" "$PULSE_STATE"
git init -q "$PULSE_REPO"
BROAD_STUB="$TMP/broad-status.sh"
write_gate "$BROAD_STUB" "printf '%s\\n' \"\${LEADV2_BROAD_STATUS_REVIEW_DELTA:-}\" > '$PULSE_CAPTURE'"
if LEADV2_PROJECT_ROOT="$PULSE_REPO" \
    LEADV2_STATE_ROOT="$PULSE_STATE" \
    LEADV2_BACKLOG_PUMP=0 \
    LEADV2_BROAD_STATUS_BIN="$BROAD_STUB" \
    LEADV2_FREEPOOL_PULSE_BIN="$HELPER" \
    LEADV2_FREEPOOL_PULSE_GATE_BIN="$DOWN_GATE" \
    LEADV2_FREEPOOL_PULSE_TIMEOUT_S=2 \
    bash "$SCRIPT_DIR/leadv2-pulse-beat.sh" --now >/dev/null 2>&1; then
  if grep -Fqx 'freepool: [freepool-liveness] arm_down health=000 reason=unreachable url=http://fixture/health' "$PULSE_CAPTURE"; then
    pass 'pulse beat forwards arm_down into the founder-status delta'
  else
    fail "pulse beat did not forward arm_down: <$(cat "$PULSE_CAPTURE" 2>/dev/null || true)>"
  fi
else
  fail 'pulse beat fixture invocation failed'
fi

printf '[freepool-pulse] PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
