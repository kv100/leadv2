#!/usr/bin/env bash
# UserPromptSubmit hook — tiered context-budget guard (M-7).
#
# Tracks the per-session turn count and fires ONE of three proportional,
# EDGE-TRIGGERED tiers as context fills. Each tier fires exactly once per
# session; tiers never regress. NON-BLOCKING: exit 0 always. Never forces
# /compact — emergency merely asks for it.
#
#   MILD        [CONTEXT_TIER:MILD]         trim verbose surfaces        (no compact)
#   AGGRESSIVE  [CONTEXT_TIER:AGGRESSIVE]   summarize closed threads     (no compact)
#   EMERGENCY   [CONTEXT_TIER:EMERGENCY]    run /compact now             (re-warns every REWARN)
#
# The three tiers have disjoint instruction bodies and distinct markers; MILD
# and AGGRESSIVE never mention /compact.
#
# State files (the turn-count file is byte-identical in format to the old
# single-threshold hook, so an older copy of this hook running concurrently in
# another repo still reads it; the tier-fired file is new and ignored by old
# copies):
#   /tmp/leadv2-turn-count-${SESSION_ID}     bare int: current turn count
#   /tmp/leadv2-tier-fired-${SESSION_ID}     highest tier already fired: 0|1|2|3
#
# Thresholds are MEASURED defaults, not picked numbers (house rule
# feedback-derive-alert-thresholds-from-config). Derived from session
# transcripts by scripts/leadv2-turn-cost-measure.py:
#   b = 100,995     median turn-1 baseline context
#   m = 9,881 tok   median per-session per-turn slope (n=196 sessions, turns 1..12)
#   C = 527,155     p95 of per-session peak context
#   T(x) = ceil((x*C - b) / m)   at  x=0.45 / 0.65 / 0.80
# The fraction rule (authored, not picked): 0.45 = still over half the window
# free, trimming is cheap and non-disruptive; 0.65 = under a third free, cheap
# trimming no longer closes the gap; 0.80 = one large tool result from the wall.
# The old single threshold of 80 sat ~47 turns past the 0.80*C crossing (turn
# 33) — the guard arrived after the useful trimming window. Full measurement +
# arithmetic: docs/context-tier-guard.md.
#
# Env contract (all optional, backward compatible):
#   LEADV2_COMPACT_WARN=0              disable entirely (exit 0, nothing fires)
#   LEADV2_COMPACT_TIER_MILD=N         override mild turn threshold
#   LEADV2_COMPACT_TIER_AGGRESSIVE=N   override aggressive
#   LEADV2_COMPACT_TIER_EMERGENCY=N    override emergency
#   LEADV2_COMPACT_THRESHOLD=N         LEGACY PIN: if set & positive, overrides
#                                      EMERGENCY (an operator who pinned 80 keeps
#                                      a compact demand at 80). Supersets the old
#                                      80/+40 behaviour: same action, same
#                                      re-warn cadence, threshold now measured.
#   LEADV2_COMPACT_REWARN=40           emergency re-warn interval (default 40)
# A nonsensical override set (non-positive, or not strictly
# mild<aggressive<emergency) degrades to the measured defaults rather than
# firing silently wrong.
#
# bash 3.2 (macOS): integer if/elif only — no associative arrays, no ${x,,}.

set -euo pipefail
trap 'echo "["$0"] error at line $LINENO" >&2; exit 0' ERR

[[ "${LEADV2_COMPACT_WARN:-1}" == "0" ]] && exit 0

INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0

SESSION_ID="$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    r = json.loads(sys.stdin.read())
    print(r.get('session_id', ''))
except Exception:
    pass
" 2>/dev/null || true)"
[[ -z "$SESSION_ID" ]] && exit 0

# --- measured defaults (re-derive via scripts/leadv2-turn-cost-measure.py) -----
DEF_MILD=14
DEF_AGGRESSIVE=25
DEF_EMERGENCY=33
REWARN="${LEADV2_COMPACT_REWARN:-40}"
if ! [[ "$REWARN" =~ ^[0-9]+$ ]] || [[ "$REWARN" -le 0 ]]; then
    REWARN=40
fi

# --- resolve thresholds from env, validating each as a positive integer --------
pos_int_or() {  # $1=env var name  $2=default  -> echoes value if valid else default
    local v="${!1:-$2}"
    if [[ "$v" =~ ^[0-9]+$ ]] && [[ "$v" -gt 0 ]]; then
        printf '%s' "$v"
    else
        printf '%s' "$2"
    fi
}

MILD="$(pos_int_or LEADV2_COMPACT_TIER_MILD "$DEF_MILD")"
AGGRESSIVE="$(pos_int_or LEADV2_COMPACT_TIER_AGGRESSIVE "$DEF_AGGRESSIVE")"
EMERGENCY="$(pos_int_or LEADV2_COMPACT_TIER_EMERGENCY "$DEF_EMERGENCY")"

