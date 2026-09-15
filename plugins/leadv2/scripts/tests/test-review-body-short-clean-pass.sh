#!/usr/bin/env bash
# REVIEW-BODY-LOST-FIRES-ON-A-SHORT-CLEAN-PASS-01.
# run-all-triggers: leadv2-review-run.sh
#
# The persistence guard and the verdict parser share
# review_body_has_parseable_verdict.  The two live controls below mutate that
# exact guard line, and their anchors must match once or this suite fails.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENGINE="${SCRIPTS_ROOT}/leadv2-review-run.sh"
PASS=0 FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }
show_gate() { printf '%s\n' "--- $1 gate ---"; cat "$2"; }

bash -n "${ENGINE}" || { fail 'engine bash -n'; exit 1; }
TMP="$(mktemp -d /private/tmp/review-body-short-clean-pass.XXXXXX)"; trap 'rm -rf "${TMP}"' EXIT
ROOT="${TMP}/repo"; mkdir -p "${ROOT}/.claude/ref"
printf 'router:\n  glm_policy:\n    protected_path_patterns:\n      - "secure/*"\n' > "${ROOT}/.claude/ref/leadv2-routing.yaml"

cat > "${TMP}/resolver.py" <<'PY'
#!/usr/bin/env python3
print("reviewer=sonnet")
print("pool=sonnet:ok:")
print("refusal=")
PY
chmod +x "${TMP}/resolver.py"

cat > "${TMP}/architect.sh" <<'SH'
#!/usr/bin/env bash
role=""
while [[ $# -gt 0 ]]; do
  case "$1" in --role) role="$2"; shift 2 ;; *) shift ;; esac
done
[[ "${role}" == hack-detect ]] && exit 0
case "${BODY_MODE}" in
  short_clean)
    # The measured 254-byte specimen: the visible fixture text plus three
    # trailing whitespace bytes. Its legacy clean verdict must normalize PASS.
    printf '%s\n' '[provider-quota-gate] OK — codex 30% < 98%' '# Codex Adversarial Review' 'Target: branch diff against HEAD' 'Verdict: approve' 'PASS — clean: the diff consistently corrects unset TMPDIR handling in test-only temporary-file creation.' 'No material findings.'
    printf '   '
    printf '[reviewer] model=sonnet\n' >&2
    ;;
  truncated)
    printf 'The reviewer read the diff but the response ended mid-sentence'
    printf 'cost recorded: reviewer/sonnet\n' >&2
    ;;
  empty)
    printf 'cost recorded: reviewer/sonnet\n' >&2
    ;;
  marker_only)
    printf 'REVIEW_VERDICT: PASS\n'
    printf 'cost recorded: reviewer/sonnet\n' >&2
    ;;
esac
SH
chmod +x "${TMP}/architect.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "${TMP}/dispatch.sh"; chmod +x "${TMP}/dispatch.sh"

run_case() { # <runner> <task> <body-mode>
  local runner="$1" task="$2" mode="$3" handoff
  handoff="${ROOT}/docs/handoff/${task}"
  mkdir -p "${handoff}"
  printf 'diff --git a/a b/a\n+x\n' > "${handoff}/review.diff"
  BODY_MODE="${mode}" LEADV2_BURN_GOVERNOR=0 \
    LEADV2_GLM_POLICY_RESOLVER="${TMP}/resolver.py" \
    LEADV2_DISPATCH_ARCHITECT_BIN="${TMP}/architect.sh" \
    LEADV2_DISPATCH_BIN="${TMP}/dispatch.sh" \
    LEADV2_JOURNAL_BIN=/bin/true \
    LEADV2_ROUTING_YAML="${ROOT}/.claude/ref/leadv2-routing.yaml" \
    LEADV2_DISPATCH_LANE_WRITES='app/review.sh' \
    bash "${runner}" --task "${task}" --root "${ROOT}" --handoff "${handoff}" \
      --diff "${handoff}/review.diff" --author glm > "${TMP}/${task}.out" 2> "${TMP}/${task}.err"
}

