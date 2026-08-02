#!/usr/bin/env bash
# Suite for hooks/leadv2-compact-warn.sh — the tiered context-budget guard (M-7).
#
# Drives the hook directly with a pre-seeded turn-count file and a synthetic
# {"session_id": ...} on stdin, then asserts on the raw JSON it emits.
# Does NOT depend on the broader /compact machinery.
#
# bash 3.2 (macOS) compatible: integer if/elif only, no associative arrays.
#
# Run: bash tests/test-compact-warn-tiers.sh
set -uo pipefail
# NOTE: no `set -e` — we manage exit codes ourselves so one failure doesn't abort.

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../hooks/leadv2-compact-warn.sh"

PASS=0
FAIL=0
FAILMSGS=()

ok()   { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); FAILMSGS+=("$1"); }

# Run the hook once with the given env and seeded state; echo its stdout.
# Usage: run_hook <count_seed> <fired_seed> [ENV=VAL ...]
run_hook() {
    local count_seed="$1" fired_seed="$2"; shift 2
    local sid="tier-test-$$-$RANDOM"
    local cf="/tmp/leadv2-turn-count-${sid}"
    local ff="/tmp/leadv2-tier-fired-${sid}"
    printf '%s\n' "$count_seed" > "$cf"
    if [[ -n "$fired_seed" ]]; then printf '%s\n' "$fired_seed" > "$ff"; else : > "$ff"; fi
    local out
    out="$(printf '{"session_id":"%s"}' "$sid" | env -u LEADV2_COMPACT_WARN "$@" bash "$HOOK" 2>/dev/null || true)"
    rm -f "$cf" "$ff"
    printf '%s' "$out"
}

