#!/usr/bin/env bash
# run-all-triggers: leadv2-dispatch-code
# test-depth-gate-uses-the-estimate.sh — A4-WIRE-ESTIMATOR (P6b,
# GATE-DEPTH-MUST-SCALE-WITH-COMPLEXITY-01): the depth gate must actually
# USE lib/leadv2-complexity-estimate.py. Before this lane the gate consulted
# only the task-judge estimate; with the judge at its line-count fallback on
# ~100% of live traffic, every dispatch resolved plan_first and the branch
# (brief_direct / review_rounds=1) had never once fired.
#
# Coverage, all against the REAL dispatcher loaded as a library (definitions
# above the `# ── dispatch ` CLI footer, symlink-populated scratch dir so
# sibling libs resolve to the real files — single-source rule preserved):
#   §1 unit       — _gate_depth_apply fixtures: estimate fills the degraded
#                   slot, judge is never clobbered, flag only raises, a dead
#                   estimator keeps the deeper floor.
#   §2 wiring     — the REAL _admission_classify journals a real
#                   complexity_gate_applied line per fixture, through the
#                   real emit path (stubbed task-judge binary only).
#   §3 handoff    — GATE_DEPTH_REVIEW_ROUNDS reaches spawn_product_close's
#                   LEADV2_DISPATCH_REVIEW_ROUNDS export for the same task
#                   id (the value the close gate resolves its retry ceiling
#                   from).
#   §4 parity     — the three re-arbitration descriptors (bench fallback,
#                   exit76 continuation, arm advance) carry the SAME
#                   complexity/duration_class/complexity_source as the
#                   initial descriptor, and the REAL route_arbiter derives
#                   the same conf/req_eff VALUES on every leg (P6b addendum,
#                   lane 1401655b: the arm actually chosen was selected
#                   against complexity=unknown conf=0.0 req_eff=3.0 seconds
#                   after complexity=complex conf=0.9 req_eff=4.0 was known).
#
# Fixture-only: stubbed task-judge, stubbed quota-live/freepool for the
# arbiter, stubbed close gate. Never a live provider, never a real spawn.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DISPATCH="${SCRIPTS_DIR}/leadv2-dispatch-code.sh"
ARBITER_ROUTING="${SCRIPTS_DIR}/../config/leadv2-routing.yaml"

PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-depth-gate.XXXXXX")"
cleanup(){ rm -rf "${TMP}"; }
trap cleanup EXIT

bash -n "$DISPATCH" || { echo "ERROR: dispatch-code.sh syntax"; exit 1; }

