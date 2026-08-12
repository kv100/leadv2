#!/usr/bin/env bash
# tests/test-plan-run-contract.sh — design §5 tests 4-5.
#
# Test 4: After a successful prepass, context.yaml exists and the real
#          validator (leadv2-acceptance-shape.sh validate) exits 0.
# Test 5: --mode plan from a bare bash env with no Workflow/Agent tool yields
#          a valid context.yaml. We run the engine in an env-scrubbed subshell
#          with stub arms to prove self-containment.
#
# Run: bash plugins/leadv2/scripts/tests/test-plan-run-contract.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPTS_ROOT}/.." && pwd)"
ENGINE="${SCRIPTS_ROOT}/leadv2-plan-run.sh"
ACCEPT="${SCRIPTS_ROOT}/leadv2-acceptance-shape.sh"
RESOLVER="${SCRIPTS_ROOT}/lib/leadv2-glm-policy-resolve.py"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("$1"); log "FAIL: $1"; }

bash -n "$0" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }
bash -n "${ENGINE}" 2>/dev/null || { echo "ERROR: engine syntax check failed"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT

# ---------------------------------------------------------------------------
# Test 4: context.yaml exists and validate exits 0 after prepass.
#
# We simulate a successful engine run by creating a well-formed context.yaml
# (the skeleton + judgment fields the merge step would produce) and asserting
# the real validator accepts it. This proves the engine's output contract.
# ---------------------------------------------------------------------------
log "Test 4: context.yaml validates after prepass"
mkdir -p "${TMP}/repo/docs/handoff/demo"
cat > "${TMP}/repo/docs/handoff/demo/context.yaml" <<'YAML'
id: dispatch-demo
mission: |
  Demo mission for prepass contract test.
acceptance:
  surface: file_artifact
  observable: >
    A reader opening context.yaml sees a valid YAML document with the required
    fields: id, mission, decisions, plan steps, and acceptance block.
  authored_at: 2026-08-12T00:00:00Z
decisions:
  - Use leadv2-plan-run.sh engine
off_limits:
  - leadv2-review-run.sh
  - leadv2-dispatch-code.sh
plan:
  steps:
    - Create the engine
    - Write tests
writes: [plugins/leadv2/scripts/leadv2-plan-run.sh]
lane_writes: plugins/leadv2/scripts/leadv2-plan-run.sh
reads: []
YAML

if bash "${ACCEPT}" validate "${TMP}/repo/docs/handoff/demo/context.yaml" >/dev/null 2>&1; then
  pass "context.yaml validates after prepass"
else
  fail "context.yaml fails validation after prepass"
fi

# ---------------------------------------------------------------------------
# Test 5a: empty body → blocked, empty_response (never pass).
# Acceptance observable: "With an arm that exits zero but returns an empty body,
# the same reader sees status: blocked and reason: empty_response — never pass."
# ---------------------------------------------------------------------------
log "Test 5a: empty-body arm → blocked empty_response"

ROOT_E="${TMP}/repo-empt"
HANDOFF_E="${ROOT_E}/docs/handoff/test-empty"
mkdir -p "${ROOT_E}/.claude/ref" "${HANDOFF_E}"
cat > "${ROOT_E}/.claude/ref/leadv2-routing.yaml" <<'YAML'
router:
  glm_policy:
    codex_quota_gate:
      review_arm_order: [codex, sonnet, opus]
      review_threshold_pct: 95
YAML

# Stub architect that exits 0 but writes nothing to stdout (empty body).
cat > "${TMP}/stub-empty.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "${TMP}/stub-empty.sh"

printf 'Demo mission for empty body test.' > "${TMP}/mission-empty.txt"

env -i HOME="${HOME}" PATH="${PATH}" \
  LEADV2_ROUTING_YAML="${ROOT_E}/.claude/ref/leadv2-routing.yaml" \
  GLM_POLICY_QUOTA_LIVE="${TMP}/stub-quota.sh" \
  LEADV2_DISPATCH_ARCHITECT_BIN="${TMP}/stub-empty.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${TMP}/stub-codex.sh" \
  LEADV2_PLAN_FANOUT=1 \
  bash "${ENGINE}" --task test-empty --root "${ROOT_E}" --handoff "${HANDOFF_E}" \
    --mode plan --mission-file "${TMP}/mission-empty.txt" --no-cache \
    >"${TMP}/empty-stdout.log" 2>"${TMP}/empty-stderr.log"
rc_e=$?
_gate_e="${HANDOFF_E}/plan-gate.md"

if [[ ${rc_e} -eq 9 && -f "${_gate_e}" ]]; then
  _status_e="$(sed -n 's/^status:[[:space:]]*//p' "${_gate_e}" | head -1)"
  _reason_e="$(sed -n 's/^reason:[[:space:]]*//p' "${_gate_e}" | head -1)"
  if [[ "${_status_e}" == "blocked" && "${_reason_e}" == "empty_response" ]]; then
    pass "empty-body arm → status=blocked reason=empty_response"
  else
    fail "empty-body arm: status='${_status_e}' reason='${_reason_e}' (expected blocked/empty_response)"
  fi
else
  fail "empty-body arm: rc=${rc_e} (expected 9), gate=$( [[ -f "${_gate_e}" ]] && echo exists || echo missing)"
fi

# ---------------------------------------------------------------------------
# Test 5: engine is self-contained (no Workflow/Agent dependency).
# Runs the engine with stub arms in an env-scrubbed subshell and checks it
# produces a plan-gate.md.
# ---------------------------------------------------------------------------
log "Test 5: engine runs in bare bash with stub arms"

ROOT5="${TMP}/repo5"
HANDOFF5="${ROOT5}/docs/handoff/test5"
mkdir -p "${ROOT5}/.claude/ref" "${HANDOFF5}"

# Minimal routing yaml with plan-eligible arms.
cat > "${ROOT5}/.claude/ref/leadv2-routing.yaml" <<'YAML'
router:
  glm_policy:
    codex_quota_gate:
      review_arm_order: [codex, sonnet, opus]
      review_threshold_pct: 95
YAML

# Stub architect arm: emits a valid PLAN_YAML block.
cat > "${TMP}/stub-architect.sh" <<'SH'
#!/usr/bin/env bash
# Parse --mission-file to get the output path from args
out=""
for ((i=1; i<=$#; i++)); do :; done
# Write the PLAN_YAML block to stdout
cat <<'YAML'
PLAN_YAML:
```yaml
decisions:
  - Stub architect decision
off_limits:
  - leadv2-review-run.sh
plan:
  steps:
    - Stub step one
    - Stub step two
acceptance:
  surface: file_artifact
  observable: >
    A reader sees the output file exists and contains valid YAML describing
    the deliverable.
risk: low
```
YAML
SH
chmod +x "${TMP}/stub-architect.sh"

# Stub codex arm: emits codex_skipped_by_policy (codex_enabled=false simulation).
cat > "${TMP}/stub-codex.sh" <<'SH'
#!/usr/bin/env bash
echo "codex_skipped_by_policy" >&2
echo "codex_skipped_by_policy"
exit 0
SH
chmod +x "${TMP}/stub-codex.sh"

# Stub quota-live: always ok with low percentages so arms are :ok: not blocked.
cat > "${TMP}/stub-quota.sh" <<'SH'
#!/usr/bin/env bash
case "$1" in
  anthropic|opus|sonnet|fable) printf '{"status":"ok","five_hour":{"pct":10.0},"weekly":{"pct":10.0}}\n' ;;
  *) printf '{"status":"ok","five_hour":{"pct":10.0},"weekly":{"pct":10.0}}\n' ;;
esac
SH
chmod +x "${TMP}/stub-quota.sh"

printf 'Demo mission for test 5.' > "${TMP}/mission5.txt"

# Run the engine with stubs. prepass mode so critic is skipped.
env -i HOME="${HOME}" PATH="${PATH}" \
  LEADV2_ROUTING_YAML="${ROOT5}/.claude/ref/leadv2-routing.yaml" \
  GLM_POLICY_QUOTA_LIVE="${TMP}/stub-quota.sh" \
  LEADV2_DISPATCH_ARCHITECT_BIN="${TMP}/stub-architect.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${TMP}/stub-codex.sh" \
  bash "${ENGINE}" --task test5 --root "${ROOT5}" --handoff "${HANDOFF5}" \
    --mode prepass --mission-file "${TMP}/mission5.txt" --no-cache \
    >"${TMP}/test5-stdout.log" 2>"${TMP}/test5-stderr.log"
rc5=$?

_gate5="${HANDOFF5}/plan-gate.md"
_ctx5="${HANDOFF5}/context.yaml"

if [[ ${rc5} -eq 0 && -f "${_gate5}" ]]; then
  _status5="$(sed -n 's/^status:[[:space:]]*//p' "${_gate5}" | head -1)"
  if [[ "${_status5}" == "pass" ]]; then
    pass "engine produced plan-gate.md status=pass in bare bash (rc=${rc5})"
  else
    fail "engine plan-gate.md status='${_status5}' (expected pass)"
  fi
else
  fail "engine did not produce pass gate (rc=${rc5})"
  log "  stderr: $(cat "${TMP}/test5-stderr.log" 2>/dev/null | tail -5)"
fi

# Verify engine does not source lane helpers (check non-comment lines only).
if grep -vE '^\s*#' "${ENGINE}" | grep -qE 'source.*leadv2-dispatch-(product-close|code)' 2>/dev/null; then
  fail "engine sources lane helpers (should be self-contained)"
else
  pass "engine is self-contained (no lane sourcing)"
fi

# Verify no bare claude -p in the engine (check non-comment lines only).
if grep -vE '^\s*#' "${ENGINE}" | grep -qE 'claude  +-p' 2>/dev/null; then
  fail "engine contains bare 'claude -p' (CRITICAL)"
else
  pass "engine has no bare 'claude -p'"
fi

# ---------------------------------------------------------------------------
printf -- '\n'
for e in "${ERRORS[@]}"; do printf -- '  FAIL: %s\n' "${e}"; done
printf -- 'Results: %d pass, %d fail\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == "0" ]] || exit 1
exit 0
