#!/usr/bin/env bash
# test-leadv2-loop-detect.sh — NUDGE-TAX-01 warn-anchoring budget.
#
# freq-WARN used to fire on EVERY call from FREQ_WARN to HARD_LIMIT — measured
# 19,776 repeated warns/10d, 12,589 past count 50 (live env sets
# LEADV2_TOOL_HARD_LIMIT=1400). Now WARN fires only on threshold crossings
# (FREQ_WARN, doublings while < HARD_LIMIT, and HARD_LIMIT-10); BLOCK and the
# sig-warn BLOCK are untouched. This suite locks:
#   1. anchors computed for the live env (30,1400) and the documented default
#      (30,50) are exactly the crossing sets;
#   2. through the REAL hook path: warns at 5, 10, 12, 20 for FW=5/HL=22,
#      BLOCK (rc=2 + deny JSON) at 22, and NOTHING between anchors;
#   3. warn budget per tool per session == number of anchors (7 for 30/1400);
#   4. sig-warn: one warn at the 3rd identical call, none at the 4th, BLOCK
#      at the 5th (the hook's own anti-loop case still fires).
set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${TEST_DIR}/../../../.." && pwd)"
HOOK="${ROOT}/plugins/leadv2/hooks/leadv2-loop-detect-hook.sh"
DETECT="${ROOT}/plugins/leadv2/scripts/leadv2-loop-detect.py"
[ -f "$HOOK" ] || { echo "FAIL: hook missing: $HOOK"; exit 1; }
[ -f "$DETECT" ] || { echo "FAIL: detector missing: $DETECT"; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/loop-detect-budget.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT

# --- 1: anchor sets (unit, through the module) --------------------------------
ANCHORS="$(python3 - "$DETECT" <<'PYEOF'
import importlib.util, os, sys
os.environ["LEADV2_TOOL_FREQ_WARN"] = "30"
os.environ["LEADV2_TOOL_HARD_LIMIT"] = "1400"
spec = importlib.util.spec_from_file_location("d", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(",".join(str(x) for x in sorted(m._TOOL_WARN_ANCHORS)))
PYEOF
)"
[ "$ANCHORS" = "30,60,120,240,480,960,1390" ] \
  && ok "live-env anchors (30,1400) = $ANCHORS" \
  || bad "live-env anchors wrong: got $ANCHORS"

ANCHORS50="$(FW=30 HL=50 python3 - "$DETECT" <<'PYEOF'
import importlib.util, os, sys
os.environ["LEADV2_TOOL_FREQ_WARN"] = "30"
os.environ["LEADV2_TOOL_HARD_LIMIT"] = "50"
spec = importlib.util.spec_from_file_location("d", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(",".join(str(x) for x in sorted(m._TOOL_WARN_ANCHORS)))
PYEOF
)"
[ "$ANCHORS50" = "30,40" ] \
  && ok "default anchors (30,50) = $ANCHORS50" \
  || bad "default anchors wrong: got $ANCHORS50"

# --- 2+3: real hook path, FW=5 HL=22 -> anchors {5,10,12,20}, BLOCK at 22 ----
SID="freq1"
FW=5; HL=22
FIRES=""; BLOCKS=""; DENY_JSON=""
for i in $(seq 1 22); do
  PRE='{"tool_name":"Bash","tool_input":{"command":"probe c'"$i"'"},"session_id":"'"$SID"'","hook_event_name":"PreToolUse"}'
  POST='{"tool_name":"Bash","tool_input":{"command":"probe c'"$i"'"},"session_id":"'"$SID"'","hook_event_name":"PostToolUse"}'
  OUT="$(printf '%s' "$PRE" | LEADV2_TOOL_FREQ_WARN=$FW LEADV2_TOOL_HARD_LIMIT=$HL \
        CLAUDE_PLUGIN_ROOT="${ROOT}/plugins/leadv2" bash "$HOOK" 2>&1 >/dev/null)"
  RC=$?
  case "$OUT" in *"WARN"*) FIRES="${FIRES} ${i}";; esac
  if [ "$RC" -ne 0 ]; then
    BLOCKS="${BLOCKS} ${i}"
    DENY_JSON="$(printf '%s' "$PRE" | LEADV2_TOOL_FREQ_WARN=$FW LEADV2_TOOL_HARD_LIMIT=$HL \
      CLAUDE_PLUGIN_ROOT="${ROOT}/plugins/leadv2" bash "$HOOK" 2>/dev/null)"
    continue
  fi
  printf '%s' "$POST" | LEADV2_TOOL_FREQ_WARN=$FW LEADV2_TOOL_HARD_LIMIT=$HL \
    CLAUDE_PLUGIN_ROOT="${ROOT}/plugins/leadv2" bash "$HOOK" >/dev/null 2>&1