# ── scratch dir: symlink every real sibling, materialise only the awked ──────
# dispatcher body as dispatch-lib.sh (definitions only, no CLI footer).
LIB_DIR="${TMP}/scripts"
mkdir -p "${LIB_DIR}"
for _entry in "${SCRIPTS_DIR}"/*; do
  _base="$(basename "${_entry}")"
  [[ "${_base}" == "leadv2-dispatch-code.sh" ]] && continue
  ln -s "${_entry}" "${LIB_DIR}/${_base}"
done
awk '/^# ── dispatch / { exit } { print }' "$DISPATCH" > "${LIB_DIR}/dispatch-lib.sh"
LIB_SH="${LIB_DIR}/dispatch-lib.sh"

# ── fixtures ────────────────────────────────────────────────────────────────
# The live condition under repair: task-judge degraded to its line-count
# fallback (estimate_source=fallback -> gate provenance "heuristic").
JUDGE_FALLBACK_STANDARD='{"estimate_v":1,"complexity":"standard","subsystems_touched":2,"needs_live_verification":false,"risk_class":"none","duration_class":"medium","work_kind":"build","estimate_id":"a4-fixture","estimate_source":"fallback"}'
JUDGE_REAL_COMPLEX='{"estimate_v":1,"complexity":"complex","subsystems_touched":4,"needs_live_verification":false,"risk_class":"none","duration_class":"long","work_kind":"build","estimate_id":"a4-fixture","estimate_source":"judge"}'
JUDGE_GARBAGE='not-json{{'
MISSION_TRIVIAL='Fix the typo in the README heading.'
WRITES_TRIVIAL='README.md'
MISSION_HEAVY='Migration of the billing subsystem across services, reworking auth, invoicing, storage and the public API contract.'
WRITES_HEAVY='plugins/billing/invoice.py,docs/billing/migration.md,scripts/billing/migrate.sh,tests/billing/test_invoice.py'

# ── §1 unit: the real _gate_depth_apply ────────────────────────────────────
# run_gate <json> <cls> <flagged> <adm_src> <mission> <writes> [estimator-bin]
run_gate() {
  LEADV2_COMPLEXITY_ESTIMATOR_BIN="${7:-}" \
  RG_JSON="$1" RG_CLS="$2" RG_FLAGGED="$3" RG_ADM="$4" RG_MISSION="$5" RG_WRITES="$6" \
  LIB_SH="$LIB_SH" \
  bash -c '
    set -uo pipefail
    source "${LIB_SH}"
    emit() { :; }
    _gate_depth_apply "${RG_JSON}" "${RG_CLS}" "${RG_FLAGGED}" "${RG_ADM}" "${RG_MISSION}" "${RG_WRITES}"
    printf "%s\t%s\t%s\t%s\n" "${GATE_DEPTH_COMPLEXITY}" "${GATE_DEPTH_SOURCE}" "${GATE_DEPTH_ROUTE}" "${GATE_DEPTH_REVIEW_ROUNDS}"
  ' 2>/dev/null
}
gate_field(){ printf '%s\n' "$1" | awk -F'\t' -v i="$2" '{print $i}'; }

out="$(run_gate "$JUDGE_FALLBACK_STANDARD" Light 0 judge "$MISSION_TRIVIAL" "$WRITES_TRIVIAL")"
if [[ "$(gate_field "$out" 1)" == "trivial" && "$(gate_field "$out" 2)" == "estimate" \
      && "$(gate_field "$out" 3)" == "brief_direct" && "$(gate_field "$out" 4)" == "1" ]]; then
  pass "S1a trivial fixture (judge fallback): estimate -> brief_direct/1 [${out//$'\t'/ }]"
else
  fail "S1a trivial fixture: got [${out//$'\t'/ }], want trivial/estimate/brief_direct/1"
fi

out="$(run_gate "$JUDGE_FALLBACK_STANDARD" Standard 0 fallback "$MISSION_HEAVY" "$WRITES_HEAVY")"
if [[ "$(gate_field "$out" 1)" == "complex" && "$(gate_field "$out" 2)" == "estimate" \
      && "$(gate_field "$out" 3)" == "plan_first" && "$(gate_field "$out" 4)" == "3" ]]; then
  pass "S1b heavy fixture (judge fallback): estimate -> plan_first/3 [${out//$'\t'/ }]"
else
  fail "S1b heavy fixture: got [${out//$'\t'/ }], want complex/estimate/plan_first/3"
fi

out="$(run_gate "$JUDGE_GARBAGE" Light 0 judge "" "")"
if [[ "$(gate_field "$out" 1)" == "standard" && "$(gate_field "$out" 3)" == "plan_first" \
      && "$(gate_field "$out" 4)" == "2" ]]; then
  pass "S1c no-signal fixture: deeper floor standard/plan_first/2 [${out//$'\t'/ }]"
else
  fail "S1c no-signal fixture: got [${out//$'\t'/ }], want standard/*/plan_first/2 — a missing estimate must never buy a shallower review"
fi

out="$(run_gate "$JUDGE_REAL_COMPLEX" Standard 0 judge "$MISSION_TRIVIAL" "$WRITES_TRIVIAL")"
if [[ "$(gate_field "$out" 1)" == "complex" && "$(gate_field "$out" 2)" == "judge" \
      && "$(gate_field "$out" 3)" == "plan_first" && "$(gate_field "$out" 4)" == "3" ]]; then
  pass "S1d judge estimate is never clobbered by the estimator [${out//$'\t'/ }]"
else
  fail "S1d judge precedence: got [${out//$'\t'/ }], want complex/judge/plan_first/3"
fi