run_case "${ENGINE}" short-clean short_clean; rc=$?
if [[ "${rc}" -eq 0 ]] && grep -q '^status: pass$' "${ROOT}/docs/handoff/short-clean/review-gate.md"; then
  pass 'GREEN short 254-byte legacy clean PASS yields status: pass'
else
  fail "short clean fixture did not pass (rc=${rc})"
fi
show_gate short-clean "${ROOT}/docs/handoff/short-clean/review-gate.md"

run_case "${ENGINE}" truncated truncated; rc=$?
if [[ "${rc}" -eq 6 ]] && grep -q '^reason: review_body_lost$' "${ROOT}/docs/handoff/truncated/review-gate.md"; then
  pass 'GREEN truncated no-marker body yields review_body_lost'
else
  fail "truncated fixture did not block as body lost (rc=${rc})"
fi
show_gate truncated "${ROOT}/docs/handoff/truncated/review-gate.md"

run_case "${ENGINE}" empty empty; rc=$?
if [[ "${rc}" -eq 6 ]] && grep -q '^reason: review_body_lost$' "${ROOT}/docs/handoff/empty/review-gate.md"; then
  pass 'GREEN empty body yields review_body_lost'
else
  fail "empty fixture did not block as body lost (rc=${rc})"
fi
show_gate empty "${ROOT}/docs/handoff/empty/review-gate.md"

run_case "${ENGINE}" marker-only marker_only; rc=$?
if [[ "${rc}" -eq 6 ]] && grep -q '^reason: empty_response$' "${ROOT}/docs/handoff/marker-only/review-gate.md"; then
  pass 'GREEN verdict-marker-only body is complete but not a usable review'
else
  fail "marker-only fixture had the wrong terminal state (rc=${rc})"
fi
show_gate marker-only "${ROOT}/docs/handoff/marker-only/review-gate.md"

mutate_once() { # <target> <replacement>; exact anchor, never silent skip
  local target="$1" replacement="$2"
  python3 - "${target}" "${replacement}" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
old = 'if ! review_body_has_parseable_verdict "${_out}"; then'
new = sys.argv[2]
s = p.read_text()
n = s.count(old)
if n != 1:
    raise SystemExit(f"mutation anchor count={n}, expected=1")
p.write_text(s.replace(old, new, 1))
PY
}

ln -s "${SCRIPTS_ROOT}/lib" "${TMP}/lib"
MUTANT_THRESHOLD="${TMP}/leadv2-review-run-threshold-mutant.sh"
cp "${ENGINE}" "${MUTANT_THRESHOLD}"
mutate_once "${MUTANT_THRESHOLD}" 'if [[ "${_pc_body_bytes}" -lt "${_pc_body_min}" ]]; then' || { fail 'threshold mutation anchor'; exit 1; }
run_case "${MUTANT_THRESHOLD}" threshold-mutant short_clean; rc=$?
if [[ "${rc}" -eq 6 ]] && grep -q '^reason: review_body_lost$' "${ROOT}/docs/handoff/threshold-mutant/review-gate.md"; then
  pass 'RED control: restoring byte threshold blocks the short clean PASS'
else
  fail "threshold mutation survived (rc=${rc})"
fi
show_gate threshold-mutant "${ROOT}/docs/handoff/threshold-mutant/review-gate.md"

MUTANT_MISSING="${TMP}/leadv2-review-run-missing-marker-mutant.sh"
cp "${ENGINE}" "${MUTANT_MISSING}"
mutate_once "${MUTANT_MISSING}" 'if false; then' || { fail 'missing-marker mutation anchor'; exit 1; }
run_case "${MUTANT_MISSING}" missing-marker-mutant truncated; rc=$?
if [[ "${rc}" -eq 6 ]] && ! grep -q '^reason: review_body_lost$' "${ROOT}/docs/handoff/missing-marker-mutant/review-gate.md"; then
  pass 'RED control: removing missing-marker check wrongly admits truncated body'
else
  fail "missing-marker mutation did not go red (rc=${rc})"
fi
show_gate missing-marker-mutant "${ROOT}/docs/handoff/missing-marker-mutant/review-gate.md"

printf 'review-body-short-clean-pass: PASS=%s FAIL=%s\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
