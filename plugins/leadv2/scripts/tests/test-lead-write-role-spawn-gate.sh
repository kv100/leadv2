#!/usr/bin/env bash
# scripts/tests/test-lead-write-role-spawn-gate.sh -- pins the LEAD path of
# leadv2-routing-guard.sh against write-capable roles
# (LEAD-CAN-SPAWN-A-WRITE-ROLE-WITHOUT-THE-ARBITER-01, 2026-09-12).
#
# Before the fix, the same hook, same payload, one field different:
#   caller = SUBAGENT (agent_type present) -> DENIED write-capable role, rc=2
#   caller = LEAD (no agent_type)          -> rc=0, no output at all
# The lead is the only actor that can start a lane, and it was the one waved
# through — a direct Agent spawn skipping estimate -> balancer -> arbiter ->
# phases in one call.
#
# Tests:
#   T1. bash -n on the hook.
#   T2. Every write-capable role from the LEAD -> rc=2 AND the refusal names
#       leadv2-dispatch-code.sh (a block with no remedy just gets bypassed).
#   T3. Positive controls: Explore/haiku and recon/haiku from the LEAD stay
#       allowed (rc=0). A guard that refuses everything is an outage, not a
#       fix.
#   T4. critic+sonnet from the LEAD -> rc=0 (the warn-only advisory path is
#       preserved; only the write-role list blocks).
#   T5. Nested path unchanged: caller=explore targeting developer -> rc=2,
#       audit reason route.subrun.write_role_denied. ONE list, both paths.
#   T6. Escape hatch: LEADV2_LEAD_WRITE_SPAWN_ALLOW=1 -> rc=0, stderr says
#       OVERRIDE ACTIVE, and the use is journalled
#       (verdict=override_allow, target, why) to docs/leadv2/
#       lead-write-spawn-overrides.log under the payload cwd.
#   T7. DECLARED NEGATIVE CONTROL: anchored mutation (count==1 on an exact
#       source string) disables the lead-path gate; the mutant must evade T2
#       (rc=0). If the mutant is still refused, the control is not
#       falsifiable and this suite FAILS.
#
# Run: bash scripts/tests/test-lead-write-role-spawn-gate.sh
# Exit 0 = all pass; non-zero = failures found.
# run-all-triggers: leadv2-routing-guard

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD_SH="${SCRIPT_DIR}/../../hooks/leadv2-routing-guard.sh"

PASS=0
FAIL=0
ERRORS=()

log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMPROOT="$(lv2_mktemp_dir "lead-write-role-gate-test")"
trap 'rm -rf "$TMPROOT"' EXIT

# Build hook input JSON: caller=$1 ('' = lead), subagent_type=$2, model=$3, cwd=$4.
_make_input() {
  local caller="$1" stype="$2" model="$3" cwd="$4"
  python3 -c "
import json, sys
d = {'tool_input': {'subagent_type': sys.argv[2], 'model': sys.argv[3], 'prompt': 'x'},
     'cwd': sys.argv[4]}
if sys.argv[1]:
    d['agent_type'] = sys.argv[1]
print(json.dumps(d))
" "$caller" "$stype" "$model" "$cwd"
}

# Run the guard on input $1 with extra env assignments; prints combined output,
# sets global RC.
RC=0
_run_guard() {
  local input="$1"; shift
  RC=0
  env -u LEADV2_LEAD_WRITE_SPAWN_ALLOW -u LEADV2_LEAD_WRITE_SPAWN_WHY "$@" \
    bash "$GUARD_SH" <<< "$input" > "$TMPROOT/last.out" 2>&1 || RC=$?
  cat "$TMPROOT/last.out"
}

# T1 ── syntax ────────────────────────────────────────────────────────────────
if bash -n "$GUARD_SH" 2>&1; then
  pass "T1: bash -n leadv2-routing-guard.sh"
else
  fail "T1: hook has bash syntax errors"
fi

# T2 ── every write-capable role refused from the lead, with a remedy ─────────
T2_FAILS=0
for role in developer frontend-developer postgres-pro devops-engineer architect product-owner general-purpose; do
  _run_guard "$(_make_input '' "$role" sonnet "$TMPROOT")"
  if [[ "$RC" -ne 2 ]]; then
    fail "T2: lead path allowed write role '$role' (rc=$RC, expected 2)"
    T2_FAILS=$((T2_FAILS + 1))
  elif ! grep -q "leadv2-dispatch-code.sh" "$TMPROOT/last.out"; then
    fail "T2: refusal for '$role' does not name leadv2-dispatch-code.sh (a block with no remedy gets bypassed)"
    T2_FAILS=$((T2_FAILS + 1))
  fi
done
[[ "$T2_FAILS" -eq 0 ]] && pass "T2: all 7 write-capable roles refused from the lead (rc=2, remedy named)"

# T3 ── read-only roles stay allowed from the lead ────────────────────────────
for pair in "Explore:haiku" "recon:haiku"; do
  stype="${pair%%:*}"; model="${pair##*:}"
  _run_guard "$(_make_input '' "$stype" "$model" "$TMPROOT")"
  if [[ "$RC" -ne 0 ]]; then
    fail "T3: over-blocked read-only role '$stype/$model' from the lead (rc=$RC)"
  else
    pass "T3: read-only $stype/$model allowed from the lead"
  fi
