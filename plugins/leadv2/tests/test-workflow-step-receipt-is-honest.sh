#!/usr/bin/env bash
# run-all-triggers: leadv2-workflow-step leadv2-workflow-receipt.schema.json workflow-step-receipt
# E2E-KILLRATE-01: receipt truth must survive two body-local mutations.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
STEP="${ROOT}/plugins/leadv2/scripts/lib/leadv2-workflow-step.sh"
SCHEMA="${ROOT}/plugins/leadv2/contracts/leadv2-workflow-receipt.schema.json"
PASS=0
FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d /private/tmp/leadv2-workflow-step.XXXXXX)"
trap 'rm -rf "${TMP}"' EXIT

cat > "${TMP}/dispatch-stub.sh" <<'SH'
#!/usr/bin/env bash
# This is the dispatcher seam, not a replacement execution path: it emits the
# dispatcher's own arbiter acceptance record consumed by the facade.
printf 'route_resolved by=arbiter role=worker arm=codex model=%s tier=volume effort=medium task=fixture reason=explicit_requested_capable\n' "${STUB_MODEL:-gpt-5.6-luna}" >&2
exit "${STUB_DISPATCH_RC:-0}"
SH
chmod +x "${TMP}/dispatch-stub.sh"

round_request='{"workflow_run_id":"wf-round","step_id":"step-1","attempt":1,"input":"round-input","admitted_W":1,"admitted_R":2,"arbiter_decision":{"arm":"codex","model":"gpt-5.6-luna","tier":"volume","effort":"medium"},"mission":"fixture mission","lane_writes":"plugins/leadv2/scripts/lib/leadv2-workflow-step.sh","terminal":{"status":"completed","actual_steps":1,"actual_rounds":1}}'
blocked_request='{"workflow_run_id":"wf-blocked","step_id":"step-1","attempt":1,"input":"blocked-input","admitted_W":1,"admitted_R":1,"arbiter_decision":{"arm":"codex","model":"gpt-5.6-luna","tier":"volume","effort":"medium"},"mission":"fixture mission","lane_writes":"plugins/leadv2/scripts/lib/leadv2-workflow-step.sh","terminal":{"status":"blocked_control_plane","actual_steps":0,"actual_rounds":0}}'

run_step() {
  LEADV2_WORKFLOW_STEP_DISPATCH_BIN="${TMP}/dispatch-stub.sh" LEADV2_WORKFLOW_RECEIPTS_LEDGER="${TMP}/receipts.jsonl" bash "$1" run-step "$2" 2>"${TMP}/dispatch.err" || {
    cat "${TMP}/dispatch.err" >&2
    return 1
  }
}

assert_round_not_realized() {
  python3 -c '
import json, sys
r=json.loads(sys.stdin.read())
assert r["terminal_status"] == "completed", r
assert r["actual_rounds"] == 1, r
assert r["admitted_R"] == 2, r
assert r["shape_realized"] is False, r
'
}

assert_blocked_denominator() {
  python3 -c '
import json, sys
r=json.loads(sys.stdin.read())
assert r["terminal_status"] == "blocked_control_plane", r
assert r["shape_realized"] is False, r
assert all(k in r for k in ("admitted_W","admitted_R","actual_steps","actual_rounds")), r
'
}

# assert_blocked_retention <ledger-path> <workflow-run-id>
# The workflow rate reads this append-only ledger, not run-step stdout.  Select
# the terminal receipt by its run ID so an earlier valid receipt cannot mask a
# dropped blocked outcome from this run.
assert_blocked_retention() {
  python3 - "$1" "$2" <<'PY'
import json, sys
ledger, workflow_run_id = sys.argv[1:]
with open(ledger) as f:
    receipts = [json.loads(line) for line in f if line.strip()]
matches = [r for r in receipts if r["workflow_run_id"] == workflow_run_id]
assert matches, (workflow_run_id, receipts)
receipt = matches[-1]
assert receipt["terminal_status"] == "blocked_control_plane", receipt
assert receipt["shape_realized"] is False, receipt
assert all(k in receipt for k in ("admitted_W", "admitted_R", "actual_steps", "actual_rounds")), receipt
PY
}

# Green baseline: observed actual rounds differ from the admitted shape.
round_receipt="$(run_step "${STEP}" "${round_request}")"
if printf '%s' "${round_receipt}" | assert_round_not_realized; then
  pass 'symptom: differing observed rounds is terminal but not realized'
else
  fail 'symptom: differing observed rounds was not represented honestly'
fi
if [[ "$(wc -l < "${TMP}/receipts.jsonl" | tr -d '[:space:]')" == "1" ]]; then
  pass 'retention: terminal receipt is appended to the external workflow ledger'
else
  fail 'retention: terminal receipt was not appended exactly once'
fi

# A pin mismatch is itself a control-plane block, but it must still emit a
# receipt.  The recorded decision is the dispatcher's actual tuple, not a
# rewritten copy of the admitted request.
set +e
mismatch_receipt="$(STUB_MODEL=gpt-5.6-terra run_step "${STEP}" "${round_request}")"
mismatch_rc=$?
set -e
if [[ ${mismatch_rc} -ne 0 ]] && printf '%s' "${mismatch_receipt}" | python3 -c '
import json, sys
r=json.loads(sys.stdin.read())
assert r["terminal_status"] == "blocked_control_plane", r
assert r["decision_matches_admission"] is False, r
assert r["arbiter_decision"]["model"] == "gpt-5.6-terra", r
'; then
  pass 'mismatch: refusal still emits a terminal receipt carrying the actual dispatcher decision'