out="$(run_gate "$JUDGE_FALLBACK_STANDARD" Standard 1 flag "$MISSION_TRIVIAL" "$WRITES_TRIVIAL")"
if [[ "$(gate_field "$out" 1)" == "standard" && "$(gate_field "$out" 2)" == "flag" \
      && "$(gate_field "$out" 3)" == "plan_first" && "$(gate_field "$out" 4)" == "2" ]]; then
  pass "S1e explicit declared class still wins (raise-only), source=flag [${out//$'\t'/ }]"
else
  fail "S1e flag floor: got [${out//$'\t'/ }], want standard/flag/plan_first/2"
fi

out="$(run_gate "$JUDGE_FALLBACK_STANDARD" Light 1 flag "$MISSION_HEAVY" "$WRITES_HEAVY")"
if [[ "$(gate_field "$out" 1)" == "complex" && "$(gate_field "$out" 2)" == "estimate" \
      && "$(gate_field "$out" 3)" == "plan_first" && "$(gate_field "$out" 4)" == "3" ]]; then
  pass "S1f flag never lowers: estimate complex survives a flagged Light [${out//$'\t'/ }]"
else
  fail "S1f flag never lowers: got [${out//$'\t'/ }], want complex/estimate/plan_first/3"
fi

out="$(run_gate "$JUDGE_FALLBACK_STANDARD" Light 0 judge "$MISSION_TRIVIAL" "$WRITES_TRIVIAL" /nonexistent-estimator.py)"
if [[ "$(gate_field "$out" 1)" == "standard" && "$(gate_field "$out" 3)" == "plan_first" \
      && "$(gate_field "$out" 4)" == "2" ]]; then
  pass "S1g dead estimator binary: deeper floor standard/plan_first/2 [${out//$'\t'/ }]"
else
  fail "S1g dead estimator: got [${out//$'\t'/ }], want standard/*/plan_first/2"
fi

# ── §2+§3 wiring: the REAL _admission_classify journals the line, and the ───
# rounds value reaches spawn_product_close for the same task id.
JUDGE_STUB="${TMP}/task-judge-stub.sh"
printf '#!/usr/bin/env bash\ncat <<JSON\n%s\nJSON\n' "$JUDGE_FALLBACK_STANDARD" > "$JUDGE_STUB"
chmod +x "$JUDGE_STUB"
CLOSE_CAPTURE="${TMP}/close-capture.txt"
CLOSE_STUB="${TMP}/close-stub.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "${LEADV2_DISPATCH_REVIEW_ROUNDS:-__ABSENT__}" > "%s"\n' "$CLOSE_CAPTURE" > "$CLOSE_STUB"
chmod +x "$CLOSE_STUB"
PHASE_STUB="${TMP}/phase-stub.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$PHASE_STUB"
chmod +x "$PHASE_STUB"
JOURNAL_BIN_STUB="${TMP}/journal-bin.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$JOURNAL_BIN_STUB"
chmod +x "$JOURNAL_BIN_STUB"

REPO="${TMP}/repo"
mkdir -p "${REPO}"
git -C "${REPO}" init -q -b main
git -C "${REPO}" config user.email fixture@example.invalid
git -C "${REPO}" config user.name fixture
printf 'seed\n' > "${REPO}/seed.txt"
git -C "${REPO}" add seed.txt
git -C "${REPO}" commit -qm seed
mkdir -p "${TMP}/cache" "${TMP}/work" "${REPO}/docs/leadv2/tasks"

