#!/usr/bin/env bash
# test-phase-precondition.sh — guard matrix for _phase_precondition_guard
# PHASES-ARE-THE-ONLY-PATH-01 §11 test suite 2.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PHASE_RECORD="${SCRIPT_DIR}/../leadv2-phase-record.sh"
DISPATCH_BIN="${SCRIPT_DIR}/../leadv2-dispatch-code.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export LEADV2_PROJECT_ROOT="$TMP_ROOT"
export LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/.cache"
export LEADV2_JOURNAL_BIN="${TMP_ROOT}/journal.sh"

# Stub journal that records lines to a file
JOURNAL_LOG="${TMP_ROOT}/journal.log"
cat > "${LEADV2_JOURNAL_BIN}" <<'JEOF'
#!/usr/bin/env bash
echo "$@" >> "${LEADV2_JOURNAL_LOG}" 2>/dev/null || true
JEOF
chmod +x "${LEADV2_JOURNAL_BIN}"
export LEADV2_JOURNAL_LOG

PASS=0
FAIL=0
ok() { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1" >&2; }

# We test phase-record.sh assert directly (it's what the guard calls)

# ── Test 1: Standard, no plan/gate1 → missing=csv on stdout, exit 3 ───────────
printf 'test: Standard missing plan/gate1\n'
OUT="$(bash "$PHASE_RECORD" assert deadbeef --class Standard 2>/dev/null)"; rc=$?
if [[ $rc -eq 3 ]]; then
  ok
else
  fail "assert Standard should exit 3 (got $rc)"
fi
if printf '%s' "$OUT" | grep -q '^missing='; then
  ok
else
  fail "assert should print missing= csv"
fi
if printf '%s' "$OUT" | grep -q 'plan'; then
  ok
else
  fail "missing should include plan"
fi

# ── Test 2: --waiver review=anything → exit 4 ─────────────────────────────────
printf 'test: waiver review refused\n'
for cls in Trivial Light Standard Heavy; do
  bash "$PHASE_RECORD" assert test01 --class "$cls" --waiver "review=anything" 2>/dev/null; rc=$?
  if [[ $rc -eq 4 ]]; then
    ok
  else
    fail "review waiver should exit 4 for class=$cls (got $rc)"
  fi
done

# ── Test 3: --waiver close=anything → exit 4 ─────────────────────────────────
printf 'test: waiver close refused\n'
for cls in Trivial Light Standard Heavy; do
  bash "$PHASE_RECORD" assert test02 --class "$cls" --waiver "close=anything" 2>/dev/null; rc=$?
  if [[ $rc -eq 4 ]]; then
    ok
  else
    fail "close waiver should exit 4 for class=$cls (got $rc)"
  fi
done

# ── Test 4: --waiver plan= (empty reason) → exit 4 ───────────────────────────
printf 'test: waiver empty reason\n'
bash "$PHASE_RECORD" assert test03 --class Standard --waiver "plan=" 2>/dev/null; rc=$?
if [[ $rc -eq 4 ]]; then
  ok
else
  fail "empty reason waiver should exit 4 (got $rc)"
fi

# ── Test 5: phases.yaml with version: 2 → exit 4 ─────────────────────────────
printf 'test: phases.yaml version 2 rejected\n'
mkdir -p "${TMP_ROOT}/.claude/leadv2-overrides"
printf 'version: 2\n' > "${TMP_ROOT}/.claude/leadv2-overrides/phases.yaml"
bash "$PHASE_RECORD" assert test04 --class Standard 2>/dev/null; rc=$?
if [[ $rc -eq 4 ]]; then
  ok
else
  fail "version 2 should exit 4 (got $rc)"
fi

# ── Test 6: phases.yaml with class_overrides.Light.remove → exit 4 ────────────
printf 'test: phases.yaml removal key rejected\n'
cat > "${TMP_ROOT}/.claude/leadv2-overrides/phases.yaml" <<'YEOF'
version: 1
class_overrides:
  Light:
    remove:
      - review
YEOF
ERR="$(bash "$PHASE_RECORD" assert test05 --class Light 2>&1 1>/dev/null)"; rc=$?
if [[ $rc -eq 4 ]]; then
  ok
else
  fail "remove key should exit 4 (got $rc)"
fi
if printf '%s' "$ERR" | grep -q 'removals are not permitted'; then
  ok
else
  fail "error should name removals"
fi

# ── Test 7: phases.yaml with class_overrides.Light.mandatory: [e2e] → union ───
printf 'test: phases.yaml union adds e2e to Light\n'
cat > "${TMP_ROOT}/.claude/leadv2-overrides/phases.yaml" <<'YEOF'
version: 1
class_overrides:
  Light:
    mandatory:
      - e2e
YEOF
PLAN_OUT="$(bash "$PHASE_RECORD" plan-for --class Light 2>/dev/null)"
if printf '%s' "$PLAN_OUT" | grep -q 'MANDATORY.*e2e'; then
  ok
else
  fail "Light + override should make e2e mandatory"
fi

# ── Test 8: waiver plan accepted when in waivers_allowed ──────────────────────
printf 'test: waiver plan accepted\n'
cat > "${TMP_ROOT}/.claude/leadv2-overrides/phases.yaml" <<'YEOF'
version: 1
waivers_allowed:
  - plan
YEOF
bash "$PHASE_RECORD" assert w01 --class Standard --waiver "plan=no_prepass_needed" 2>/dev/null; rc=$?
if [[ $rc -eq 3 ]]; then
  # exit 3 is fine — plan is waived but gate1 still missing
  ok
else
  if [[ $rc -eq 0 ]]; then
    ok  # all satisfied somehow
  else
    fail "accepted waiver should not exit 4 (got $rc)"
  fi
fi
# Verify the waiver was recorded
if [[ -f "${TMP_ROOT}/docs/handoff/dispatch-w01/phases.d/plan.yaml" ]]; then
  if grep -q 'status: waived' "${TMP_ROOT}/docs/handoff/dispatch-w01/phases.d/plan.yaml" \
     && grep -q 'reason: no_prepass_needed' "${TMP_ROOT}/docs/handoff/dispatch-w01/phases.d/plan.yaml"; then
    ok
  else
    fail "waiver record missing fields"
  fi
else
  fail "waived plan.yaml not written"
fi

# ── Test 9: waiver plan NOT in waivers_allowed → exit 4 ───────────────────────
printf 'test: waiver plan not allowed\n'
rm -f "${TMP_ROOT}/.claude/leadv2-overrides/phases.yaml"
bash "$PHASE_RECORD" assert w02 --class Standard --waiver "plan=test" 2>/dev/null; rc=$?
if [[ $rc -eq 4 ]]; then
  ok
else
  fail "waiver not in waivers_allowed should exit 4 (got $rc)"
fi

# ── Test 10: no phases.yaml → base table, no crash ───────────────────────────
printf 'test: no phases.yaml → base table\n'
PLAN_OUT="$(bash "$PHASE_RECORD" plan-for --class Trivial 2>/dev/null)"; rc=$?
if [[ $rc -eq 0 ]]; then
  ok
else
  fail "plan-for Trivial should succeed without phases.yaml (got $rc)"
fi
if printf '%s' "$PLAN_OUT" | grep -q 'MANDATORY.*classify'; then
  ok
else
  fail "Trivial should have classify mandatory"
fi
if printf '%s' "$PLAN_OUT" | grep -q 'MANDATORY.*review'; then
  ok
else
  fail "Trivial should have review mandatory"
fi

printf '\n[PHASE-PRECONDITION] pass=%d fail=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
