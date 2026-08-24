#!/usr/bin/env bash
# REVIEW-ENGINE-V3-CORE-01-R2: zero-provider executable contract.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="${SCRIPT_DIR}/../leadv2-review-run.sh"
PASS=0 FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

bash -n "${ENGINE}" || exit 1
bash -n "${SCRIPT_DIR}/test-review-engine-v3-core.sh" || exit 1
TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT
ROOT="${TMP}/repo"; mkdir -p "${ROOT}/.claude/ref"
LOG="${TMP}/calls.log"

cat > "${TMP}/resolver.py" <<'PY'
#!/usr/bin/env python3
print("reviewer=sonnet")
print("pool=sonnet:ok:")
print("refusal=")
PY
chmod +x "${TMP}/resolver.py"
cat > "${TMP}/architect.sh" <<'SH'
#!/usr/bin/env bash
role=""; mission=""
while [[ $# -gt 0 ]]; do case "$1" in --role) role="$2"; shift 2 ;; --mission-file) mission="$2"; shift 2 ;; *) shift ;; esac; done
printf '%s\n' "$role" >> "${CALL_LOG}"
[[ "$role" == hack-detect ]] && exit 0
cp "$mission" "${MISSION_CAPTURE}"
if [[ "${FIXTURE_FAIL:-0}" == 1 ]]; then
  printf 'REVIEW_VERDICT: FAIL\nREVIEW_FINDINGS: critical=0 high=1 medium=0 low=0\nFINDING: severity=High file=x.sh line=9 dimension=correctness desc=prior blocker\n'
else
  printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n'
fi
SH
chmod +x "${TMP}/architect.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "${TMP}/dispatch.sh"; chmod +x "${TMP}/dispatch.sh"

run_review() { # handoff diff task [environment assignments]
  local handoff="$1" diff="$2" task="$3"; shift 3
  env "$@" CALL_LOG="${LOG}" MISSION_CAPTURE="${TMP}/mission-${task}.md" \
    LEADV2_GLM_POLICY_RESOLVER="${TMP}/resolver.py" \
    LEADV2_DISPATCH_ARCHITECT_BIN="${TMP}/architect.sh" \
    LEADV2_DISPATCH_BIN="${TMP}/dispatch.sh" \
    bash "${ENGINE}" --task "${task}" --root "${ROOT}" --handoff "${handoff}" --diff "${diff}" --author glm >/dev/null 2>&1
}

# Ordinary path: one critic, no security pass, no explicit fanout setting.
H1="${ROOT}/docs/handoff/dispatch-ordinary"; mkdir -p "${H1}"
D1="${H1}/review.diff"; printf 'diff --git a/a b/a\n+x\n' > "${D1}"
: > "${LOG}"
run_review "${H1}" "${D1}" ordinary
[[ "$(grep -cx critic "${LOG}" || true)" == 1 && "$(grep -cx hack-detect "${LOG}" || true)" == 0 ]] \
  && pass "ordinary diff calls one reviewer and no security pass" \
  || fail "ordinary call count: $(tr '\n' ' ' < "${LOG}")"

# Explicit risk escalation retains one independent reviewer and adds security.
H2="${ROOT}/docs/handoff/dispatch-risk"; mkdir -p "${H2}"
D2="${H2}/review.diff"; printf 'diff --git a/b b/b\n+y\n' > "${D2}"
: > "${LOG}"
run_review "${H2}" "${D2}" risk LEADV2_REVIEW_SECURITY_PASS=1
[[ "$(grep -cx critic "${LOG}" || true)" == 1 && "$(grep -cx hack-detect "${LOG}" || true)" == 1 ]] \
  && pass "explicit risk adds exactly one security pass" \
  || fail "risk call count: $(tr '\n' ' ' < "${LOG}")"

# Failed first review + changed diff gets a single blocker-only verification pass;
# its state counters restart for the new diff and an unchanged failed re-run caps.
H3="${ROOT}/docs/handoff/dispatch-recheck"; mkdir -p "${H3}"
D3="${H3}/review.diff"; printf 'diff --git a/c b/c\n+broken\n' > "${D3}"
: > "${LOG}"
run_review "${H3}" "${D3}" recheck FIXTURE_FAIL=1; rc=$?
[[ "${rc}" == 7 ]] || fail "first blocker review exited ${rc}"
printf 'diff --git a/c b/c\n+fixed\n' > "${D3}"
run_review "${H3}" "${D3}" recheck FIXTURE_FAIL=1; rc=$?
MISSION="${TMP}/mission-recheck.md"
if [[ "${rc}" == 7 ]] && grep -q 'VERIFICATION-ONLY ROUND 2' "${MISSION}" && grep -q 'prior blocker' "${MISSION}" && ! grep -q 'Review this diff through FIVE lenses' "${MISSION}"; then
  pass "changed failed diff uses targeted blocker recheck"
else
  fail "changed diff was not targeted (rc=${rc})"
fi
[[ "$(sed -n 's/^attempts=//p' "${H3}/.review-round.state")" == 1 ]] \
  && pass "changed diff starts fresh review state" \
  || fail "changed diff inherited attempts"
run_review "${H3}" "${D3}" recheck FIXTURE_FAIL=1; rc=$?
[[ "${rc}" == 8 ]] && pass "unchanged failed recheck is capped" || fail "recheck cap exited ${rc}"

printf 'review-engine-v3-core: PASS=%s FAIL=%s\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
