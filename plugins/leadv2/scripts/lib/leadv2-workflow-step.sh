#!/usr/bin/env bash
# leadv2-workflow-step.sh -- fixed-shape workflow facade over dispatch.
#
# This file deliberately does not reserve, spawn, select a provider, or invoke
# an adapter.  Those operations remain owned by leadv2-dispatch-code.sh.  A
# workflow supplies an already-admitted arbiter decision; runStep pins that
# decision into the dispatcher, reads the dispatcher's decision record back,
# and returns one terminal receipt.

leadv2_workflow_step_script_dir() {
  local source="${BASH_SOURCE[0]}" link dir
  while [[ -h "${source}" ]]; do
    dir="$(cd -P "$(dirname "${source}")" && pwd)"
    link="$(readlink "${source}")"
    [[ "${link}" == /* ]] || link="${dir}/${link}"
    source="${link}"
  done
  cd -P "$(dirname "${source}")" && pwd
}

leadv2_workflow_step_dispatch_bin() {
  printf '%s\n' "${LEADV2_WORKFLOW_STEP_DISPATCH_BIN:-$(leadv2_workflow_step_script_dir)/../leadv2-dispatch-code.sh}"
}

leadv2_workflow_step_receipts_ledger() {
  printf '%s\n' "${LEADV2_WORKFLOW_RECEIPTS_LEDGER:-${HOME}/.claude/state/leadv2/workflow-receipts.jsonl}"
}

# _lws_json_get <json> <dot.path> -> scalar or compact JSON for objects.
_lws_json_get() {
  python3 -c '
import json, sys
obj = json.loads(sys.argv[1]); value = obj
for part in sys.argv[2].split("."):
    if part:
        if not isinstance(value, dict) or part not in value:
            sys.exit(2)
        value = value[part]
if value is None:
    print("")
elif isinstance(value, (dict, list)):
    print(json.dumps(value, sort_keys=True, separators=(",", ":")))
elif isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
' "$1" "$2"
}

# leadv2_workflow_step_validate_request <request-json>
# Validates the fixed workflow shape.  Shape choice is intentionally absent.
leadv2_workflow_step_validate_request() {
  python3 -c '
import json, re, sys
try:
    d = json.loads(sys.argv[1])
except Exception as e:
    print("workflow-step: invalid request JSON: %s" % e, file=sys.stderr); sys.exit(2)
required = ("workflow_run_id", "step_id", "attempt", "input", "admitted_W", "admitted_R", "arbiter_decision", "mission", "lane_writes")
missing = [k for k in required if k not in d]
if missing:
    print("workflow-step: missing request fields: %s" % ",".join(missing), file=sys.stderr); sys.exit(2)
for k in ("workflow_run_id", "step_id"):
    if not isinstance(d[k], str) or not re.fullmatch(r"[A-Za-z0-9._-]+", d[k]):
        print("workflow-step: %s must be a non-empty opaque id" % k, file=sys.stderr); sys.exit(2)
for k in ("attempt", "admitted_W", "admitted_R"):
    if not isinstance(d[k], int) or isinstance(d[k], bool) or d[k] < 1:
        print("workflow-step: %s must be an integer >= 1" % k, file=sys.stderr); sys.exit(2)
if not isinstance(d["input"], str) or not d["input"]:
    print("workflow-step: input must be non-empty text", file=sys.stderr); sys.exit(2)
if not isinstance(d["mission"], str) or not d["mission"].strip():
    print("workflow-step: mission must be non-empty text", file=sys.stderr); sys.exit(2)
if not isinstance(d["lane_writes"], str) or not d["lane_writes"].strip():
    print("workflow-step: lane_writes must be non-empty", file=sys.stderr); sys.exit(2)
a = d["arbiter_decision"]
if not isinstance(a, dict):
    print("workflow-step: arbiter_decision must be an object", file=sys.stderr); sys.exit(2)
for k in ("arm", "model", "tier", "effort"):
    if not isinstance(a.get(k), str) or not re.fullmatch(r"[A-Za-z0-9._:-]+", a[k]):
        print("workflow-step: arbiter_decision.%s must be a non-empty token" % k, file=sys.stderr); sys.exit(2)
if "input_digest" in d and d["input_digest"] is not None and not re.fullmatch(r"[a-f0-9]{64}", str(d["input_digest"])):
    print("workflow-step: input_digest must be lowercase sha256", file=sys.stderr); sys.exit(2)
if "terminal" in d:
    t = d["terminal"]
    if not isinstance(t, dict) or t.get("status") not in ("completed", "blocked_control_plane", "unknown_completion", "budget_exhausted"):
        print("workflow-step: terminal.status is invalid", file=sys.stderr); sys.exit(2)
    for k in ("actual_steps", "actual_rounds"):
        if k in t and t[k] is not None and (not isinstance(t[k], int) or isinstance(t[k], bool) or t[k] < 0):
            print("workflow-step: terminal.%s must be null or integer >= 0" % k, file=sys.stderr); sys.exit(2)
' "$1"
}

_lws_terminal_from_dispatch_rc() {
  case "$1" in
    6) printf 'budget_exhausted\n' ;;
    3|5) printf 'blocked_control_plane\n' ;;
    *) printf 'unknown_completion\n' ;;
  esac
}

# _lws_persist_receipt <single-json-line>
# O_APPEND keeps each sub-PIPE_BUF receipt append indivisible.  This is an
# external, append-only measurement ledger, never repository runtime state.
_lws_persist_receipt() {
  local ledger
  ledger="$(leadv2_workflow_step_receipts_ledger)"
  python3 -c '
import os, sys
line, path = sys.argv[1:]
os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
try:
    os.write(fd, (line + "\n").encode())
finally:
    os.close(fd)
' "$1" "${ledger}"
}

# _lws_receipt <request> <dispatch-rc> <dispatch-output> <observed-status>
#              <actual-decision-json-or-empty> <forced-status-or-empty>
# Emits a closed-vocabulary terminal receipt.  A spawn success is never
# promoted to completed: async completion is unknown until a caller observes it.
_lws_receipt() {
  python3 -c '
import hashlib, json, sys
request, dispatch_rc, dispatch_output, fallback_status, actual_json, forced_status = sys.argv[1:]
d = json.loads(request); a = d["arbiter_decision"]
t = d.get("terminal") or {}
status = forced_status or t.get("status", fallback_status)
actual_steps = t.get("actual_steps")
actual_rounds = t.get("actual_rounds")
if status == "completed":
    # A claimed completion still requires observed counts.  Null cannot be a
    # clean realization and is represented honestly as unknown completion.
    if actual_steps is None or actual_rounds is None:
        status = "unknown_completion"
if actual_steps is None:
    actual_steps = 0
if actual_rounds is None:
    actual_rounds = 0
digest = hashlib.sha256(d["input"].encode()).hexdigest()
provided = d.get("input_digest")
if provided and provided != digest:
    raise SystemExit("workflow-step: supplied input_digest does not match input")
receipt = {
  "receipt_version": 1,
  "workflow_run_id": d["workflow_run_id"], "step_id": d["step_id"], "attempt": d["attempt"],
  "input_digest": digest, "admitted_W": d["admitted_W"], "admitted_R": d["admitted_R"],
  "admitted_arbiter_decision": {k: a[k] for k in ("arm", "model", "tier", "effort")},
  "arbiter_decision": json.loads(actual_json) if actual_json else None,
  "decision_matches_admission": bool(actual_json) and json.loads(actual_json) == {k: a[k] for k in ("arm", "model", "tier", "effort")},
  "terminal_status": status, "actual_steps": actual_steps, "actual_rounds": actual_rounds,
  "shape_realized": status == "completed" and actual_steps == d["admitted_W"] and actual_rounds == d["admitted_R"],
  "dispatch_exit_code": int(dispatch_rc),
  "dispatch_output_digest": hashlib.sha256(dispatch_output.encode()).hexdigest(),
}
print(json.dumps(receipt, sort_keys=True, separators=(",", ":")))
' "$1" "$2" "$3" "$4" "$5" "$6"
}

# leadv2_workflow_run_step <request-json>
# stdout is exactly one JSON terminal receipt.  stderr retains dispatch output.
leadv2_workflow_run_step() {
  [[ $# -eq 1 ]] || { printf 'workflow-step: runStep expects exactly one request JSON\n' >&2; return 2; }
  local request="$1" dispatch_bin mission writes run_id step_id attempt arm expected_model expected_tier expected_effort dispatch_out rc observed actual_line actual_arm actual_model actual_tier actual_effort receipt
  leadv2_workflow_step_validate_request "${request}" || return $?
  dispatch_bin="$(leadv2_workflow_step_dispatch_bin)"
  [[ -f "${dispatch_bin}" || -x "${dispatch_bin}" ]] || { printf 'workflow-step: dispatcher unavailable: %s\n' "${dispatch_bin}" >&2; return 2; }
  mission="$(_lws_json_get "${request}" mission)"
  writes="$(_lws_json_get "${request}" lane_writes)"
  run_id="$(_lws_json_get "${request}" workflow_run_id)"
  step_id="$(_lws_json_get "${request}" step_id)"
  attempt="$(_lws_json_get "${request}" attempt)"
  arm="$(_lws_json_get "${request}" arbiter_decision.arm)"
  expected_model="$(_lws_json_get "${request}" arbiter_decision.model)"
  expected_tier="$(_lws_json_get "${request}" arbiter_decision.tier)"
  expected_effort="$(_lws_json_get "${request}" arbiter_decision.effort)"

  # The dispatcher remains the sole execution pipeline.  --requested-arm is a
  # hard pin: a dispatcher refusal cannot silently substitute another arm.
  dispatch_out="$(bash "${dispatch_bin}" --requested-arm "${arm}" --task-id "workflow-${run_id}-${step_id}-${attempt}" --writes "${writes}" "${mission}" 2>&1)"; rc=$?
  [[ -n "${dispatch_out}" ]] && printf '%s\n' "${dispatch_out}" >&2

  # Only the dispatcher's own emitted arbiter record proves what it accepted.
  actual_line="$(printf '%s\n' "${dispatch_out}" | grep 'route_resolved by=arbiter role=worker ' | tail -1 || true)"
  actual_arm="$(printf '%s\n' "${actual_line}" | sed -n 's/.* arm=\([^ ]*\).*/\1/p')"
  actual_model="$(printf '%s\n' "${actual_line}" | sed -n 's/.* model=\([^ ]*\).*/\1/p')"
  actual_tier="$(printf '%s\n' "${actual_line}" | sed -n 's/.* tier=\([^ ]*\).*/\1/p')"
  actual_effort="$(printf '%s\n' "${actual_line}" | sed -n 's/.* effort=\([^ ]*\).*/\1/p')"
  local actual_json=""
  if [[ -n "${actual_line}" ]]; then
    actual_json="$(python3 -c 'import json,sys; print(json.dumps(dict(zip(("arm","model","tier","effort"),sys.argv[1:])),sort_keys=True,separators=(",",":")))' "${actual_arm}" "${actual_model}" "${actual_tier}" "${actual_effort}")"
  fi
  if [[ ${rc} -eq 0 ]] && { [[ -z "${actual_line}" ]] || [[ "${actual_arm}" != "${arm}" ]] || [[ "${actual_model}" != "${expected_model}" ]] || [[ "${actual_tier}" != "${expected_tier}" ]] || [[ "${actual_effort}" != "${expected_effort}" ]]; }; then
    printf 'workflow-step: dispatcher decision mismatch or absent record expected=%s/%s/%s/%s actual=%s/%s/%s/%s\n' \
      "${arm}" "${expected_model}" "${expected_tier}" "${expected_effort}" "${actual_arm:-missing}" "${actual_model:-missing}" "${actual_tier:-missing}" "${actual_effort:-missing}" >&2
    receipt="$(_lws_receipt "${request}" "${rc}" "${dispatch_out}" "blocked_control_plane" "${actual_json}" "blocked_control_plane")" || return $?
    _lws_persist_receipt "${receipt}" || { printf 'workflow-step: could not persist terminal receipt\n' >&2; printf '%s\n' "${receipt}"; return 1; }
    printf '%s\n' "${receipt}"
    return 1
  fi
  observed="$(_lws_terminal_from_dispatch_rc "${rc}")"
  receipt="$(_lws_receipt "${request}" "${rc}" "${dispatch_out}" "${observed}" "${actual_json}" "")" || return $?
  _lws_persist_receipt "${receipt}" || { printf 'workflow-step: could not persist terminal receipt\n' >&2; printf '%s\n' "${receipt}"; return 1; }
  printf '%s\n' "${receipt}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    run-step)
      [[ $# -eq 2 ]] || { printf 'Usage: %s run-step <request-json>\n' "$0" >&2; exit 2; }
      leadv2_workflow_run_step "$2" ;;
    *)
      printf 'Usage: %s run-step <request-json>\n' "$0" >&2; exit 2 ;;
  esac
fi
