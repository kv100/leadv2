#!/usr/bin/env bash
# test-phase-precondition-bootstrap.sh — DISPATCH-PHASE-DEADLOCK-01.
#
# Covers the deadlock where every brand-new Standard/Heavy lane was refused
# because _verify_artifact only accepted machine-produced proof for plan/
# gate1 (context.yaml.decisions / architect-prepass.md / .gate1-passed) —
# none of which exist before a worker has ever run. Two independent fixes
# under test here:
#
#   1. PHASE-BOOTSTRAP-01: a lane with ZERO phase records at all is at
#      bootstrap, not in violation — cmd_assert admits it. The instant any
#      phase record exists, bootstrap is over and enforcement is exactly as
#      before (acceptance criteria 1, 2, 5).
#   2. Lead-authored proof: a brief/fix-round file is admissible plan
#      evidence, and an explicit --reason is admissible gate1 evidence — both
#      stamped `attested`, never `verified` (acceptance criteria 3, 4).
#
# Every case drives leadv2-phase-record.sh directly against a fixture
# handoff tree under a throwaway TMP_ROOT — never a real lane, never the real
# dispatch ledger or state root.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE_RECORD="${SCRIPT_DIR}/../leadv2-phase-record.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export LEADV2_PROJECT_ROOT="$TMP_ROOT"
export LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/.cache"
export LEADV2_JOURNAL_BIN="${TMP_ROOT}/journal.sh"

JOURNAL_LOG="${TMP_ROOT}/journal.log"
cat > "${LEADV2_JOURNAL_BIN}" <<'JEOF'
#!/usr/bin/env bash
echo "$@" >> "${LEADV2_JOURNAL_LOG}" 2>/dev/null || true
JEOF
chmod +x "${LEADV2_JOURNAL_BIN}"
export LEADV2_JOURNAL_LOG="$JOURNAL_LOG"

