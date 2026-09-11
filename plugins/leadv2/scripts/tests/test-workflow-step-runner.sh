#!/usr/bin/env bash
# changed-scope triggers, self-registered (scan_suite_triggers convention):
# run-all-triggers: leadv2-workflow-step leadv2-launch-registry
# WORKFLOW-STEP-BOUNDARY-01 (§4 phase 1, row 4afa0ee2525a): the executable
# boundary between an arbiter decision and a real launch. The suite tests the
# BOUNDARY, not routing: the arbiter is a stub executable replaying one
# decision line whose shape is the real line the arbiter CLI printed under
# these same seams on 2026-09-10 (arm=haiku kind=recon model=haiku
# tier=standard effort=low; see docs/handoff/w-workflow-step-runner/report.md).
# The registry (lib/leadv2-launch-registry.py resolve_decision) and the
# workflow-step boundary (leadv2-workflow-step.py run_step) are the code
# under test; the routing yaml is a two-row fixture.
#
# Cases (brief acceptance):
#   main    -- full green pass: receipt outcome=ok, requested==observed arm/model
#   paired  -- ONLY difference: decision line carries model=sonnet (substituted
#              between arbiter and launch) -> refusal NAMING field=model,
#              outcome != ok, launched=false
#   schema  -- executor output fails the schema -> invalid_output, receipt written
#   stale   -- quota evidence 120s old -> refusal naming freshness
#   glm     -- decision names an arm the registry cannot launch -> refusal
#              naming the arm (adapter_scope=external), never a substitute
#   empty   -- explicitly empty launchable_arms -> refusal (never pool-widening)
#   kind    -- unknown work_kind -> refusal before the arbiter's coercion
# Every case must append EXACTLY ONE receipt line: a step without a receipt
# did not happen.
#
# Mutation control: leadv2-mutation-control.sh drops "arm","model" from the
# decision-match-mut tuple inside resolve_decision's body -> the PAIRED case
# goes red. Artifact in docs/handoff/w-workflow-step-runner/mutation-control/.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
STEP_BIN="${SCRIPTS_ROOT}/leadv2-workflow-step.py"
REGISTRY_LIB="${SCRIPTS_ROOT}/lib/leadv2-launch-registry.py"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/wf-step.XXXXXX")"
trap '[[ "${WFSTEP_KEEP_LOGS:-0}" == "1" ]] || rm -rf "$TMP"' EXIT

python3 -m py_compile "$STEP_BIN" "$REGISTRY_LIB" || { fail "py_compile" "boundary/registry do not compile"; exit 1; }
pass "py_compile: boundary + registry"

# ── fixtures ─────────────────────────────────────────────────────────────────
# Two rows only: haiku (claude family -- launchable through the registry) and
# glm (external adapter -- lookup() must refuse it by name, not substitute).
cat > "$TMP/routing.yaml" <<YAML
router_v2:
  capability_matrix:
    - { arm: haiku, provider: claude, model: haiku, tier: standard, cost: 2, kinds: [recon, docs], sizes: [standard], capability: 2, pool_default: true }
    - { arm: glm, provider: glm, model: glm-4.7, tier: standard, cost: 1, kinds: [recon], sizes: [standard], capability: 3, pool_default: true }
YAML
export LEADV2_ROUTE_ARBITER_ROUTING_YAML="$TMP/routing.yaml"
export LEADV2_WORKFLOW_STEP_RECEIPTS_FILE="$TMP/receipts.jsonl"

# stub arbiter: prints one decision line, rc 0 -- the boundary's contract with
# the real arbiter CLI is its line protocol, nothing more
cat > "$TMP/arbiter.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$STUB_DECISION_LINE"
EOF
chmod +x "$TMP/arbiter.sh"

# stub executor: $EXEC_STDOUT to stdout, $EXEC_RESULT_JSON (if non-empty) to
# $LEADV2_STEP_RESULT_JSON, exit $EXEC_RC
cat > "$TMP/exec.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s' "${EXEC_STDOUT:-}"
if [[ -n "${EXEC_RESULT_JSON:-}" && -n "${LEADV2_STEP_RESULT_JSON:-}" ]]; then
  printf '%s' "$EXEC_RESULT_JSON" > "$LEADV2_STEP_RESULT_JSON"
fi
exit "${EXEC_RC:-0}"
EOF
chmod +x "$TMP/exec.sh"