# run_wiring <sig8> <mission> <writes> — journals into $TMP/journal-<sig8>.txt
run_wiring() {
  local sig8="$1" mission="$2" writes="$3"
  rm -f "${TMP}/journal-${sig8}.txt" "${CLOSE_CAPTURE}"
  W_SIG8="$sig8" W_MISSION="$mission" W_WRITES="$writes" \
  W_JOURNAL="${TMP}/journal-${sig8}.txt" W_REPO="${REPO}" W_TMP="${TMP}" \
  LEADV2_TASK_JUDGE_BIN="$JUDGE_STUB" \
  LEADV2_JOURNAL_BIN="$JOURNAL_BIN_STUB" \
  LEADV2_DISPATCH_PRODUCT_CLOSE_BIN="$CLOSE_STUB" \
  LEADV2_PHASE_RECORD_BIN="$PHASE_STUB" \
  LIB_SH="$LIB_SH" \
  bash -c '
    set -uo pipefail
    # cd into the fixture repo BEFORE sourcing: FOREIGN-PROJECT-ROOT-GUARD-01
    # roots the control plane at the cwd repo when env and cwd disagree, which
    # would write admission receipts into the REAL checkout instead of the
    # fixture (and make the second suite run a same-digest re-entry with no
    # journal line at all). cwd == env root keeps the fixture authoritative.
    cd "${W_REPO}" || exit 3
    export PROJECT_ROOT="${W_REPO}"
    source "${LIB_SH}"
    emit() { printf "%s\n" "$*" >> "${W_JOURNAL}"; }   # hermetic capture, real call sites
    mission="${W_MISSION}"
    lane_writes="${W_WRITES}"
    founder_task_id=""
    sig="fixture-digest-${W_SIG8}-0000000000000000000000000000000000000000"
    _admission_classify "${mission}" "${sig}" "${W_SIG8}" "" 0
    # §3: same process, same task id — the rounds the close gate receives.
    E2E_GATE=1 REVIEW_GATE=1
    CACHE_BASE="${W_TMP}/cache" WORK_ROOT="${W_TMP}/work" LANE_START_SHA=""
    CODEX_BIN=/bin/true ARCHITECT_BIN=/bin/true DISPATCH_LANE_NAME="a4-${W_SIG8}"
    spawn_product_close "${W_SIG8}" sonnet fixture-handle codex,sonnet "${W_WRITES}" "" "${W_MISSION}"
  ' >>"${TMP}/wiring-${sig8}.out" 2>&1
}

run_wiring A4WIRE01 "$MISSION_TRIVIAL" "$WRITES_TRIVIAL"
if grep -q "complexity_gate_applied task=A4WIRE01 complexity=trivial complexity_source=estimate pipeline_route=brief_direct forced_plan=0 review_rounds=1$" "${TMP}/journal-A4WIRE01.txt" 2>/dev/null; then
  pass "S2a REAL admission journals estimate/brief_direct/1: $(grep 'complexity_gate_applied task=A4WIRE01' "${TMP}/journal-A4WIRE01.txt")"
else
  fail "S2a trivial journal line missing/wrong: $(grep 'complexity_gate_applied' "${TMP}/journal-A4WIRE01.txt" 2>/dev/null || printf '(no journal)')"
fi
sleep 1
if [[ "$(cat "${CLOSE_CAPTURE}" 2>/dev/null)" == "1" ]]; then
  pass "S3a close gate receives LEADV2_DISPATCH_REVIEW_ROUNDS=1 for A4WIRE01"
else
  fail "S3a close-gate rounds for A4WIRE01: got '$(cat "${CLOSE_CAPTURE}" 2>/dev/null)', want 1"
fi

run_wiring A4WIRE02 "$MISSION_HEAVY" "$WRITES_HEAVY"
if grep -q "complexity_gate_applied task=A4WIRE02 complexity=complex complexity_source=estimate pipeline_route=plan_first forced_plan=0 review_rounds=3$" "${TMP}/journal-A4WIRE02.txt" 2>/dev/null; then
  pass "S2b REAL admission journals estimate/plan_first/3: $(grep 'complexity_gate_applied task=A4WIRE02' "${TMP}/journal-A4WIRE02.txt")"
else
  fail "S2b heavy journal line missing/wrong: $(grep 'complexity_gate_applied' "${TMP}/journal-A4WIRE02.txt" 2>/dev/null || printf '(no journal)')"
fi
sleep 1
if [[ "$(cat "${CLOSE_CAPTURE}" 2>/dev/null)" == "3" ]]; then
  pass "S3b close gate receives LEADV2_DISPATCH_REVIEW_ROUNDS=3 for A4WIRE02"
else
  fail "S3b close-gate rounds for A4WIRE02: got '$(cat "${CLOSE_CAPTURE}" 2>/dev/null)', want 3"
