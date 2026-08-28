#!/usr/bin/env bash
# FP-07: a <200-byte paid review body retries once on an untried distinct arm.
# NEGATIVE CONTROL (1): run a mutant that retries the SAME arm; it must run red.
# FP-07b: the retry pool must come from the RESOLVER'S REAL output format — the
# fixture below is the captured stdout of the actual lib/leadv2-glm-policy-resolve.py
# (gate block arm=/rule=... above the pool= block), not a hand-typed stub, so a
# parse that grabs the wrong token re-runs red (NEGATIVE CONTROL (2): mutate the
# engine's pool= parse to arm=; the fixture retry must fail).
# The gate-shape-only case pins the live 2026-08-28 FP-03 symptom: a resolver
# stdout with NO pool= line must fail closed (refusal=resolver_error_failclosed,
# stderr captured to review-pool-resolver.err), never parse as a silent empty pool.
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
if [[ "${REVIEW_BODY_MODE}" == all_lost || "${model}" == sonnet \
      || "${model}" == "${REVIEW_BODY_LOST_ARM:-__none__}" ]] \
   && [[ "${model}" != "${REVIEW_BODY_HEALTHY_ARM:-__none__}" ]]; then
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

run_case() { # <engine> <task> <mode> [resolver]
  local runner="$1" task="$2" mode="$3" handoff
  local resolver="${4:-${TMP}/resolver.py}"
  handoff="${ROOT}/docs/handoff/${task}"
  mkdir -p "${handoff}"
  printf 'diff --git a/a b/a\n+x\n' > "${handoff}/review.diff"
  CALL_LOG="${TMP}/${task}.calls" REVIEW_BODY_MODE="${mode}" \
    JOURNAL_LOG="${TMP}/${task}.journal" LEADV2_JOURNAL_BIN="${TMP}/journal.sh" \
    LEADV2_GLM_POLICY_RESOLVER="${resolver}" \
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

# ---------------------------------------------------------------------------
# FP-07b: fixture = REAL resolver output, captured from the actual resolver with
# deterministic quota injections (codex 98% blocked, glm 95% blocked, anthropic
# 30% ok, kimi bin missing -> unknown, author=glm excluded). The captured shape
# is the live contract: the gate block (arm=/rule=/tier=/...) prints ABOVE the
# pool= block, so a parse keyed on the wrong token sees gate lines and starves.
# ---------------------------------------------------------------------------
REAL_RESOLVER="${SCRIPTS_ROOT}/lib/leadv2-glm-policy-resolve.py"
cat > "${TMP}/quota-live.sh" <<'SH'
#!/usr/bin/env bash
case "$1" in
  codex)     printf '{"status":"ok","binding_window":"primary","windows":[{"kind":"primary","used_percent":98.0}]}\n' ;;
  glm)       printf '{"status":"ok","five_hour":{"pct":95.0},"weekly":{"pct":95.0}}\n' ;;
  anthropic) printf '{"status":"ok","accounts":[{"active":true,"account_label":"a","five_hour_pct":30.0,"seven_day_pct":30.0}]}\n' ;;
  *)         printf '{"status":"ok"}\n' ;;
esac
SH
chmod +x "${TMP}/quota-live.sh"
env -u LEADV2_QUOTA_LOCKOUT_DIR LEADV2_DISPATCH_KIMI_BIN=/nonexistent-kimi \
  python3 "${REAL_RESOLVER}" \
  --routing-yaml "${ROOT}/.claude/ref/leadv2-routing.yaml" --job review --base-arm codex \
  --review-pool --author glm --signals '{"protected_path":false}' \
  --quota-live "${TMP}/quota-live.sh" > "${TMP}/pool-fixture.txt"
grep -q '^pool=.*opus:ok:.*sonnet:ok:' "${TMP}/pool-fixture.txt" || { fail "fixture capture lost the pool block"; exit 1; }
grep -q '^arm=' "${TMP}/pool-fixture.txt" || { fail "fixture capture lost the gate block"; exit 1; }
# The engine-side stub replays the captured bytes verbatim (ignores its args).
# It must be a python file: the engine runs its resolver with python3.
cat > "${TMP}/fixture-resolver.py" <<PY
#!/usr/bin/env python3
import sys
sys.stdout.write(open("${TMP}/pool-fixture.txt").read())
PY
chmod +x "${TMP}/fixture-resolver.py"