# driver: merges key=json overrides over the base request, runs run_step,
# prints the receipt
cat > "$TMP/driver.py" <<'EOF'
import importlib.util, json, sys, time
spec = importlib.util.spec_from_file_location("wfs", sys.argv[1])
wfs = importlib.util.module_from_spec(spec); spec.loader.exec_module(wfs)
req = {
    "schema_version": 1, "workflow_run_id": "suite-w1", "step_id": "probe/1",
    "round": 1, "attempt": 1, "kind": "recon", "size": "standard",
    "provenance": "heuristic", "required_capabilities": ["read_repo", "json_result"],
    "role": "worker", "task": "boundary suite fixture", "subtype": "probe",
    "quota_evidence": {"sampled_at_epoch": int(time.time()), "source": "suite-fixture"},
    "arbiter_cmd": [sys.argv[2]], "executor": [sys.argv[3]],
    "output_schema": {"type": "object", "required": ["answer"]}, "schema_id": "answer-v1",
    "repo_root": sys.argv[4], "timeout_s": 60,
}
for kv in sys.argv[5:]:
    k, _, v = kv.partition("=")
    req[k] = json.loads(v)
print(json.dumps(wfs.run_step(req), sort_keys=True))
EOF

check() { # <file> <python-expr over r> <label>
  if python3 - "$1" "$2" "$3" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
ok = eval(sys.argv[2], {}, {"r": r})
print(("PASS: %s" % sys.argv[3]) if ok else ("FAIL: %s -> %r" % (sys.argv[3], r)))
sys.exit(0 if ok else 1)
PY
  then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi
}

receipts_count() { wc -l < "${LEADV2_WORKFLOW_STEP_RECEIPTS_FILE}" | tr -d ' '; }

# ── main: full green pass ────────────────────────────────────────────────────
STUB_DECISION_LINE='arm=haiku kind=recon model=haiku tier=standard effort=low reason=cheapest_capable chain=haiku util_glm=20' \
EXEC_STDOUT='{"answer": 42}' \
EXEC_RESULT_JSON='{"arm":"haiku","model":"haiku","usage":{"input_tokens":10,"output_tokens":5}}' \
python3 "$TMP/driver.py" "$STEP_BIN" "$TMP/arbiter.sh" "$TMP/exec.sh" "$TMP" > "$TMP/case-main.json" 2>"$TMP/case-main.err" \
  || fail "main rc" "driver exited non-zero: $(head -c 200 "$TMP/case-main.err")"
check "$TMP/case-main.json" 'r["outcome"] == "ok" and r["status"] == "ok"' "main: outcome ok"
check "$TMP/case-main.json" 'r["requested"]["arm"] == r["observed"]["arm"] == "haiku"' "main: requested arm == observed arm"
check "$TMP/case-main.json" 'r["requested"]["model"] == r["observed"]["model"] == "haiku"' "main: requested model == observed model"
check "$TMP/case-main.json" 'bool(r.get("decision_id")) and r["launched"] is True' "main: decision_id + launched"
check "$TMP/case-main.json" 'r["schema_validation"]["valid"] is True' "main: schema validated"
check "$TMP/case-main.json" 'r["receipt_persisted"] is True and r["usage"] != "unknown"' "main: receipt persisted + usage"
[[ "$(receipts_count)" == "1" ]] && pass "main: one receipt line" || fail "main: receipts lines=$(receipts_count)"

# ── paired: ONLY the decision line's model is substituted ────────────────────
STUB_DECISION_LINE='arm=haiku kind=recon model=sonnet tier=standard effort=low reason=cheapest_capable chain=haiku util_glm=20' \
EXEC_STDOUT='{"answer": 42}' \
EXEC_RESULT_JSON='{"arm":"haiku","model":"haiku","usage":{"input_tokens":10,"output_tokens":5}}' \
python3 "$TMP/driver.py" "$STEP_BIN" "$TMP/arbiter.sh" "$TMP/exec.sh" "$TMP" > "$TMP/case-paired.json" 2>/dev/null
check "$TMP/case-paired.json" 'r["status"] == "refused" and r["outcome"] != "ok"' "paired: refused, outcome not ok"
check "$TMP/case-paired.json" 'r["refusal"]["field"] == "model"' "paired: refusal names field=model"
check "$TMP/case-paired.json" 'r["refusal"]["decision_value"] == "sonnet" and r["refusal"]["registry_value"] == "haiku"' "paired: diverged values named"
check "$TMP/case-paired.json" 'r["launched"] is False' "paired: nothing launched"
[[ "$(receipts_count)" == "2" ]] && pass "paired: one receipt line" || fail "paired: receipts lines=$(receipts_count)"

