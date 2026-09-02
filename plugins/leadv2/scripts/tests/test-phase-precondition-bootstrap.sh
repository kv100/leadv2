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
# PHASE-GATE-IS-INVERTED-01 (2026-09-01): the caller-attested --at-bootstrap is
# gone — the guard derives bootstrap state itself, from the store. Guard-level
# cases below drive leadv2-phase-record.sh directly against a fixture handoff
# tree under a throwaway TMP_ROOT; criterion 5's contract is additionally
# exercised THROUGH leadv2-dispatch-code.sh (tests 7/7b), because testing the
# guard in isolation with a correctly-computed bootstrap answer is exactly how
# faee3fc5 shipped past a green suite.
#
# Never a real lane, never the real dispatch ledger or state root.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE_RECORD="${SCRIPT_DIR}/../leadv2-phase-record.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# PHASE-GATE-IS-INVERTED-01: export BOTH root names, equal — a divergent
# pair now refuses on the write path by design.
export PROJECT_ROOT="$TMP_ROOT"
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

# ── Test 6: is-bootstrap read-only probe still flips after the first record ──
# (The probe no longer feeds any caller-attested flag — PHASE-GATE-IS-INVERTED-01
# removed that seam — but it remains a read-only helper.)
printf 'test: 6 is-bootstrap probe flips after the first record\n'
SIG_PROBE="probe001"
bash "$PHASE_RECORD" is-bootstrap "$SIG_PROBE" 2>/dev/null; rc6a=$?
if [[ $rc6a -eq 0 ]]; then
  ok
else
  fail "is-bootstrap on a lane with no records should exit 0 (got $rc6a)"
fi
bash "$PHASE_RECORD" record "$SIG_PROBE" classify --status done --owner test >/dev/null 2>&1
bash "$PHASE_RECORD" is-bootstrap "$SIG_PROBE" 2>/dev/null; rc6b=$?
if [[ $rc6b -eq 1 ]]; then
  ok
else
  fail "is-bootstrap after classify should exit 1 (got $rc6b)"
fi

# ── Tests 7/7b/7c (PHASE-GATE-IS-INVERTED-01): criterion 5 THROUGH the real
#    dispatch entry. A classify-only fresh lane is what dispatch-code hands the
#    guard on every brand-new Standard dispatch (it records classify first), and
#    it is exactly the shape faee3fc5 shipped in. Driving only cmd_assert with a
#    hand-computed bootstrap answer cannot see the ordering bug; this can.
#    Fixture repo + stub launchers for all four arms + fixture quota reader —
#    never a live provider (harness shape: test-effort-routing.sh). ──────────
DC="${SCRIPT_DIR}/../leadv2-dispatch-code.sh"
ROUTING="${SCRIPT_DIR}/../config/leadv2-routing.yaml"
REPO7="${TMP_ROOT}/repo7"
mkdir -p "$REPO7"
(
  cd "$REPO7" || exit 1
  git init -q -b main
  git config user.email test@example.invalid
  git config user.name test
  printf 'seed\n' > .gitignore
  git add .gitignore
  git commit -qm seed
) >/dev/null 2>&1

mk_stub() { # <name>
  local n="$1"
  local stub="${TMP_ROOT}/stub-$n.sh"
  cat > "$stub" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
  task|bg) printf '%s\n' "$n" >> "${TMP_ROOT}/spawned.txt"; printf 'task-fixture-0001\n'; exit 0 ;;
  status) exit 0 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$stub"
  printf '%s' "$stub"
}
CODEX_STUB="$(mk_stub codex)"
GLM_STUB="$(mk_stub glm)"
SONNET_STUB="$(mk_stub sonnet)"
FREEPOOL_STUB="$(mk_stub freepool)"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "\$ROUTE_TEST_QUOTA"\n' > "${TMP_ROOT}/live.sh"
chmod +x "${TMP_ROOT}/live.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "${TMP_ROOT}/free.sh"
chmod +x "${TMP_ROOT}/free.sh"
QUOTA_JSON="$(python3 -c "import json;print(json.dumps({'glm':{'status':'ok','five_hour':{'pct':1},'weekly':{'pct':1}},'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':1}]},'anthropic':{'status':'ok','accounts':[{'active':True,'five_hour_pct':1,'seven_day_pct':1}]}}))")"

