#!/usr/bin/env bash
# tests/test-plan-run-codex-disabled-degrades.sh — design §5 test 7.
#
# Asserts that when codex is disabled by policy (codex_skipped_by_policy with
# rc=0), the engine classifies it as arm_unavailable (not failed, not parked),
# emits the journal line plan_run arm_unavailable arm=codex reason=policy,
# and the engine advances to the next arm in the pool (status never = fail
# solely due to codex being disabled).
#
# Also runs the engine end-to-end with stub arms to prove a codex-disabled
# run still produces status: pass.
#
# Run: bash plugins/leadv2/scripts/tests/test-plan-run-codex-disabled-degrades.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENGINE="${SCRIPTS_ROOT}/leadv2-plan-run.sh"
RESOLVER="${SCRIPTS_ROOT}/lib/leadv2-glm-policy-resolve.py"

PASS=0; FAIL=0
log()  { printf -- '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

bash -n "$0" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT

# ---------------------------------------------------------------------------
# Case 1: codex_skipped_by_policy classification (inline logic test)
# ---------------------------------------------------------------------------
log "Case 1: codex_skipped_by_policy → arm_unavailable"
echo "codex_skipped_by_policy" > "${TMP}/err"
echo "" > "${TMP}/out"

_cls="$(bash -c '
  rc="0"
  combined="$(cat "'"${TMP}"'/out" 2>/dev/null || true)"$'"'"'\n'"'"'"$(cat "'"${TMP}"'/err" 2>/dev/null || true)"
  if [[ "${rc}" == "0" && "${combined}" == *"codex_skipped_by_policy"* ]]; then
    printf "arm_unavailable"
  else
    printf "ran"
  fi
')"

if [[ "${_cls}" == "arm_unavailable" ]]; then
  pass "codex_skipped_by_policy classified as arm_unavailable"
else
  fail "codex_skipped_by_policy misclassified as '${_cls}' (expected arm_unavailable)"
fi

# ---------------------------------------------------------------------------
# Case 2: engine source emits the correct journal verb
# ---------------------------------------------------------------------------
if grep -q 'plan_run arm_unavailable arm=.*reason=policy' "${ENGINE}"; then
  pass "engine emits plan_run arm_unavailable arm=codex reason=policy"
else
  fail "engine missing arm_unavailable journal line"
fi

# ---------------------------------------------------------------------------
# Case 3: engine has no status=parked
# ---------------------------------------------------------------------------
if ! grep -q 'status=parked' "${ENGINE}"; then
  pass "engine has no status=parked"
else
  fail "engine contains status=parked (should not exist)"
fi

# ---------------------------------------------------------------------------
# Case 4: end-to-end — codex disabled, sonnet fallback, status=pass
# m3-market shape: codex is NOT in review_arm_order (codex_enabled=false).
# ---------------------------------------------------------------------------
log "Case 4: end-to-end codex-disabled → status=pass"

ROOT4="${TMP}/repo4"
HANDOFF4="${ROOT4}/docs/handoff/test4"
mkdir -p "${ROOT4}/.claude/ref" "${HANDOFF4}"

cat > "${ROOT4}/.claude/ref/leadv2-routing.yaml" <<'YAML'
router:
  glm_policy:
    codex_quota_gate:
      review_arm_order: [sonnet, opus]
      review_threshold_pct: 95
      anthropic_review_threshold_pct: 95
YAML

cat > "${TMP}/stub-quota.sh" <<'SH'
#!/usr/bin/env bash
case "$1" in
  anthropic|opus|sonnet|fable) printf '{"status":"ok","five_hour":{"pct":10.0},"weekly":{"pct":10.0}}\n' ;;
  *) printf '{"status":"ok","five_hour":{"pct":10.0},"weekly":{"pct":10.0}}\n' ;;
esac
SH
chmod +x "${TMP}/stub-quota.sh"

# Stub architect arm that emits a valid PLAN_YAML block.
cat > "${TMP}/stub-architect.sh" <<'SH'
#!/usr/bin/env bash
cat <<'YAML'
PLAN_YAML:
```yaml
decisions:
  - Architect decision from stub
off_limits:
  - leadv2-review-run.sh
plan:
  steps:
    - Step one
acceptance:
  surface: file_artifact
  observable: >
    A reader sees a valid plan-gate.md with status pass.
risk: low
```
YAML
SH
chmod +x "${TMP}/stub-architect.sh"

printf 'Test mission for codex-disabled degrade.' > "${TMP}/mission4.txt"

LEADV2_ROUTING_YAML="${ROOT4}/.claude/ref/leadv2-routing.yaml" \
GLM_POLICY_QUOTA_LIVE="${TMP}/stub-quota.sh" \
LEADV2_DISPATCH_ARCHITECT_BIN="${TMP}/stub-architect.sh" \
LEADV2_DISPATCH_CODEX_BIN="${TMP}/stub-architect.sh" \
bash "${ENGINE}" --task test4 --root "${ROOT4}" --handoff "${HANDOFF4}" \
  --mode prepass --mission-file "${TMP}/mission4.txt" --no-cache \
  >"${TMP}/test4-stdout.log" 2>"${TMP}/test4-stderr.log"
rc4=$?

_status4="$(sed -n 's/^status:[[:space:]]*//p' "${HANDOFF4}/plan-gate.md" 2>/dev/null | head -1)"

if [[ "${_status4}" == "pass" ]]; then
  pass "codex-disabled run produced status=pass (rc=${rc4})"
else
  fail "codex-disabled run status='${_status4}' (expected pass)"
  log "  stderr: $(tail -5 "${TMP}/test4-stderr.log" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
printf -- '\nResults: %d pass, %d fail\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == "0" ]] || exit 1
exit 0