done
[ "$FIRES" = " 5 10 12 20" ] && ok "freq-WARN fires exactly on anchors:${FIRES}" \
                              || bad "freq-WARN fired at:${FIRES} — expected 5 10 12 20 and silence between"
[ "$BLOCKS" = " 22" ] && ok "BLOCK still fires at the limit (call 22)" \
                       || bad "BLOCK behaviour changed: blocked at:${BLOCKS:- none}"
case "$DENY_JSON" in
  *'"permissionDecision": "deny"'*) ok "BLOCK carries deny JSON for the harness" ;;
  "") bad "BLOCK emitted no deny JSON" ;;
  *) bad "unexpected BLOCK output: $DENY_JSON" ;;
esac
N_ANCHORS="$(printf '%s' " 5 10 12 20" | wc -w | tr -d ' ')"
[ "$N_ANCHORS" -le 7 ] && ok "warn budget: ${N_ANCHORS} warns <= 7 per tool per session (was 17 repeated warns on this run shape)" \
                        || bad "warn budget exceeded: ${N_ANCHORS}"

# --- 4: sig-warn (identical call) still fires, once ---------------------------
SID="sig1"
SIGFIRES=""; SIGBLOCKS=""
for i in 1 2 3 4 5; do
  PRE='{"tool_name":"Bash","tool_input":{"command":"same-every-time"},"session_id":"'"$SID"'","hook_event_name":"PreToolUse"}'
  POST='{"tool_name":"Bash","tool_input":{"command":"same-every-time"},"session_id":"'"$SID"'","hook_event_name":"PostToolUse"}'
  OUT="$(printf '%s' "$PRE" | LEADV2_TOOL_FREQ_WARN=1000 LEADV2_TOOL_HARD_LIMIT=2000 \
        LEADV2_LOOP_WARN_AT=3 LEADV2_LOOP_HARD_AT=5 \
        CLAUDE_PLUGIN_ROOT="${ROOT}/plugins/leadv2" bash "$HOOK" 2>&1 >/dev/null)"
  RC=$?
  case "$OUT" in *"WARN"*) SIGFIRES="${SIGFIRES} ${i}";; esac
  if [ "$RC" -ne 0 ]; then SIGBLOCKS="${SIGBLOCKS} ${i}"; continue; fi
  printf '%s' "$POST" | LEADV2_TOOL_FREQ_WARN=1000 LEADV2_TOOL_HARD_LIMIT=2000 \
    LEADV2_LOOP_WARN_AT=3 LEADV2_LOOP_HARD_AT=5 \
    CLAUDE_PLUGIN_ROOT="${ROOT}/plugins/leadv2" bash "$HOOK" >/dev/null 2>&1
done
[ "$SIGFIRES" = " 3" ] && ok "sig-WARN fires once, at the 3rd identical call" \
                        || bad "sig-WARN fired at:${SIGFIRES} — expected only 3"
[ "$SIGBLOCKS" = " 5" ] && ok "sig-BLOCK still fires at the 5th identical call" \
                         || bad "sig-BLOCK changed: blocked at:${SIGBLOCKS:- none}"

rm -f "/tmp/leadv2-loop-detect-${SID}.json" "/tmp/leadv2-loop-detect-freq1.json"
echo "passed=${PASS} failed=${FAIL}"
[ "$FAIL" -eq 0 ]