run_dispatch() { # <mission> <out-file> [writes]
  local mission="$1" outf="$2" writes="${3:-src/x.py}"
  # LEADV2_JUDGE_DISABLE=1 pins leadv2-task-judge.sh to its code-only fallback
  # estimator: no live model call ever decides a class in here. Without it the
  # suite passed or failed on whether a real `claude -p haiku` happened to be
  # reachable and what it answered (observed: subsystems_touched=5 via a live
  # judge one run, classifier_error the next).
  (
    cd "$REPO7" || exit 111
    CLAUDE_PROJECT_ROOT="$REPO7" PROJECT_ROOT="$REPO7" LEADV2_PROJECT_ROOT="$REPO7" \
    LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/cache7" LEADV2_STATE_BASE="${TMP_ROOT}/state7" \
    LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_LANE_SHAPE=off LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 \
    LEADV2_DISPATCH_CODEX_BIN="$CODEX_STUB" LEADV2_DISPATCH_GLM_BIN="$GLM_STUB" \
    LEADV2_DISPATCH_SUBSESSION_BIN="$SONNET_STUB" LEADV2_DISPATCH_FREEPOOL_BIN="$FREEPOOL_STUB" \
    LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ROUTING" \
    LEADV2_ROUTE_ARBITER_QUOTA_LIVE="${TMP_ROOT}/live.sh" \
    LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="${TMP_ROOT}/free.sh" \
    LEADV2_ROUTE_ARBITER_STATE_FILE="${TMP_ROOT}/arb7" \
    ROUTE_TEST_QUOTA="$QUOTA_JSON" ROUTE_TEST_FREE_RC=1 \
    LEADV2_JUDGE_DISABLE=1 \
    timeout 120 bash "$DC" "$mission" --kind code --task-class standard \
      --writes "$writes"
  ) >"$outf" 2>&1
  return $?
}

mission_sig8() {
  printf '%s' "$1" | tr -d '\r' | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//' \
    | shasum -a 256 | awk '{print substr($1, 1, 8)}'
}

# Test 7: brand-new Standard lane, no plan/gate1 anywhere ⇒ the REAL dispatcher
# admits the bootstrap lane before recording classify and reaches the stub arm.
printf 'test: 7 fresh Standard dispatch through dispatch-code.sh is admitted\n'
M7='PPB fixture Standard lane writes production code'
S7="$(mission_sig8 "$M7")"
run_dispatch "$M7" "${TMP_ROOT}/d7.out"; rc7=$?
if [[ $rc7 -eq 0 ]]; then
  ok
else
  fail "fresh Standard dispatch should exit 0 (rc=$rc7, out=$(tail -5 "${TMP_ROOT}/d7.out" 2>/dev/null | tr '\n' ' '))"
fi
if [[ -f "${TMP_ROOT}/spawned.txt" ]]; then
  ok
else
  fail "admitted dispatch spawned no worker"
fi
if grep -q 'phase_precondition_bootstrap' "${JOURNAL_LOG}" 2>/dev/null; then
  ok
else
  fail "fresh dispatch should journal phase_precondition_bootstrap"
fi