PASS=0
FAIL=0
ok() { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1" >&2; }

phases_d() { printf '%s/docs/handoff/dispatch-%s/phases.d' "$TMP_ROOT" "$1"; }

# ── Test 1 (acceptance 1): a lane with NO phase record at all ⇒ first
#    dispatch admitted, even though plan/gate1 (and classify) are unproven ──
printf 'test: 1 bootstrap lane with zero phase records is admitted\n'
SIG_BOOT="boot0001"
: > "$JOURNAL_LOG"
OUT1="$(bash "$PHASE_RECORD" assert "$SIG_BOOT" --class Standard --pre-build 2>&1)"; rc1=$?
if [[ $rc1 -eq 0 ]]; then
  ok
else
  fail "bootstrap lane should be admitted (rc=$rc1, out=$OUT1)"
fi
if [[ ! -d "$(phases_d "$SIG_BOOT")" ]] || [[ -z "$(ls -A "$(phases_d "$SIG_BOOT")" 2>/dev/null)" ]]; then
  ok
else
  fail "bootstrap check must run BEFORE any phase file is written (phases.d not empty)"
fi
if grep -q 'phase_precondition_bootstrap' "$JOURNAL_LOG" 2>/dev/null; then
  ok
else
  fail "bootstrap admission should journal phase_precondition_bootstrap"
fi

# ── Test 2 (acceptance 2): the SAME lane, once classify has been recorded
#    (exactly what dispatch-code.sh does right before calling the guard),
#    is no longer bootstrap — missing plan/gate1 refuses exactly as today ──
printf 'test: 2 same lane, later dispatch, missing mandatory phase is refused\n'
bash "$PHASE_RECORD" record "$SIG_BOOT" classify --status done --owner test >/dev/null 2>&1
OUT2="$(bash "$PHASE_RECORD" assert "$SIG_BOOT" --class Standard --pre-build 2>&1)"; rc2=$?
if [[ $rc2 -eq 3 ]]; then
  ok
else
  fail "non-bootstrap lane missing plan/gate1 should refuse (rc=$rc2, out=$OUT2)"
fi
if printf '%s' "$OUT2" | grep -q 'missing=.*plan' && printf '%s' "$OUT2" | grep -q 'missing=.*gate1'; then
  ok
else
  fail "missing= should list both plan and gate1 (got: $OUT2)"
fi

# ── Test 3 (acceptance 3): plan evidence that is ONLY a lead-authored brief
#    is admissible, and the proof is recorded honestly as `attested` ──────
printf 'test: 3 lead-authored brief admits plan, proof=attested\n'
SIG_BRIEF="brief001"
mkdir -p "${TMP_ROOT}/docs/handoff/TASK-BRIEF-01"
printf '# TASK-BRIEF-01\n\nSome founder-authored brief text.\n' \
  > "${TMP_ROOT}/docs/handoff/TASK-BRIEF-01/brief.md"
bash "$PHASE_RECORD" record "$SIG_BRIEF" classify --status done --owner test >/dev/null 2>&1
bash "$PHASE_RECORD" record "$SIG_BRIEF" plan --status done \
  --artifact "docs/handoff/TASK-BRIEF-01/brief.md" --owner test >/dev/null 2>&1
PLAN_FILE="$(phases_d "$SIG_BRIEF")/plan.yaml"
if [[ -f "$PLAN_FILE" ]] && grep -q '^proof: attested$' "$PLAN_FILE"; then
  ok
else
  fail "plan recorded from a brief should carry proof: attested (file: $(cat "$PLAN_FILE" 2>/dev/null))"
fi
OUT3="$(bash "$PHASE_RECORD" assert "$SIG_BRIEF" --class Standard --pre-build 2>&1)"; rc3=$?
# plan is now satisfied; only gate1 remains mandatory and missing.
if [[ $rc3 -eq 3 ]] && printf '%s' "$OUT3" | grep -q 'missing=gate1$'; then
  ok
else
  fail "brief-satisfied plan should drop out of missing=, only gate1 left (rc=$rc3, out=$OUT3)"
fi

# Negative control: an artifact that does NOT match the brief/fix-round
# naming must NOT satisfy plan — the acceptance is restricted, not "any
# non-empty file". Proves the pattern match, not a name we never verified.
printf 'test: 3b non-brief-named artifact does NOT satisfy plan\n'
SIG_FORGE="forge001"
mkdir -p "${TMP_ROOT}/docs/handoff/TASK-BRIEF-01"
printf 'not a recognized plan artifact name\n' > "${TMP_ROOT}/docs/handoff/TASK-BRIEF-01/notes.md"
bash "$PHASE_RECORD" record "$SIG_FORGE" classify --status done --owner test >/dev/null 2>&1
bash "$PHASE_RECORD" record "$SIG_FORGE" plan --status done \
  --artifact "docs/handoff/TASK-BRIEF-01/notes.md" --owner test >/dev/null 2>&1
FORGE_PLAN_FILE="$(phases_d "$SIG_FORGE")/plan.yaml"
if grep -q '^proof: unverified$' "$FORGE_PLAN_FILE" 2>/dev/null; then
  ok
else
  fail "non-brief-named artifact should record proof: unverified (file: $(cat "$FORGE_PLAN_FILE" 2>/dev/null))"
fi
OUT3B="$(bash "$PHASE_RECORD" assert "$SIG_FORGE" --class Standard --pre-build 2>&1)"; rc3b=$?
if [[ $rc3b -eq 3 ]] && printf '%s' "$OUT3B" | grep -q 'missing=.*plan'; then
  ok
else
  fail "non-brief artifact must still leave plan in missing= (rc=$rc3b, out=$OUT3B)"
fi

# ── Test 4 (acceptance 4): running the printed remedy for a refusal clears
#    it — plan via brief, gate1 via an explicit recorded --reason ─────────
printf 'test: 4 the printed remedy actually clears the refusal\n'
SIG_REMEDY="remedy01"
mkdir -p "${TMP_ROOT}/docs/handoff/TASK-REMEDY-01"
printf '# TASK-REMEDY-01 brief\n' > "${TMP_ROOT}/docs/handoff/TASK-REMEDY-01/brief.md"
bash "$PHASE_RECORD" record "$SIG_REMEDY" classify --status done --owner test >/dev/null 2>&1
OUT4A="$(bash "$PHASE_RECORD" assert "$SIG_REMEDY" --class Standard --pre-build 2>&1)"; rc4a=$?
if [[ $rc4a -eq 3 ]]; then
  ok
else
  fail "pre-remedy assert should refuse (rc=$rc4a, out=$OUT4A)"
fi
# Run exactly the remedy leadv2-dispatch-code.sh now prints for each missing phase.
bash "$PHASE_RECORD" record "$SIG_REMEDY" plan --status done \
  --artifact "docs/handoff/TASK-REMEDY-01/brief.md" --owner test >/dev/null 2>&1
bash "$PHASE_RECORD" record "$SIG_REMEDY" gate1 --status done \
  --reason "founder gate-1 decision: approved for fixture test" --owner test >/dev/null 2>&1
OUT4B="$(bash "$PHASE_RECORD" assert "$SIG_REMEDY" --class Standard --pre-build 2>&1)"; rc4b=$?
if [[ $rc4b -eq 0 ]]; then
  ok
else
  fail "assert after running the printed remedies should admit (rc=$rc4b, out=$OUT4B)"
fi
GATE1_FILE="$(phases_d "$SIG_REMEDY")/gate1.yaml"
if grep -q '^proof: attested$' "$GATE1_FILE" 2>/dev/null; then
  ok
else
  fail "gate1 recorded via --reason should carry proof: attested (file: $(cat "$GATE1_FILE" 2>/dev/null))"
fi

# Negative control: gate1 status=done with NEITHER --artifact NOR --reason
# must still be refused at the record layer — the exemption is reason-gated,
# not a blanket drop of the --artifact requirement.
printf 'test: 4b gate1 done with no artifact and no reason is still refused by record\n'
bash "$PHASE_RECORD" record "nogate01" gate1 --status done --owner test >/dev/null 2>&1
rc4c=$?
if [[ $rc4c -eq 4 ]]; then
  ok
else
  fail "gate1 --status done with neither --artifact nor --reason should exit 4 (got $rc4c)"
fi

# ── Test 5 (acceptance 5): a Standard lane that genuinely skipped planning
#    (classify recorded, nothing else — no brief, no context.yaml, no
#    prepass, no gate1 reason anywhere) is still refused ──────────────────
printf 'test: 5 Standard lane that genuinely skipped planning is still refused\n'
SIG_SKIP="skip0001"
bash "$PHASE_RECORD" record "$SIG_SKIP" classify --status done --owner test >/dev/null 2>&1
OUT5="$(bash "$PHASE_RECORD" assert "$SIG_SKIP" --class Standard --pre-build 2>&1)"; rc5=$?
if [[ $rc5 -eq 3 ]]; then
  ok
else
  fail "genuinely-skipped-planning lane should refuse (rc=$rc5, out=$OUT5)"
fi
if printf '%s' "$OUT5" | grep -q 'missing=.*plan' && printf '%s' "$OUT5" | grep -q 'missing=.*gate1'; then
  ok
else
  fail "missing= should list plan and gate1 for the genuinely-skipped lane (got: $OUT5)"
fi

printf '\n[PHASE-PRECONDITION-BOOTSTRAP] pass=%d fail=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