# ── schema-invalid output ────────────────────────────────────────────────────
STUB_DECISION_LINE='arm=haiku kind=recon model=haiku tier=standard effort=low reason=cheapest_capable chain=haiku util_glm=20' \
EXEC_STDOUT='{"nope": 1}' \
EXEC_RESULT_JSON='{"arm":"haiku","model":"haiku","usage":{"input_tokens":3}}' \
python3 "$TMP/driver.py" "$STEP_BIN" "$TMP/arbiter.sh" "$TMP/exec.sh" "$TMP" > "$TMP/case-schema.json" 2>/dev/null
check "$TMP/case-schema.json" 'r["outcome"] == "invalid_output" and r["launched"] is True' "schema: invalid_output after a real launch"
check "$TMP/case-schema.json" 'r["schema_validation"]["valid"] is False and "answer" in r["schema_validation"]["error"]' "schema: error names the missing property"
[[ "$(receipts_count)" == "3" ]] && pass "schema: receipt still written" || fail "schema: receipts lines=$(receipts_count)"

# ── stale quota evidence (120s > 60s limit) ──────────────────────────────────
STALE_TS=$(( $(date +%s) - 120 ))
STUB_DECISION_LINE='arm=haiku kind=recon model=haiku tier=standard effort=low reason=cheapest_capable chain=haiku util_glm=20' \
EXEC_STDOUT='{"answer": 42}' \
python3 "$TMP/driver.py" "$STEP_BIN" "$TMP/arbiter.sh" "$TMP/exec.sh" "$TMP" \
  "quota_evidence={\"sampled_at_epoch\": ${STALE_TS}, \"source\": \"stale-fixture\"}" > "$TMP/case-stale.json" 2>/dev/null
check "$TMP/case-stale.json" 'r["status"] == "refused" and r["outcome"] != "ok"' "stale: refused"
check "$TMP/case-stale.json" 'r["refusal"]["kind"] == "stale_admission_evidence" and "STALE" in r["refusal"]["message"]' "stale: refusal names freshness"
check "$TMP/case-stale.json" 'r["refusal"]["age_s"] > 60 and r["launched"] is False' "stale: age > limit, nothing launched"
[[ "$(receipts_count)" == "4" ]] && pass "stale: one receipt line" || fail "stale: receipts lines=$(receipts_count)"

# ── arm the registry cannot launch ───────────────────────────────────────────
STUB_DECISION_LINE='arm=glm kind=recon model=glm-4.7 tier=standard effort=low reason=cheapest_capable chain=glm util_glm=20' \
EXEC_STDOUT='{"answer": 42}' \
python3 "$TMP/driver.py" "$STEP_BIN" "$TMP/arbiter.sh" "$TMP/exec.sh" "$TMP" > "$TMP/case-glm.json" 2>/dev/null
check "$TMP/case-glm.json" 'r["status"] == "refused" and r["refusal"]["field"] == "arm" and r["refusal"]["arm"] == "glm"' "glm: refusal names the arm"
check "$TMP/case-glm.json" 'r["refusal"]["registry_reason"] == "adapter_argv_not_registered" and r["refusal"].get("adapter_scope") == "external"' "glm: external adapter scope, no substitute"
check "$TMP/case-glm.json" 'r["launched"] is False and r["outcome"] != "ok"' "glm: nothing launched"
[[ "$(receipts_count)" == "5" ]] && pass "glm: one receipt line" || fail "glm: receipts lines=$(receipts_count)"

# ── explicitly empty launchable set ──────────────────────────────────────────
STUB_DECISION_LINE='arm=haiku kind=recon model=haiku tier=standard effort=low reason=cheapest_capable chain=haiku util_glm=20' \
python3 "$TMP/driver.py" "$STEP_BIN" "$TMP/arbiter.sh" "$TMP/exec.sh" "$TMP" 'launchable_arms=[]' > "$TMP/case-empty.json" 2>/dev/null
check "$TMP/case-empty.json" 'r["refusal"]["kind"] == "empty_launchable_set" and r["launched"] is False' "empty: empty set is a refusal, never pool-widening"
[[ "$(receipts_count)" == "6" ]] && pass "empty: one receipt line" || fail "empty: receipts lines=$(receipts_count)"

# ── unknown kind (refused BEFORE the arbiter's coercion could allow it) ──────
STUB_DECISION_LINE='arm=haiku kind=code model=haiku tier=standard effort=low reason=cheapest_capable chain=haiku util_glm=20' \
python3 "$TMP/driver.py" "$STEP_BIN" "$TMP/arbiter.sh" "$TMP/exec.sh" "$TMP" 'kind="bogus"' > "$TMP/case-kind.json" 2>/dev/null
check "$TMP/case-kind.json" 'r["refusal"]["kind"] == "unknown_kind" and r["launched"] is False' "kind: unknown work_kind refused at the boundary"
[[ "$(receipts_count)" == "7" ]] && pass "kind: one receipt line" || fail "kind: receipts lines=$(receipts_count)"

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