# Test 7b: the SAME lane after the printed remedies are recorded (brief = plan,
# explicit gate-1 reason = gate1) ⇒ the REAL dispatcher admits and spawns.
# Test 7's dispatch confirmed a ledger slot for this sig; the duplicate-signature
# guard would refuse this re-dispatch before the phase guard ever runs. Clear the
# fixture ledger so 7b measures phase state, not dispatcher concurrency.
printf 'test: 7b same lane after plan+gate1 remedies is admitted and spawns\n'
rm -f "${TMP_ROOT}"/cache7/dispatch-ledger/*.jsonl 2>/dev/null
mkdir -p "${REPO7}/docs/handoff/PPB-${S7}"
printf '# PPB-%s\n\nfixture lead-authored plan\n' "$S7" > "${REPO7}/docs/handoff/PPB-${S7}/brief.md"
( cd "$REPO7" && PROJECT_ROOT="$REPO7" LEADV2_PROJECT_ROOT="$REPO7" bash "$PHASE_RECORD" record "$S7" plan \
    --status done --artifact "docs/handoff/PPB-${S7}/brief.md" --owner lead:test ) >/dev/null 2>&1
( cd "$REPO7" && PROJECT_ROOT="$REPO7" LEADV2_PROJECT_ROOT="$REPO7" bash "$PHASE_RECORD" record "$S7" gate1 \
    --status done --reason 'fixture Gate 1 decision' --owner lead:test ) >/dev/null 2>&1
( cd "$REPO7" && PROJECT_ROOT="$REPO7" LEADV2_PROJECT_ROOT="$REPO7" bash "$PHASE_RECORD" record "$S7" diverge \
    --status n/a --reason 'fixture: no diverge round' --owner lead:test ) >/dev/null 2>&1
run_dispatch "$M7" "${TMP_ROOT}/d7b.out"; rc7b=$?
if [[ $rc7b -eq 0 ]]; then
  ok
else
  fail "dispatch after remedies should exit 0 (rc=$rc7b, out=$(tail -3 "${TMP_ROOT}/d7b.out" 2>/dev/null | tr '\n' ' '))"
fi
if [[ -f "${TMP_ROOT}/spawned.txt" ]]; then
  ok
else
  fail "admitted dispatch spawned no worker"
fi

# Test 7c: a pre-existing phase record that falsely claims verified plan proof
# still refuses. The real assert re-verifies the artifact instead of trusting
# the forged proof field, so this is not a bootstrap lane anymore.
printf 'test: 7c false verified-plan claim through dispatch-code.sh is refused\n'
M7F='PPB fixture false verified plan claim'
S7F="$(mission_sig8 "$M7F")"
mkdir -p "${REPO7}/docs/handoff/PPB-${S7F}"
printf 'not a recognized plan artifact name\n' > "${REPO7}/docs/handoff/PPB-${S7F}/notes.md"
( cd "$REPO7" && PROJECT_ROOT="$REPO7" LEADV2_PROJECT_ROOT="$REPO7" bash "$PHASE_RECORD" record "$S7F" classify \
    --status done --owner test ) >/dev/null 2>&1
( cd "$REPO7" && PROJECT_ROOT="$REPO7" LEADV2_PROJECT_ROOT="$REPO7" bash "$PHASE_RECORD" record "$S7F" plan \
    --status done --artifact "docs/handoff/PPB-${S7F}/notes.md" --owner test ) >/dev/null 2>&1
# Forge the proof field (portable: no sed -i — suite must run on BSD sed).
_PL_YAML="${REPO7}/docs/handoff/dispatch-${S7F}/phases.d/plan.yaml"
grep -v '^proof:' "${_PL_YAML}" > "${_PL_YAML}.forged" && printf 'proof: verified\n' >> "${_PL_YAML}.forged" && mv "${_PL_YAML}.forged" "${_PL_YAML}"
grep -q '^proof: verified$' "${_PL_YAML}" || fail "fixture: proof forgery did not land"
FALSE_BEFORE="$(wc -l < "${TMP_ROOT}/spawned.txt" | tr -d ' ')"
# Distinct writeset: earlier tests' lanes hold src/x.py in the active registry.
run_dispatch "$M7F" "${TMP_ROOT}/d7f.out" src/f7f.py; rc7f=$?
FALSE_AFTER="$(wc -l < "${TMP_ROOT}/spawned.txt" | tr -d ' ')"
if [[ $rc7f -eq 3 ]]; then
  ok
else
  fail "false verified-plan claim should exit 3 (rc=$rc7f, out=$(tail -5 "${TMP_ROOT}/d7f.out" 2>/dev/null | tr '\n' ' '))"
fi
if grep -q 'missing=.*plan' "${TMP_ROOT}/d7f.out" && grep -q 'missing=.*gate1' "${TMP_ROOT}/d7f.out"; then
  ok
else
  fail "false claim refusal should name plan and gate1 ($(grep 'missing=' "${TMP_ROOT}/d7f.out" 2>/dev/null | tail -1))"
fi
if [[ "$FALSE_AFTER" == "$FALSE_BEFORE" ]]; then
  ok
else
  fail "false verified-plan claim spawned a worker (before=$FALSE_BEFORE after=$FALSE_AFTER)"
fi

# Test 7d: a caller STILL passing --at-bootstrap for a lane that has records is
# ignored — the store wins (the flag is parsed for compatibility, decides nothing).
printf 'test: 7d --at-bootstrap claim is ignored, the store wins\n'
SIG_CLAIM="$(mission_sig8 'PPB classify-only claim lane')"
( cd "$REPO7" && PROJECT_ROOT="$REPO7" LEADV2_PROJECT_ROOT="$REPO7" bash "$PHASE_RECORD" record "$SIG_CLAIM" classify \
    --status done --owner test ) >/dev/null 2>&1
OUT7C="$( cd "$REPO7" && PROJECT_ROOT="$REPO7" LEADV2_PROJECT_ROOT="$REPO7" bash "$PHASE_RECORD" assert "$SIG_CLAIM" \
    --class Standard --pre-build --at-bootstrap 2>&1 )"; rc7c=$?
if [[ $rc7c -eq 3 ]] && printf '%s' "$OUT7C" | grep -q 'missing=.*plan'; then
  ok
else
  fail "classify-only lane with --at-bootstrap must refuse (rc=$rc7c, out=$OUT7C)"
fi

# Test 8: brand-new HEAVY lane (the live 2026-09-02 shape: class_escalated to=Heavy
# because=subsystems_touched:5) is admitted at bootstrap like Standard — the fix is
# keyed on zero-records, not class. Hermetic Heavy: the mission names four
# SUBSYSTEM_KEYWORDS (dispatch/journal/router/judge — see leadv2-task-judge.sh's
# fallback estimator), so the pinned code-only estimate carries
# subsystems_touched=4 and leadv2_admission_class escalates the declared
# Standard to Heavy through the real admission map. No live judge decides this.
# Heavy's pre-build mandatory set is classify,diverge,plan,gate1, so the
# bootstrap journal must name diverge alongside plan/gate1 (diverge is
# mandatory only for Heavy).
printf 'test: 8 fresh Heavy dispatch through dispatch-code.sh is admitted\n'
M8='PPB fixture Heavy lane spans dispatch journal router judge subsystems'
S8="$(mission_sig8 "$M8")"
HEAVY_BOOT_LINE="$(grep -c 'phase_precondition_bootstrap' "${JOURNAL_LOG}" 2>/dev/null || true)"
run_dispatch "$M8" "${TMP_ROOT}/d8.out" src/h8.py; rc8=$?
if [[ $rc8 -eq 0 ]]; then
  ok
else
  fail "fresh Heavy dispatch should exit 0 (rc=$rc8, out=$(tail -5 "${TMP_ROOT}/d8.out" 2>/dev/null | tr '\n' ' '))"
fi
if grep "class_escalated" "${JOURNAL_LOG}" 2>/dev/null | grep -q "task=${S8}.*to=Heavy.*because=subsystems_touched"; then
  ok
else
  fail "Heavy dispatch should journal class_escalated to=Heavy because=subsystems_touched ($(grep "task=${S8}" "${JOURNAL_LOG}" 2>/dev/null | grep class_escalated | tail -1))"
fi
BOOT8="$(grep 'phase_precondition_bootstrap' "${JOURNAL_LOG}" 2>/dev/null | grep "task=${S8}" | tail -1)"
if [[ -n "${BOOT8}" ]] && printf '%s' "${BOOT8}" | grep -q 'class=Heavy would_be_missing=classify,diverge,plan,gate1'; then
  ok
else
  fail "Heavy bootstrap journal should read class=Heavy with the full mandatory csv including diverge (got: ${BOOT8:-<none>})"
fi
HEAVY_AFTER_LINE="$(grep -c 'phase_precondition_bootstrap' "${JOURNAL_LOG}" 2>/dev/null || true)"
if [[ "${HEAVY_AFTER_LINE}" -gt "${HEAVY_BOOT_LINE}" ]]; then
  ok
else
  fail "Heavy dispatch did not journal phase_precondition_bootstrap"
fi

# Test 8b: the SAME Heavy lane after the remedies are recorded (n/a diverge,
# brief = plan, explicit gate-1 reason) ⇒ the REAL dispatcher admits and
# spawns. Mirrors 7b; ledger cleared for the same duplicate-signature reason.
printf 'test: 8b Heavy lane after diverge/plan/gate1 remedies is admitted and spawns\n'
rm -f "${TMP_ROOT}"/cache7/dispatch-ledger/*.jsonl 2>/dev/null
mkdir -p "${REPO7}/docs/handoff/PPB-${S8}"
printf '# PPB-%s\n\nfixture lead-authored plan\n' "$S8" > "${REPO7}/docs/handoff/PPB-${S8}/brief.md"
( cd "$REPO7" && PROJECT_ROOT="$REPO7" LEADV2_PROJECT_ROOT="$REPO7" bash "$PHASE_RECORD" record "$S8" diverge \
    --status n/a --reason 'fixture: no diverge round' --owner lead:test ) >/dev/null 2>&1
( cd "$REPO7" && PROJECT_ROOT="$REPO7" LEADV2_PROJECT_ROOT="$REPO7" bash "$PHASE_RECORD" record "$S8" plan \
    --status done --artifact "docs/handoff/PPB-${S8}/brief.md" --owner lead:test ) >/dev/null 2>&1
( cd "$REPO7" && PROJECT_ROOT="$REPO7" LEADV2_PROJECT_ROOT="$REPO7" bash "$PHASE_RECORD" record "$S8" gate1 \
    --status done --reason 'fixture Gate 1 decision' --owner lead:test ) >/dev/null 2>&1
SPAWN8B_BEFORE="$(wc -l < "${TMP_ROOT}/spawned.txt" 2>/dev/null | tr -d ' ')"
run_dispatch "$M8" "${TMP_ROOT}/d8b.out" src/h8.py; rc8b=$?
SPAWN8B_AFTER="$(wc -l < "${TMP_ROOT}/spawned.txt" 2>/dev/null | tr -d ' ')"
if [[ $rc8b -eq 0 ]]; then
  ok
else
  fail "Heavy dispatch after remedies should exit 0 (rc=$rc8b, out=$(tail -5 "${TMP_ROOT}/d8b.out" 2>/dev/null | tr '\n' ' '))"
fi
if [[ "${SPAWN8B_AFTER}" -gt "${SPAWN8B_BEFORE}" ]]; then
  ok
else
  fail "admitted Heavy dispatch spawned no worker (before=${SPAWN8B_BEFORE} after=${SPAWN8B_AFTER})"
fi

# Test 8c: Heavy is NOT a blanket pass — once any record exists the lane is no
# longer bootstrap, and Heavy's mandatory set includes diverge (which Standard's
# does not). Direct guard drive, like tests 2/5.
printf 'test: 8c Heavy lane with classify-only records still refuses, naming diverge\n'
SIG_H8C="heavy08c1"
bash "$PHASE_RECORD" record "$SIG_H8C" classify --status done --owner test >/dev/null 2>&1
OUT8C="$(bash "$PHASE_RECORD" assert "$SIG_H8C" --class Heavy --pre-build 2>&1)"; rc8c=$?
if [[ $rc8c -eq 3 ]]; then
  ok
else
  fail "classify-only Heavy lane should refuse (rc=$rc8c, out=$OUT8C)"
fi
if printf '%s' "$OUT8C" | grep -q 'missing=.*diverge'; then
  ok
else
  fail "Heavy refusal must name diverge in missing= (got: $OUT8C)"
fi

printf '\n[PHASE-PRECONDITION-BOOTSTRAP] pass=%d fail=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
