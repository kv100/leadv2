#!/usr/bin/env bash
# FP-07: a <200-byte paid review body retries once on an untried distinct arm.
# NEGATIVE CONTROL: run a mutant that retries the SAME arm; it must run red.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENGINE="${SCRIPTS_ROOT}/leadv2-review-run.sh"
PASS=0 FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

bash -n "${ENGINE}" || exit 1
TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT
ROOT="${TMP}/repo"; mkdir -p "${ROOT}/.claude/ref"
printf 'router:\n  glm_policy:\n    protected_path_patterns:\n      - "secure/*"\n' > "${ROOT}/.claude/ref/leadv2-routing.yaml"

cat > "${TMP}/resolver.py" <<'PY'
#!/usr/bin/env python3
print("reviewer=sonnet")
print("pool=sonnet:ok:,opus:ok:")
print("refusal=")
PY
chmod +x "${TMP}/resolver.py"

cat > "${TMP}/architect.sh" <<'SH'
#!/usr/bin/env bash
model=""
while [[ $# -gt 0 ]]; do
  case "$1" in --model) model="$2"; shift 2 ;; *) shift ;; esac
done
printf '%s\n' "$model" >> "${CALL_LOG}"
if [[ "${REVIEW_BODY_MODE}" == all_lost || "${model}" == sonnet ]]; then
  printf 'short paid review body\n' # deliberately <200 bytes, no verdict
  printf 'cost recorded: reviewer/%s\n' "$model" >&2
  exit 0
fi
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n\n'
printf '%*s\n' 320 '' | tr ' ' x
SH
chmod +x "${TMP}/architect.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "${TMP}/dispatch.sh"; chmod +x "${TMP}/dispatch.sh"
cat > "${TMP}/journal.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${JOURNAL_LOG}"
SH
chmod +x "${TMP}/journal.sh"

run_case() { # <engine> <task> <mode>
  local runner="$1" task="$2" mode="$3" handoff
  handoff="${ROOT}/docs/handoff/${task}"
  mkdir -p "${handoff}"
  printf 'diff --git a/a b/a\n+x\n' > "${handoff}/review.diff"
  CALL_LOG="${TMP}/${task}.calls" REVIEW_BODY_MODE="${mode}" \
    JOURNAL_LOG="${TMP}/${task}.journal" LEADV2_JOURNAL_BIN="${TMP}/journal.sh" \
    LEADV2_GLM_POLICY_RESOLVER="${TMP}/resolver.py" \
    LEADV2_DISPATCH_ARCHITECT_BIN="${TMP}/architect.sh" \
    LEADV2_DISPATCH_BIN="${TMP}/dispatch.sh" \
    LEADV2_ROUTING_YAML="${ROOT}/.claude/ref/leadv2-routing.yaml" \
    LEADV2_DISPATCH_LANE_WRITES="app/review.sh" \
    bash "${runner}" --task "${task}" --root "${ROOT}" --handoff "${handoff}" \
      --diff "${handoff}/review.diff" --author glm > "${TMP}/${task}.out" 2> "${TMP}/${task}.err"
}

run_case "${ENGINE}" retry-pass healthy; rc=$?
if [[ "${rc}" -eq 0 ]] && [[ "$(tr '\n' ',' < "${TMP}/retry-pass.calls")" == 'sonnet,opus,' ]] && \
    grep -q 'review_arm_retry from=sonnet to=opus' "${TMP}/retry-pass.err" && \
    grep -q '^append retry-pass review_arm_retry review_arm_retry from=sonnet to=opus$' "${TMP}/retry-pass.journal" && \
    grep -q '^status: pass$' "${ROOT}/docs/handoff/retry-pass/review-gate.md"; then
  pass "lost sonnet body retries once on distinct opus and passes"
else
  fail "distinct retry failed (rc=${rc})"
fi

run_case "${ENGINE}" both-lost all_lost; rc=$?
if [[ "${rc}" -eq 6 ]] && [[ "$(tr '\n' ',' < "${TMP}/both-lost.calls")" == 'sonnet,opus,' ]] && \
    grep -q 'review_arm_retry from=sonnet to=opus' "${TMP}/both-lost.err" && \
    grep -q '^status: blocked$' "${ROOT}/docs/handoff/both-lost/review-gate.md" && \
    grep -q '^reason: review_body_lost$' "${ROOT}/docs/handoff/both-lost/review-gate.md"; then
  pass "both bodies lost blocks after one distinct retry"
else
  fail "both-lost terminal state wrong (rc=${rc})"
fi

# The mutation replaces the distinct-arm selector with the failed arm itself.
# It must not pass the healthy scenario: this is the required red control.
MUTANT="${TMP}/leadv2-review-run-mutant.sh"
cp "${ENGINE}" "${MUTANT}"
ln -s "${SCRIPTS_ROOT}/lib" "${TMP}/lib"
perl -0pi -e 's/\$\(_review_next_distinct_ok_arm[^\n]+\|\| true\)/\${_arm}/' "${MUTANT}"
run_case "${MUTANT}" same-arm-mutant healthy; mutant_rc=$?
if [[ "${mutant_rc}" -ne 0 ]] && [[ "$(tr '\n' ',' < "${TMP}/same-arm-mutant.calls")" == 'sonnet,sonnet,' ]]; then
  pass "negative control ran red: same-arm retry is caught"
else
  fail "negative control did not run red (rc=${mutant_rc})"
fi

printf 'review-body-lost-retry-distinct-arm: PASS=%s FAIL=%s\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