# Extract the additionalContext string from a hook JSON payload (or "" if none).
ctx_of() { printf '%s' "$1" | python3 -c "import sys,json
try:
    d=json.loads(sys.stdin.read() or '{}')
    print(d.get('hookSpecificOutput',{}).get('additionalContext',''))
except Exception:
    print('')" 2>/dev/null; }

# ---- tests -------------------------------------------------------------------

# (1) MILD fires at the derived mild threshold, mentions MILD, never /compact.
C="$(run_hook 13 '' )"; X="$(ctx_of "$C")"
if [[ "$X" == "[CONTEXT_TIER:MILD]"* ]] && [[ "$X" != *"/compact"* ]]; then ok; else fail "mild: expected MILD marker w/o /compact, got [$X]"; fi

# (2) AGGRESSIVE fires at its threshold, distinct marker, never /compact.
C="$(run_hook 24 1 )"; X="$(ctx_of "$C")"
if [[ "$X" == "[CONTEXT_TIER:AGGRESSIVE]"* ]] && [[ "$X" != *"/compact"* ]]; then ok; else fail "aggressive: expected AGGRESSIVE marker w/o /compact, got [$X]"; fi

# (3) EMERGENCY fires at its threshold, distinct marker, mentions /compact.
C="$(run_hook 32 2 )"; X="$(ctx_of "$C")"
if [[ "$X" == "[CONTEXT_TIER:EMERGENCY]"* ]] && [[ "$X" == *"/compact"* ]]; then ok; else fail "emergency: expected EMERGENCY marker w/ /compact, got [$X]"; fi

# (4) tiers are distinguishable: mild != aggressive != emergency markers.
M="$(ctx_of "$(run_hook 13 '')")"; A="$(ctx_of "$(run_hook 24 1)")"; E="$(ctx_of "$(run_hook 32 2)")"
if [[ "$M" != "$A" ]] && [[ "$A" != "$E" ]] && [[ "$M" != "$E" ]]; then ok; else fail "distinguishable: markers not all distinct"; fi

# (5) LEADV2_COMPACT_WARN=0 disables: past emergency, no output, exit 0.
C="$(run_hook 200 0 LEADV2_COMPACT_WARN=0)"; X="$(ctx_of "$C")"
if [[ -z "$X" ]]; then ok; else fail "disabled: expected no output, got [$X]"; fi

# (6) edge-trigger: re-running same tier after fired => silent (no regress).
C="$(run_hook 30 2 )"; X="$(ctx_of "$C")"   # count=31, between aggressive(25) & emergency(33), fired=2
if [[ -z "$X" ]]; then ok; else fail "no-regress: expected silence at count31 fired2, got [$X]"; fi

# (7) jump-past: fired=0 but count past emergency => fires EMERGENCY once.
C="$(run_hook 49 0 )"; X="$(ctx_of "$C")"
if [[ "$X" == "[CONTEXT_TIER:EMERGENCY]"* ]]; then ok; else fail "jump-past: expected EMERGENCY, got [$X]"; fi

# (8) jump-past does not also fire lower tiers in the same invocation (one emit).
NLINES="$(printf '%s' "$C" | grep -c 'additionalContext' || true)"
if [[ "$NLINES" -eq 1 ]]; then ok; else fail "jump-past: expected exactly 1 emit, got $NLINES"; fi

# (9) legacy pin: LEADV2_COMPACT_THRESHOLD=80 overrides EMERGENCY to 80 only;
#     lower tiers stay measured, so count50 still fires AGGRESSIVE (not emergency),
#     and count80 fires EMERGENCY.
C="$(run_hook 49 0 LEADV2_COMPACT_THRESHOLD=80)"; X="$(ctx_of "$C")"
if [[ "$X" == "[CONTEXT_TIER:AGGRESSIVE]"* ]]; then ok; else fail "legacy-pin@50: lower tiers stay on; expected AGGRESSIVE, got [$X]"; fi
C="$(run_hook 79 2 LEADV2_COMPACT_THRESHOLD=80)"; X="$(ctx_of "$C")"
if [[ "$X" == "[CONTEXT_TIER:EMERGENCY]"* ]]; then ok; else fail "legacy-pin@80: expected EMERGENCY at count80, got [$X]"; fi

# (10) emergency re-warn: first fire at 33, then silent until 33+40=73.
C="$(run_hook 72 3 )"; X="$(ctx_of "$C")"   # count=73 => re-warn
if [[ "$X" == *"73 turns"* ]] && [[ "$X" == *"/compact"* ]]; then ok; else fail "rewarn@73: expected re-warn mentioning 73 turns, got [$X]"; fi
C="$(run_hook 73 3 )"; X="$(ctx_of "$C")"   # count=74 => silent
if [[ -z "$X" ]]; then ok; else fail "rewarn@74: expected silence, got [$X]"; fi

# (11) degrade: nonsensical overrides (mild>=aggressive) => measured defaults.
C="$(run_hook 13 '' LEADV2_COMPACT_TIER_MILD=50 LEADV2_COMPACT_TIER_AGGRESSIVE=10)"; X="$(ctx_of "$C")"
if [[ "$X" == "[CONTEXT_TIER:MILD]"* ]]; then ok; else fail "degrade: bad overrides should fall to defaults and fire MILD at 14, got [$X]"; fi

# (12) turn-count state file format is a bare integer (back-compat with old hook).
SID="fmt-$$-$RANDOM"; CF="/tmp/leadv2-turn-count-${SID}"
printf '7\n' > "$CF"; : > "/tmp/leadv2-tier-fired-${SID}"
printf '{"session_id":"%s"}' "$SID" | env -u LEADV2_COMPACT_WARN bash "$HOOK" >/dev/null 2>&1 || true
V="$(cat "$CF" 2>/dev/null | tr -d '[:space:]')"
if [[ "$V" =~ ^[0-9]+$ ]] && [[ "$V" -eq 8 ]]; then ok; else fail "count-format: expected bare int 8, got [$V]"; fi
rm -f "$CF" "/tmp/leadv2-tier-fired-${SID}"

# (13) corrupt tier-fired value is clamped, not bricking the guard:
#      fired=9 (corrupt) + a rewarn boundary (count->73) => EMERGENCY rewarn fires.
C="$(run_hook 72 9 )"; X="$(ctx_of "$C")"
if [[ "$X" == "[CONTEXT_TIER:EMERGENCY]"* ]] && [[ "$X" == *"73 turns"* ]]; then ok; else fail "clamp: corrupt fired=9 should clamp and still rewarn at 73, got [$X]"; fi

# ---- report -----------------------------------------------------------------
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
    for m in "${FAILMSGS[@]}"; do echo "  FAIL: $m"; done
    exit 1
fi
exit 0