# legacy pin: LEADV2_COMPACT_THRESHOLD overrides emergency (old 80-turn behaviour)
if [[ -n "${LEADV2_COMPACT_THRESHOLD:-}" ]] \
   && [[ "${LEADV2_COMPACT_THRESHOLD}" =~ ^[0-9]+$ ]] \
   && [[ "${LEADV2_COMPACT_THRESHOLD}" -gt 0 ]]; then
    EMERGENCY="$LEADV2_COMPACT_THRESHOLD"
fi

# order sanity: must be strictly mild < aggressive < emergency, else degrade
if ! { [[ "$MILD" -lt "$AGGRESSIVE" ]] && [[ "$AGGRESSIVE" -lt "$EMERGENCY" ]]; }; then
    MILD="$DEF_MILD"
    AGGRESSIVE="$DEF_AGGRESSIVE"
    EMERGENCY="$DEF_EMERGENCY"
fi

# --- increment turn count (format unchanged: bare integer) --------------------
COUNT_FILE="/tmp/leadv2-turn-count-${SESSION_ID}"
FIRED_FILE="/tmp/leadv2-tier-fired-${SESSION_ID}"

PREV="$(cat "$COUNT_FILE" 2>/dev/null || echo '0')"
PREV="${PREV// /}"
[[ ! "$PREV" =~ ^[0-9]+$ ]] && PREV=0
COUNT=$(( PREV + 1 ))
printf '%d\n' "$COUNT" > "$COUNT_FILE"

FIRED="$(cat "$FIRED_FILE" 2>/dev/null || echo '0')"
FIRED="${FIRED// /}"
[[ ! "$FIRED" =~ ^[0-9]+$ ]] && FIRED=0
# clamp to a sane tier range — a corrupt/stale value >3 would brick the guard
# (TIER>FIRED never true; rewarn requires FIRED==3).
[[ "$FIRED" -gt 3 ]] && FIRED=3

# --- classify current tier ----------------------------------------------------
# tier(): 0 below mild, 1 mild, 2 aggressive, 3 emergency
if [[ "$COUNT" -ge "$EMERGENCY" ]]; then
    TIER=3
elif [[ "$COUNT" -ge "$AGGRESSIVE" ]]; then
    TIER=2
elif [[ "$COUNT" -ge "$MILD" ]]; then
    TIER=1
else
    TIER=0
fi

# --- decide whether to emit ---------------------------------------------------
# edge-trigger: fire when TIER exceeds the highest previously fired tier.
# emergency additionally re-warns every REWARN turns after first crossing.
EMIT=0
MARKER=""
INSTRUCTION=""
if [[ "$TIER" -gt "$FIRED" ]]; then
    EMIT=1
    FIRED="$TIER"
    case "$TIER" in
        1)
            MARKER="[CONTEXT_TIER:MILD]"
            INSTRUCTION="Context is filling. Trim verbose surfaces to keep token cost flat: bound every Read with limit=, do not re-read files already in context, pipe head/tail/grep at the source instead of trimming after, and avoid pasting raw logs. Continue normally."
            ;;
        2)
            MARKER="[CONTEXT_TIER:AGGRESSIVE]"
            INSTRUCTION="Context is over half full and cheap trimming will not close the gap. Summarize and close finished threads first: append journal lines for closed lanes, prune resolved rows from docs/leadv2/open-threads.md, and collapse each completed lane to one line. Then continue."
            ;;
        3)
            MARKER="[CONTEXT_TIER:EMERGENCY]"
            INSTRUCTION="Context is at ~80% of the working ceiling — one large tool result from the wall. Run /compact now (the pre-compact checkpoint hook freezes state first). This re-warns every ${REWARN} turns until you do."
            ;;
    esac
elif [[ "$TIER" -eq 3 ]] && [[ "$FIRED" -eq 3 ]]; then
    OVER=$(( COUNT - EMERGENCY ))
    if [[ "$OVER" -gt 0 ]] && [[ $(( OVER % REWARN )) -eq 0 ]]; then
        EMIT=1
        MARKER="[CONTEXT_TIER:EMERGENCY]"
        INSTRUCTION="Still past the emergency turn count (${COUNT} turns). Run /compact now to reset context."
    fi
fi

# Persist the fired tier ONLY after a successful emit. Persisting before the
# emit would mark a tier fired even if python3 failed, permanently skipping
# that warning. (In the no-emit path FIRED is unchanged and need not be written.)
if [[ "$EMIT" -eq 1 ]]; then
    if MARKER="$MARKER" INSTRUCTION="$INSTRUCTION" python3 -c "
import os, json
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'UserPromptSubmit',
        'additionalContext': os.environ['MARKER'] + ' ' + os.environ['INSTRUCTION']
    }
}))
"; then
        printf '%d\n' "$FIRED" > "$FIRED_FILE"
    fi
fi

exit 0
