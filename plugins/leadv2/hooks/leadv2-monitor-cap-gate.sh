#!/usr/bin/env bash
# PreToolUse(Monitor) hook — hard Monitor-cap gate (TOKEN-ECONOMY-ACTIONS-01).
#
# A Monitor's cost is per-turn, not per-event: every event and every
# background-command completion is appended to the conversation and re-sent
# on every later turn, so overlapping watchers on the same journal multiply
# the cost. This hook counts how many Monitor tool_use entries already exist
# in the live transcript and denies arming a 5th+ one.
#
# MONITOR-CAP-UNBLOCK-01 (founder order 2026-08-21): the hard deny is OFF by
# default. It was blocking real work — a lead that needed a sixth watcher had no
# way forward, because the count is over the WHOLE transcript, so the deny message's
# own advice ("TaskStop an old one") could never free a slot. Stopping a Monitor
# does not decrement this counter and never did.
#
# The advisory stays: the cost model behind it is real (every event is appended to
# the conversation and re-sent on every later turn), so a lead arming many watchers
# still gets told to batch patterns into one grep -E. Advice, not a wall.
#
#   < advisory  -> allow, silent
#   >= advisory -> allow, stdout advisory (default 3)
#   >= deny     -> deny (default 1000000 — effectively never)
#
# Tunables: LEADV2_MONITOR_DENY_AT, LEADV2_MONITOR_ADVISE_AT.
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

DENY_AT="${LEADV2_MONITOR_DENY_AT:-1000000}"
ADVISE_AT="${LEADV2_MONITOR_ADVISE_AT:-3}"
[[ "$DENY_AT" =~ ^[0-9]+$ ]] || DENY_AT=1000000
[[ "$ADVISE_AT" =~ ^[0-9]+$ ]] || ADVISE_AT=3

if [[ "$COUNT" -ge "$DENY_AT" ]]; then
    # Note the wording: the count is transcript-wide, so a TaskStop cannot lower it.
    # Only raising LEADV2_MONITOR_DENY_AT or LEADV2_MONITORCAP_OFF=1 clears this.
    COUNT="$COUNT" DENY_AT="$DENY_AT" python3 -c "
import json, os
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': 'MONITOR-CAP: %s Monitors armed this session, deny threshold %s. This count is transcript-wide, so TaskStop will NOT lower it — batch patterns into one grep -E, or raise LEADV2_MONITOR_DENY_AT / set LEADV2_MONITORCAP_OFF=1.' % (os.environ['COUNT'], os.environ['DENY_AT'])
    }
}))
"
    exit 0
fi

if [[ "$COUNT" -ge "$ADVISE_AT" ]]; then
    echo "MONITOR-CAP advisory: ${COUNT} Monitors armed this session — each event is re-sent on every later turn, so prefer batching patterns (A|B|C) into one Monitor. Not a block."
fi

exit 0
