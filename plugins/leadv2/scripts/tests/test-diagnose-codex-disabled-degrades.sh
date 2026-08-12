#!/usr/bin/env bash
# tests/test-diagnose-codex-disabled-degrades.sh — design §7 test 12.
#
# Asserts that --mode diagnose degrades the same way as --mode plan when
# codex is disabled: uses diagnose_run verbs, produces root-cause.md.
# Structurally: the diagnose mode in the engine shares the same
# classify_arm_failure path and arm_unavailable logic as plan mode.
#
# EXECUTION TEST (added fix-round): actually run the engine with --mode diagnose
# using a codex-disabled stub and assert the non-codex arm produces root-cause.md.
#
# Run: bash plugins/leadv2/scripts/tests/test-diagnose-codex-disabled-degrades.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENGINE="${SCRIPTS_ROOT}/leadv2-plan-run.sh"

PASS=0; FAIL=0
log()  { printf -- '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

bash -n "$0" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }

# ---------------------------------------------------------------------------
# Source-level assertions (structural checks)
# ---------------------------------------------------------------------------

# Case 1: diagnose mode has its own journal verb (diagnose_run).
if grep -q 'diagnose_run' "${ENGINE}" 2>/dev/null; then
  pass "diagnose mode uses diagnose_run verb"
else
  fail "diagnose mode missing diagnose_run verb"
fi

# Case 2: diagnose mode journals arm_unavailable.
if grep -q 'diagnose_run arm_unavailable' "${ENGINE}" 2>/dev/null; then
  pass "diagnose mode journals arm_unavailable"
else
  fail "diagnose mode missing arm_unavailable journal"
fi

# Case 3: diagnose mode writes root-cause.md (not context.yaml).
if grep -q 'root-cause.md' "${ENGINE}" 2>/dev/null; then
  pass "diagnose mode writes root-cause.md"
else
  fail "diagnose mode missing root-cause.md artifact"
fi

# Case 4: diagnose mode has no status=parked (degrades, never parks).
if ! grep -q 'status=parked' "${ENGINE}" 2>/dev/null; then
  pass "diagnose mode has no status=parked"
else
  fail "diagnose mode has status=parked (should not)"
fi

# ---------------------------------------------------------------------------
# EXECUTION TEST: codex disabled → non-codex arm runs, root-cause.md produced
# ---------------------------------------------------------------------------
TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT

ROOT_X="${TMP}/repo-x"
HANDOFF_X="${ROOT_X}/docs/handoff/diag-x"
mkdir -p "${ROOT_X}/.claude/ref" "${HANDOFF_X}"

cat > "${ROOT_X}/.claude/ref/leadv2-routing.yaml" <<'YAML'
router:
  glm_policy:
    codex_quota_gate:
      review_arm_order: [codex, sonnet, opus]
      review_threshold_pct: 95
YAML

# Stub codex: codex_skipped_by_policy (simulates codex disabled).
cat > "${TMP}/stub-codex-skip.sh" <<'SH'
#!/usr/bin/env bash
echo "codex_skipped_by_policy" >&2
exit 0
SH
chmod +x "${TMP}/stub-codex-skip.sh"

# Stub non-codex arm: emits valid diagnose YAML.
cat > "${TMP}/stub-diag-ok.sh" <<'SH'
#!/usr/bin/env bash
cat <<'YAML'
PLAN_YAML:
```yaml
root_cause: Race condition in the event loop
confidence: medium
evidence_files:
  - src/loop.ts
fix_hint: Add mutex around the shared state
alternates:
  - Incorrect timeout handling
```
YAML
SH
chmod +x "${TMP}/stub-diag-ok.sh"

# Stub quota-live.
cat > "${TMP}/stub-quota.sh" <<'SH'
#!/usr/bin/env bash
printf '{"status":"ok","five_hour":{"pct":10.0},"weekly":{"pct":10.0}}\n'
SH
chmod +x "${TMP}/stub-quota.sh"

printf 'Bug: intermittent crash in the event loop.' > "${TMP}/diag-mission.txt"

env -i HOME="${HOME}" PATH="${PATH}" \
  LEADV2_ROUTING_YAML="${ROOT_X}/.claude/ref/leadv2-routing.yaml" \
  GLM_POLICY_QUOTA_LIVE="${TMP}/stub-quota.sh" \
  LEADV2_DISPATCH_ARCHITECT_BIN="${TMP}/stub-diag-ok.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${TMP}/stub-codex-skip.sh" \
  LEADV2_PLAN_FANOUT=1 \
  bash "${ENGINE}" --task diag-x --root "${ROOT_X}" --handoff "${HANDOFF_X}" \
    --mode diagnose --mission-file "${TMP}/diag-mission.txt" \
    >"${TMP}/x-stdout.log" 2>"${TMP}/x-stderr.log"
rc_x=$?
_gate_x="${HANDOFF_X}/plan-gate.md"
_rcmd_x="${HANDOFF_X}/root-cause.md"

if [[ ${rc_x} -eq 0 && -f "${_gate_x}" && -f "${_rcmd_x}" ]]; then
  _status_x="$(sed -n 's/^status:[[:space:]]*//p' "${_gate_x}" | head -1)"
  if [[ "${_status_x}" == "pass" ]] && grep -q 'root_cause' "${_rcmd_x}" 2>/dev/null; then
    pass "codex-disabled diagnose: non-codex arm produced root-cause.md + gate pass"
  else
    fail "codex-disabled diagnose: status='${_status_x}' or root-cause.md missing root_cause"
  fi
else
  fail "codex-disabled diagnose: rc=${rc_x} gate=$( [[ -f "${_gate_x}" ]] && echo yes || echo no) rcmd=$( [[ -f "${_rcmd_x}" ]] && echo yes || echo no)"
  log "  stderr: $(tail -5 "${TMP}/x-stderr.log" 2>/dev/null)"
fi

printf -- '\nResults: %d pass, %d fail\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == "0" ]] || exit 1
exit 0