else
  fail 'mismatch: missing or dishonest terminal receipt'
fi

# Red negative control 1.  Mutation is deliberately inside _lws_receipt's
# Python function body: echo the plan into actual_rounds.  The same assertion
# must fail; a green result here would prove the receipt merely repeats its plan.
cp "${STEP}" "${TMP}/mutated-round.sh"
python3 - "${TMP}/mutated-round.sh" <<'PY'
import sys
p=sys.argv[1]
s=open(p).read()
needle='"actual_rounds": actual_rounds,'
assert s.count(needle) == 1
open(p, 'w').write(s.replace(needle, '"actual_rounds": d["admitted_R"],'))
PY
set +e
mutated_round="$(run_step "${TMP}/mutated-round.sh" "${round_request}" | assert_round_not_realized 2>&1)"
mutated_round_rc=$?
set -e
if [[ ${mutated_round_rc} -ne 0 ]]; then
  pass "red control: receipt-plan echo mutation failed assertion (rc=${mutated_round_rc})"
else
  fail 'red control: receipt-plan echo mutation stayed green'
fi

# Green baseline: a blocked control-plane result still produces a denominator
# receipt with the non-clean terminal status.
blocked_receipt="$(run_step "${STEP}" "${blocked_request}")"
if printf '%s' "${blocked_receipt}" | assert_blocked_denominator; then
  pass 'guard: blocked control-plane stdout carries a terminal denominator receipt'
else
  fail 'guard: blocked control-plane outcome was omitted or misclassified'
fi
if assert_blocked_retention "${TMP}/receipts.jsonl" "wf-blocked"; then
  pass 'guard: blocked control-plane outcome is retained in the terminal denominator ledger'
else
  fail 'guard: blocked control-plane outcome was absent or misclassified in the terminal denominator ledger'
fi

# Red negative control 2.  The lead's 2a mutation is body-local to
# _lws_persist_receipt: it silently drops every non-completed receipt from the
# ledger while leaving stdout intact.  A new run ID proves the assertion cannot
# be satisfied by the genuine blocked receipt above.
cp "${STEP}" "${TMP}/mutated-drop-retention.sh"
python3 - "${TMP}/mutated-drop-retention.sh" <<'PY'
import sys
p=sys.argv[1]
s=open(p).read()
needle='  ledger="$(leadv2_workflow_step_receipts_ledger)"\n'
assert s.count(needle) == 1
drop='  [[ "$1" == *\'"terminal_status":"completed"\'* ]] || return 0\n'
open(p, 'w').write(s.replace(needle, needle + drop))
PY
retention_control_request="${blocked_request/wf-blocked/wf-blocked-retention-control}"
mutated_retention_receipt="$(run_step "${TMP}/mutated-drop-retention.sh" "${retention_control_request}")"
if printf '%s' "${mutated_retention_receipt}" | assert_blocked_denominator \
  && ! assert_blocked_retention "${TMP}/receipts.jsonl" "wf-blocked-retention-control" 2>/dev/null; then
  pass 'red control: retained-ledger drop mutation failed the blocked denominator assertion'
else
  fail 'red control: retained-ledger drop mutation stayed green'
fi

# Red negative control 3.  This body-local mutation silently drops the blocked
# outcome before the JSON receipt is emitted.  The denominator assertion must
# fail on the empty output.
cp "${STEP}" "${TMP}/mutated-drop.sh"
python3 - "${TMP}/mutated-drop.sh" <<'PY'
import sys
p=sys.argv[1]
s=open(p).read()
needle='status = forced_status or t.get("status", fallback_status)'
assert s.count(needle) == 1
open(p, 'w').write(s.replace(needle, needle + '\nif status == "blocked_control_plane":\n    raise SystemExit(0)'))
PY
set +e
mutated_drop="$(run_step "${TMP}/mutated-drop.sh" "${blocked_request}" | assert_blocked_denominator 2>&1)"
mutated_drop_rc=$?
set -e
if [[ ${mutated_drop_rc} -ne 0 ]]; then
  pass "red control: dropped blocked receipt failed assertion (rc=${mutated_drop_rc})"
else
  fail 'red control: dropped blocked receipt stayed green'
fi

# Schema and computability proof: every field in the stated rate is present in
# a receipt and the schema's closed vocabulary admits all terminal categories.
if printf '%s' "${round_receipt}" | python3 -c '
import json, jsonschema, sys
r=json.loads(sys.stdin.read()); s=json.load(open(sys.argv[1]))
jsonschema.Draft7Validator.check_schema(s)
jsonschema.validate(r, s)
assert set(r) == set(s["required"]), (set(r), set(s["required"]))
assert all(k in r for k in ("terminal_status","actual_steps","actual_rounds","admitted_W","admitted_R"))
assert set(s["properties"]["terminal_status"]["enum"]) == {"completed","blocked_control_plane","unknown_completion","budget_exhausted"}
' "${SCHEMA}"; then
  pass 'measurement fields: receipt carries the full shape-realization denominator and numerator inputs'
else
  fail 'measurement fields: receipt/schema do not support the stated measurement'
fi

printf 'test-workflow-step-receipt-is-honest: %d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ ${FAIL} -eq 0 ]]
