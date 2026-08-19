#!/usr/bin/env bash
# PreToolUse(Monitor) hook — hard Monitor-cap gate (TOKEN-ECONOMY-ACTIONS-01).
#
# A Monitor's cost is per-turn, not per-event: every event and every
# background-command completion is appended to the conversation and re-sent
# on every later turn, so overlapping watchers on the same journal multiply
# the cost. This hook counts how many Monitor tool_use entries already exist
# in the live transcript and denies arming a 5th+ one.
#
#   <=2   -> allow, silent
#   3-4   -> allow, stdout advisory
#   >=5   -> deny (PreToolUse JSON), advising TaskStop or batching greps
#
# Escape hatch: LEADV2_MONITORCAP_OFF=1 -> exit 0 unconditionally (allow).

set -euo pipefail
trap 'echo "[$0] error at line $LINENO" >&2; exit 0' ERR

[[ "${LEADV2_MONITORCAP_OFF:-0}" == "1" ]] && exit 0

INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0

TRANSCRIPT="$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    r = json.loads(sys.stdin.read())
    print(r.get('transcript_path', ''))
except Exception:
    pass
" 2>/dev/null || true)"

[[ -z "$TRANSCRIPT" ]] && exit 0
[[ ! -r "$TRANSCRIPT" ]] && exit 0

COUNT="$(grep -c '"name":"Monitor"' "$TRANSCRIPT" 2>/dev/null || echo 0)"
COUNT="${COUNT//[$'\n\r ']/}"
[[ "$COUNT" =~ ^[0-9]+$ ]] || COUNT=0

if [[ "$COUNT" -ge 5 ]]; then
    python3 -c "
import json
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': 'MONITOR-CAP: 5 Monitors already armed this session — TaskStop an old one or batch patterns into one grep -E'
    }
}))
"
    exit 0
fi

if [[ "$COUNT" -ge 3 ]]; then
    echo "MONITOR-CAP advisory: ${COUNT} Monitors already armed this session — prefer batching grep patterns (A|B|C) into one Monitor over arming another."
fi

exit 0