# Live-contract retry: primary reviewer is opus (first :ok: in the REAL pool);
# its body is lost; the retry must land on sonnet from the SAME pool bytes.
# HEALTHY_ARM exempts sonnet from the FP-07 always-loses stub rule above.
REVIEW_BODY_LOST_ARM=opus REVIEW_BODY_HEALTHY_ARM=sonnet \
  run_case "${ENGINE}" fixture-retry healthy "${TMP}/fixture-resolver.py"; rc=$?
if [[ "${rc}" -eq 0 ]] && [[ "$(tr '\n' ',' < "${TMP}/fixture-retry.calls")" == 'opus,sonnet,' ]] && \
    grep -q 'review_arm_retry from=opus to=sonnet' "${TMP}/fixture-retry.err" && \
    grep -q '^status: pass$' "${ROOT}/docs/handoff/fixture-retry/review-gate.md"; then
  pass "real-format resolver fixture: lost opus body retries on distinct sonnet"
else
  fail "real-format fixture retry failed (rc=${rc})"
fi

# Gate-shape-only stdout (the live FP-03 symptom: arm=/rule= lines, NO pool=)
# must fail closed with a named refusal + captured stderr, never parse as a
# silent empty pool, and never spend a reviewer arm.
cat > "${TMP}/gateshape-resolver.py" <<'PY'
#!/usr/bin/env python3
import sys
print("arm=codex")
print("rule=none")
print("reason=base_arm_default")
print("tier=standard")
print("codex_quota_blocked=0")
sys.stderr.write("resolver boom: pool block lost\n")
PY
chmod +x "${TMP}/gateshape-resolver.py"
run_case "${ENGINE}" gateshape-failclosed healthy "${TMP}/gateshape-resolver.py"; rc=$?
if [[ "${rc}" -eq 9 ]] \
    && grep -q '^reason: all_arms_unavailable$' "${ROOT}/docs/handoff/gateshape-failclosed/review-gate.md" \
    && grep -q 'refusal=resolver_error_failclosed' "${TMP}/gateshape-failclosed.err" \
    && grep -q 'review_pool_resolver task=gateshape-failclosed rc=0' "${TMP}/gateshape-failclosed.err" \
    && grep -q 'pool block lost' "${ROOT}/docs/handoff/gateshape-failclosed/review-pool-resolver.err" \
    && { [[ ! -s "${TMP}/gateshape-failclosed.calls" ]]; }; then
  pass "gate-shape-only resolver output fails closed with refusal + stderr artifact"
else
  fail "gate-shape-only fail-closed wrong (rc=${rc})"
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

# NEGATIVE CONTROL (2, FP-07b): revert the engine's pool parse to the WRONG
# token (pool= -> arm=, the pre-fix mis-encoding that starved the retry live).
# Against the REAL-format fixture the mutant must run red: the gate block's
# arm= line is not a pool, so the retry finds no candidate and the gate blocks.
MUTANT2="${TMP}/leadv2-review-run-mutant2.sh"
cp "${ENGINE}" "${MUTANT2}"
perl -0pi -e 's{s/\^pool=//p}{s/^arm=//p}' "${MUTANT2}"
grep -q "s/\^arm=//p" "${MUTANT2}" || { fail "wrong-token mutant did not apply"; exit 1; }
REVIEW_BODY_LOST_ARM=opus run_case "${MUTANT2}" wrong-token-mutant healthy "${TMP}/fixture-resolver.py"; mutant2_rc=$?
if [[ "${mutant2_rc}" -eq 6 ]] && [[ "$(tr '\n' ',' < "${TMP}/wrong-token-mutant.calls")" == 'opus,' ]] && \
    grep -q '^reason: review_body_lost$' "${ROOT}/docs/handoff/wrong-token-mutant/review-gate.md"; then
  pass "negative control ran red: wrong-token pool parse starves the retry"
else
  fail "wrong-token negative control did not run red (rc=${mutant2_rc})"
fi

printf 'review-body-lost-retry-distinct-arm: PASS=%s FAIL=%s\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
