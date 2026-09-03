#!/usr/bin/env bash
# test-leadv2-lead-delegation-nudge.sh — NUDGE-TAX-01 firing budget.
#
# The nudge used to fire on EVERY Bash/Read past streak 6 — measured 39,230
# fires/10d, one situation re-fired ~895x in a single run. The fix fires on
# doubling anchors (6, 16, 36, 76, 156, ...). This suite locks:
#   1. the hook's own case still fires — crossing 6 emits the message;
#   2. a 220-call non-delegating run costs EXACTLY the 5 anchor fires
#      (budget: fires <= log2(220/6)+1 = 6; the old hook would fire 215);
#   3. the stored gap doubles, so longer runs stay O(log n);
#   4. an Agent call still resets the streak (delegation clears the pressure);
#   5. legacy bare-integer state files still parse (one transient fire).
set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${TEST_DIR}/../../../.." && pwd)"
HOOK="${ROOT}/plugins/leadv2/hooks/leadv2-lead-delegation-nudge.sh"
[ -f "$HOOK" ] || { echo "FAIL: nudge hook missing: $HOOK"; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/nudge-budget.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
HOME_SBOX="${TMP}/home"
mkdir -p "${HOME_SBOX}"

call_hook() { # <tool> <sid> -> emits hook stderr
  printf '{"tool_name":"%s","session_id":"%s","transcript_path":"/tmp/x.jsonl"}' "$1" "$2" \
    | HOME="${HOME_SBOX}" bash "$HOOK" 2>&1 >/dev/null
}

# --- 1+2: 220 direct calls, exact anchor fires, budget never exceeded --------
SID="budget1"
FIRES=0
FIRE_AT=""
for i in $(seq 1 220); do
  OUT="$(call_hook Bash "$SID")"
  if [ -n "$OUT" ]; then
    case "$OUT" in
      *"[leadv2-lead-delegation-nudge] lead has done 6 direct tool calls"*"Spawn Agent"*)
        [ "$i" -eq 6 ] && ok "own case fires: crossing 6 emits the nudge at call 6" \
                        || bad "own case: first fire at call $i, expected 6"
        ;;
      *"[leadv2-lead-delegation-nudge]"*) : ;;
      *) bad "call $i produced non-nudge stderr: $OUT" ;;
    esac
    FIRES=$((FIRES + 1))
    FIRE_AT="${FIRE_AT} ${i}"
  fi
done
[ "$FIRES" -eq 5 ] && ok "220-call run fires exactly at anchors:${FIRE_AT}" \
                   || bad "220-call run fired ${FIRES}x at:${FIRE_AT} — expected 5 fires at 6 16 36 76 156"
if [ "$FIRES" -le 6 ]; then
  ok "firing budget holds: ${FIRES} <= 6 fires per 220-call run"
else
  bad "FIRING BUDGET EXCEEDED: ${FIRES} fires in a 220-call run (max 6)"
fi

# --- 3: stored gap doubled along the way -------------------------------------
STREAK_FILE="${HOME_SBOX}/.claude/state/leadv2/${SID}.lead-streak"
GAP="$(cut -d' ' -f3 "${STREAK_FILE}")"
[ "$GAP" -ge 160 ] && ok "gap escalated to ${GAP} (doubling keeps long runs O(log n))" \
                   || bad "gap did not escalate (got ${GAP}, want >=160)"

# --- 4: Agent resets ----------------------------------------------------------
call_hook Agent "$SID" >/dev/null 2>&1
OUT="$(call_hook Bash "$SID")"
[ -z "$OUT" ] && ok "Agent call resets the streak (no fire on the next direct call)" \
               || bad "streak survived an Agent call: $OUT"
for _ in 1 2 3 4 5; do OUT="$(call_hook Bash "$SID")"; done
case "$OUT" in
  *"lead has done 6 direct tool calls"*) ok "post-reset re-crossing of 6 still fires" ;;
  *) bad "post-reset crossing of 6 did not fire: ${OUT:-<none>}" ;;
esac

# --- 5: legacy bare-integer state file ----------------------------------------
SID="legacy1"
mkdir -p "${HOME_SBOX}/.claude/state/leadv2"
printf '900\n' > "${HOME_SBOX}/.claude/state/leadv2/${SID}.lead-streak"
OUT="$(call_hook Bash "$SID")"
case "$OUT" in
  *"[leadv2-lead-delegation-nudge]"*) ok "legacy bare-integer state parses (transient fire)" ;;
  *) bad "legacy state file broke the hook: ${OUT:-<no fire>}" ;;
esac
OUT="$(call_hook Bash "$SID")"
[ -z "$OUT" ] && ok "no repeat fire right after the legacy transient (gap re-armed)" \
               || bad "legacy path re-fired on the next call: $OUT"

echo "passed=${PASS} failed=${FAIL}"
[ "$FAIL" -eq 0 ]
