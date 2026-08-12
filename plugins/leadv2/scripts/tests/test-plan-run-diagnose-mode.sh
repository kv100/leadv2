#!/usr/bin/env bash
# tests/test-plan-run-diagnose-mode.sh — design §5 tests 10, 12.
#
# Test 10: --mode diagnose prompt contains no persona-engine constants
#          (no journalctl -u persona-engine, no persona_engine table names).
# Test 12: diagnose degrade proof with diagnose_run verbs — the engine journals
#          arm_unavailable in diagnose mode just as in plan mode, and
#          root-cause.md is the output artifact.
#
# EXECUTION TESTS (added fix-round): actually run the engine with --mode diagnose
# using stub arms and assert correct gate/artifact behaviour — not just grep
# the source.
#
# Run: bash plugins/leadv2/scripts/tests/test-plan-run-diagnose-mode.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENGINE="${SCRIPTS_ROOT}/leadv2-plan-run.sh"

PASS=0; FAIL=0
log()  { printf -- '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

bash -n "$0" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }
bash -n "${ENGINE}" 2>/dev/null || { echo "ERROR: engine syntax check failed"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT

# ---------------------------------------------------------------------------
# Source-level assertions (fast structural checks)
# ---------------------------------------------------------------------------

# Test 10: engine contains no persona-engine constants in non-comment lines.
_engine_nocomments="$(grep -vE '^\s*#' "${ENGINE}" 2>/dev/null)"
log "Test 10: diagnose mode has no persona-engine constants"
if printf '%s\n' "${_engine_nocomments}" | grep -qiE 'journalctl.*persona-engine|persona_engine' 2>/dev/null; then
  fail "engine contains persona-engine constants (should be portable)"
else
  pass "engine has no persona-engine constants"
fi

# Also verify --log-path and --diff-paths are accepted as flags.
if grep -q '\-\-log-path' "${ENGINE}" && grep -q '\-\-diff-paths' "${ENGINE}"; then
  pass "engine accepts --log-path and --diff-paths flags"
else
  fail "engine missing --log-path or --diff-paths flag"
fi

# Test 12: verify engine source contains diagnose_run journal verbs.
log "Test 12: diagnose mode journals arm_unavailable and writes root-cause.md"
if grep -q 'diagnose_run arm_unavailable' "${ENGINE}"; then
  pass "engine journals diagnose_run arm_unavailable"
else
  fail "engine missing diagnose_run arm_unavailable journal"
fi

# Verify the gate artifact for diagnose is root-cause.md (not context.yaml).
if grep -q 'root-cause.md' "${ENGINE}"; then
  pass "diagnose gate artifact is root-cause.md"
else
  fail "diagnose gate missing root-cause.md artifact"
fi

# Verify diagnose uses exit code 9 for blocked (not 4 or 1).
_diag_blocked_exits="$(grep -A2 'diagnose_run.*status=blocked' "${ENGINE}" | grep -oE 'exit [0-9]+' | sort -u)"
if printf '%s' "${_diag_blocked_exits}" | grep -q 'exit 9'; then
  pass "diagnose blocked exits with code 9"
else
  fail "diagnose blocked exit code wrong: '${_diag_blocked_exits}' (expected 9)"
fi

# ---------------------------------------------------------------------------
# EXECUTION TESTS — actually run --mode diagnose with stub arms
# ---------------------------------------------------------------------------

# Shared stubs and fixtures.
setup_diagnose_env() { # <root> <handoff>
  local _root="$1" _hoff="$2"
  mkdir -p "${_root}/.claude/ref" "${_hoff}"
  cat > "${_root}/.claude/ref/leadv2-routing.yaml" <<'YAML'
router:
  glm_policy:
    codex_quota_gate:
      review_arm_order: [codex, sonnet, opus]
      review_threshold_pct: 95
YAML

  # Stub architect arm that emits a valid diagnose PLAN_YAML block.
  cat > "${TMP}/stub-diag-ok.sh" <<'SH'
#!/usr/bin/env bash
cat <<'YAML'
PLAN_YAML:
```yaml
root_cause: Missing return statement in the handler
confidence: high
evidence_files:
  - src/handler.ts
fix_hint: Add explicit return before the closing brace
alternates:
  - Null pointer from upstream caller
```
YAML
SH
  chmod +x "${TMP}/stub-diag-ok.sh"

  # Stub architect arm that exits 0 but writes nothing (empty body).
  cat > "${TMP}/stub-empty.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "${TMP}/stub-empty.sh"

  # Stub codex arm: codex_skipped_by_policy.
  cat > "${TMP}/stub-codex.sh" <<'SH'
#!/usr/bin/env bash
echo "codex_skipped_by_policy" >&2
exit 0
SH
  chmod +x "${TMP}/stub-codex.sh"

  # Stub quota-live: always ok.
  cat > "${TMP}/stub-quota.sh" <<'SH'
#!/usr/bin/env bash
printf '{"status":"ok","five_hour":{"pct":10.0},"weekly":{"pct":10.0}}\n'
SH
  chmod +x "${TMP}/stub-quota.sh"
}

# --- Test D1: successful diagnose run → root-cause.md + gate pass ----------
log "Test D1: diagnose mode with valid arm → root-cause.md + gate pass"
ROOT_D1="${TMP}/repo-d1"
HANDOFF_D1="${ROOT_D1}/docs/handoff/diag-ok"
setup_diagnose_env "${ROOT_D1}" "${HANDOFF_D1}"
printf 'Bug: the handler returns undefined instead of the result object.' > "${TMP}/diag-mission.txt"

env -i HOME="${HOME}" PATH="${PATH}" \
  LEADV2_ROUTING_YAML="${ROOT_D1}/.claude/ref/leadv2-routing.yaml" \
  GLM_POLICY_QUOTA_LIVE="${TMP}/stub-quota.sh" \
  LEADV2_DISPATCH_ARCHITECT_BIN="${TMP}/stub-diag-ok.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${TMP}/stub-codex.sh" \
  LEADV2_PLAN_FANOUT=1 \
  bash "${ENGINE}" --task diag-ok --root "${ROOT_D1}" --handoff "${HANDOFF_D1}" \
    --mode diagnose --mission-file "${TMP}/diag-mission.txt" \
    >"${TMP}/d1-stdout.log" 2>"${TMP}/d1-stderr.log"
rc_d1=$?
_gate_d1="${HANDOFF_D1}/plan-gate.md"
_rc_md="${HANDOFF_D1}/root-cause.md"

if [[ ${rc_d1} -eq 0 && -f "${_gate_d1}" && -f "${_rc_md}" ]]; then
  _status_d1="$(sed -n 's/^status:[[:space:]]*//p' "${_gate_d1}" | head -1)"
  _mode_d1="$(sed -n 's/^mode:[[:space:]]*//p' "${_gate_d1}" | head -1)"
  if [[ "${_status_d1}" == "pass" && "${_mode_d1}" == "diagnose" ]]; then
    if grep -q 'root_cause' "${_rc_md}" 2>/dev/null; then
      pass "diagnose ok: gate=pass mode=diagnose root-cause.md has root_cause"
    else
      fail "diagnose ok: root-cause.md missing root_cause field"
    fi
  else
    fail "diagnose ok: status='${_status_d1}' mode='${_mode_d1}' (expected pass/diagnose)"
  fi
else
  fail "diagnose ok: rc=${rc_d1} gate=$( [[ -f "${_gate_d1}" ]] && echo yes || echo no) rcmd=$( [[ -f "${_rc_md}" ]] && echo yes || echo no)"
  log "  stderr: $(tail -5 "${TMP}/d1-stderr.log" 2>/dev/null)"
fi

# --- Test D2: empty body arm → blocked empty_response ----------------------
log "Test D2: diagnose mode with empty-body arm → blocked empty_response"
ROOT_D2="${TMP}/repo-d2"
HANDOFF_D2="${ROOT_D2}/docs/handoff/diag-empty"
setup_diagnose_env "${ROOT_D2}" "${HANDOFF_D2}"
printf 'Bug: something crashes.' > "${TMP}/diag-mission2.txt"

env -i HOME="${HOME}" PATH="${PATH}" \
  LEADV2_ROUTING_YAML="${ROOT_D2}/.claude/ref/leadv2-routing.yaml" \
  GLM_POLICY_QUOTA_LIVE="${TMP}/stub-quota.sh" \
  LEADV2_DISPATCH_ARCHITECT_BIN="${TMP}/stub-empty.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${TMP}/stub-codex.sh" \
  LEADV2_PLAN_FANOUT=1 \
  bash "${ENGINE}" --task diag-empty --root "${ROOT_D2}" --handoff "${HANDOFF_D2}" \
    --mode diagnose --mission-file "${TMP}/diag-mission2.txt" \
    >"${TMP}/d2-stdout.log" 2>"${TMP}/d2-stderr.log"
rc_d2=$?
_gate_d2="${HANDOFF_D2}/plan-gate.md"

if [[ ${rc_d2} -eq 9 && -f "${_gate_d2}" ]]; then
  _status_d2="$(sed -n 's/^status:[[:space:]]*//p' "${_gate_d2}" | head -1)"
  _reason_d2="$(sed -n 's/^reason:[[:space:]]*//p' "${_gate_d2}" | head -1)"
  if [[ "${_status_d2}" == "blocked" && "${_reason_d2}" == "empty_response" ]]; then
    pass "diagnose empty: status=blocked reason=empty_response"
  else
    fail "diagnose empty: status='${_status_d2}' reason='${_reason_d2}' (expected blocked/empty_response)"
  fi
else
  fail "diagnose empty: rc=${rc_d2} (expected 9)"
  log "  stderr: $(tail -5 "${TMP}/d2-stderr.log" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
printf -- '\nResults: %d pass, %d fail\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == "0" ]] || exit 1
exit 0