done

# T4 ── warn-only advisory path preserved (critic on sonnet) ──────────────────
_run_guard "$(_make_input '' critic sonnet "$TMPROOT")"
if [[ "$RC" -ne 0 ]]; then
  fail "T4: critic/sonnet from the lead now blocks (rc=$RC) — warn-only advisory must be preserved"
else
  pass "T4: critic/sonnet from the lead still warn-only (rc=0)"
fi

# T5 ── nested path unchanged (one list, both paths) ──────────────────────────
T5DIR="$TMPROOT/nested-cwd"; mkdir -p "$T5DIR"
_run_guard "$(_make_input explore developer sonnet "$T5DIR")"
if [[ "$RC" -ne 2 ]]; then
  fail "T5: nested developer spawn no longer denied (rc=$RC, expected 2)"
elif [[ ! -f "$T5DIR/docs/leadv2/nested-spawns.log" ]] \
  || ! grep -q "route.subrun.write_role_denied" "$T5DIR/docs/leadv2/nested-spawns.log"; then
  fail "T5: nested denial did not audit route.subrun.write_role_denied"
else
  pass "T5: nested write-role denial unchanged (rc=2 + audit reason)"
fi

# T6 ── escape hatch is loud and journaled ────────────────────────────────────
T6DIR="$TMPROOT/override-cwd"; mkdir -p "$T6DIR"
_run_guard "$(_make_input '' developer sonnet "$T6DIR")" \
  LEADV2_LEAD_WRITE_SPAWN_ALLOW=1 LEADV2_LEAD_WRITE_SPAWN_WHY=why-test-fixture
if [[ "$RC" -ne 0 ]]; then
  fail "T6: escape hatch did not allow the spawn (rc=$RC, expected 0)"
elif ! grep -q "OVERRIDE ACTIVE" "$TMPROOT/last.out"; then
  fail "T6: override allowed the spawn but was not announced on stderr"
elif [[ ! -f "$T6DIR/docs/leadv2/lead-write-spawn-overrides.log" ]] \
  || ! grep -q "caller=lead target=developer .*why=why-test-fixture verdict=override_allow" \
       "$T6DIR/docs/leadv2/lead-write-spawn-overrides.log"; then
  fail "T6: override use not journalled (verdict=override_allow + target + why)"
else
  pass "T6: override allowed, announced, and journalled"
fi

# T7 ── DECLARED NEGATIVE CONTROL ─────────────────────────────────────────────
# Mutation (anchored, exactly-once on the REAL hook): disable the lead-path
# gate line so the lead can spawn write roles again — the exact defect this
# row exists to end. The suite must be able to see that defect (the mutant
# evades T2), or the suite is not falsifiable and cannot be trusted green.
ANCHOR='if _is_write_role "$SUBAGENT_TYPE"; then   # LEAD-WRITE-ROLE-GATE'
REPLACEMENT='if false; then   # LEAD-WRITE-ROLE-GATE (mutated: gate disabled)'
ANCHOR_COUNT="$(python3 -c "
import sys
src = open(sys.argv[1]).read()
sys.stdout.write(str(src.count(sys.argv[2])))
" "$GUARD_SH" "$ANCHOR")"

if [[ "$ANCHOR_COUNT" != "1" ]]; then
  fail "T7: mutation anchor found ${ANCHOR_COUNT}x (expected exactly 1) — re-anchor on the real source, do not silence the control"
else
  MUT="$TMPROOT/guard-mutated.sh"
  cp "$GUARD_SH" "$MUT"
  python3 - "$MUT" "$ANCHOR" "$REPLACEMENT" <<'PY' || fail "T7: mutation application failed"
import sys
path, anchor, repl = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path).read()
n = src.count(anchor)
if n != 1:
    sys.exit('anchor found %dx in mutant copy (expected 1)' % n)
open(path, 'w').write(src.replace(anchor, repl, 1))
PY
  if bash -n "$MUT" 2>/dev/null; then
    # Run the T2 assertion against the mutant: the gate is gone, so the lead
    # path must now let the write role through (rc=0) — i.e. this suite's own
    # demand of rc=2 goes RED against the mutant.
    GUARD_SH_SAVED="$GUARD_SH"; GUARD_SH="$MUT"
    _run_guard "$(_make_input '' developer sonnet "$TMPROOT")"
    MUT_RC="$RC"
    GUARD_SH="$GUARD_SH_SAVED"
    if [[ "$MUT_RC" -eq 2 ]]; then
      fail "T7 (red): control not falsifiable — mutant still refuses (rc=2); the anchor was replaced but nothing real changed"
    elif [[ "$MUT_RC" -eq 0 ]]; then
      pass "T7 (red): NEGATIVE CONTROL RED — gate-disabled mutant lets lead+developer through (rc=0); this suite's rc=2 demand fails against it, so T2 discriminates the defect"
    else
      fail "T7 (red): unexpected mutant rc=$MUT_RC (wanted the gate gone -> rc=0)"
    fi
  fi
fi

# ── summary ──────────────────────────────────────────────────────────────────
echo "---"
echo "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