fi

# ── §4 parity: every re-arbitration leg inherits the complexity triple ──────
# Extract each descriptor constructor VERBATIM from the real dispatcher and
# evaluate it with the inputs the live path holds (DC_* set once, shared by
# all legs), then resolve each through the REAL route_arbiter. Values, not
# presence: every leg must print the SAME complexity/conf/req_eff the initial
# descriptor produced.
cat > "${TMP}/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
cat > "${TMP}/free.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${TMP}/live.sh" "${TMP}/free.sh"
QUOTA_HEALTHY="$(python3 - <<'PY'
import json
q = {'glm':{'status':'ok','five_hour':{'pct':10},'weekly':{'pct':10}},
     'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':10}]},
     'anthropic':{'status':'ok','accounts':[{'active':True,'five_hour_pct':10,'seven_day_pct':10}]}}
print(json.dumps(q))
PY
)"

extract_ctor() { # <anchor-substring> -> constructor text on stdout (empty if absent)
  local anchor="$1"
  awk -v anch="$anchor" '
    index($0, anch) > 0 { grab = 1 }
    grab { print; if ($0 ~ /"\)$/) { exit } }
  ' "$DISPATCH" | head -4
}

parity_leg() { # <leg-label> <anchor-regex> <desc-var> -> PASS/FAIL via globals
  local leg="$1" anchor="$2" var="$3" ctor desc out
  ctor="$(extract_ctor "$anchor")"
  if [[ -z "${ctor}" ]]; then
    fail "S4 ${leg}: constructor not found in dispatcher (drifted?) — update ${0##*/}"
    return
  fi
  out="$(PL_CTOR="$ctor" PL_VAR="$var" ROUTE_TEST_QUOTA="$QUOTA_HEALTHY" \
    LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ARBITER_ROUTING" \
    LEADV2_ROUTE_ARBITER_QUOTA_LIVE="${TMP}/live.sh" \
    LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="${TMP}/free.sh" \
    LEADV2_ROUTE_ARBITER_STATE_FILE="${TMP}/arb-state-${leg}" \
    bash -c '
      set -uo pipefail
      source "'"${LIB_SH}"'"
      emit() { :; }
      _arm_launchable_arms() { printf "codex,sonnet\n"; }
      kind=code task_class=Standard
      _arb_protected=0 _arb_safety=0 _arb_ui=0 _arb_allowed_csv="codex,sonnet"
      _arb_launchable_csv="codex,sonnet" arm_pool_cli="" _arb_pool_flag=0
      _test_only=0 requested_arm="" sig8=A4PARITY
      _bf_allowed="codex,sonnet" _e76_allowed="codex,sonnet"
      _adv_remaining="codex,sonnet" _adv_pin="" _adv_class=Standard
      DC_COMPLEXITY=complex DC_DURATION_CLASS=long DC_COMPLEXITY_SOURCE=judge
      eval "${PL_CTOR}"
      route_arbiter worker "${!PL_VAR}"
    ' 2>/dev/null)"
  if [[ "${out}" == *"complexity=complex"* && "${out}" == *"complexity_source=judge"* \
        && "${out}" == *"conf=0.9"* && "${out}" == *"req_eff=4.0"* ]]; then
    pass "S4 ${leg} leg carries complexity=complex conf=0.9 req_eff=4.0 (matches initial resolution)"
  else
    fail "S4 ${leg} leg lost the signal: $(printf '%s' "$out" | sed -n 's/.*\(complexity=[^ ]*\).*\(complexity_source=[^ ]*\).*\(conf=[^ ]*\).*\(req_eff=[^ ]*\).*/\1 \2 \3 \4/p')"
  fi
}

parity_leg initial '_arb_desc="$(python3' _arb_desc
parity_leg bench-fallback '_bf_desc="$(python3' _bf_desc
parity_leg exit76 '_e76_desc="$(python3' _e76_desc
parity_leg arm-advance '_adv_desc="$(python3' _adv_desc

# ── verdict ─────────────────────────────────────────────────────────────────
printf 'depth-gate-uses-the-estimate: pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
