#!/usr/bin/env bash
# THE-REVIEWER-NEVER-READS-THE-SPEC-01: review verdict dimensions are real only
# if a correct-but-wrong-task diff and a broken diff produce distinguishable gates.
# run-all-triggers: leadv2-review-run

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="${SCRIPT_DIR}/../leadv2-review-run.sh"
PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

bash -n "${ENGINE}" || exit 1
bash -n "${SCRIPT_DIR}/test-review-mission-alignment.sh" || exit 1
TMP="$(mktemp -d /private/tmp/review-mission-alignment.XXXXXX)"; trap 'rm -rf "${TMP}"' EXIT
ROOT="${TMP}/repo"
mkdir -p "${ROOT}/.claude/ref"

cat > "${TMP}/resolver.py" <<'PY'
#!/usr/bin/env python3
print("reviewer=sonnet")
print("pool=sonnet:ok:")
print("refusal=")
PY
chmod +x "${TMP}/resolver.py"

cat > "${TMP}/critic.sh" <<'SH'
#!/usr/bin/env bash
mission=""
role=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mission-file) mission="$2"; shift 2 ;;
    --role) role="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ "${role}" == hack-detect ]] && exit 0
[[ "$(head -n 1 "${mission}")" == 'Run hack-detection on the diff at '* ]] && exit 0
cp "$mission" "${MISSION_CAPTURE}"
case "${FIXTURE_CASE}" in
  aligned)
    printf 'REVIEW_CODE_VERDICT: PASS\nREVIEW_MISSION_VERDICT: PASS\nREVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\nThe implementation is correct and realizes the requested widget.\n'
    ;;
  wrong_task)
    printf 'REVIEW_CODE_VERDICT: PASS\nREVIEW_MISSION_VERDICT: FAIL\nREVIEW_VERDICT: FAIL\nREVIEW_FINDINGS: critical=0 high=1 medium=0 low=0\nFINDING: severity=High file=docs/handoff/spec-wrong_task.md line=1 dimension=mission_alignment desc=requested widget is absent despite otherwise sound code\n'
    ;;
  broken)
    printf 'REVIEW_CODE_VERDICT: FAIL\nREVIEW_MISSION_VERDICT: PASS\nREVIEW_VERDICT: FAIL\nREVIEW_FINDINGS: critical=0 high=1 medium=0 low=0\nFINDING: severity=High file=widget.sh line=7 dimension=correctness desc=implementation is broken\n'
    ;;
esac
SH
chmod +x "${TMP}/critic.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "${TMP}/dispatch.sh"
chmod +x "${TMP}/dispatch.sh"

run_case() { # <tag> <expected-rc> <code verdict> <mission verdict>
  local tag="$1" expected_rc="$2" expected_code="$3" expected_mission="$4"
  local handoff="${ROOT}/docs/handoff/dispatch-${tag}"
  local diff="${handoff}/review.diff"
  local mission="${ROOT}/docs/handoff/spec-${tag}.md"
  mkdir -p "${handoff}"
  printf 'diff --git a/widget.sh b/widget.sh\n+widget\n' > "${diff}"
  printf '# Requested widget\nImplement the requested widget, not a different feature.\n' > "${mission}"
  FIXTURE_CASE="${tag}" MISSION_CAPTURE="${TMP}/captured-${tag}.md" \
    LEADV2_GLM_POLICY_RESOLVER="${TMP}/resolver.py" \
    LEADV2_DISPATCH_ARCHITECT_BIN="${TMP}/critic.sh" \
    LEADV2_DISPATCH_BIN="${TMP}/dispatch.sh" \
    bash "${ENGINE}" --task "${tag}" --root "${ROOT}" --handoff "${handoff}" \
      --diff "${diff}" --author glm --mission-file "${mission}" >/dev/null 2>&1
  local rc=$?
  printf '# Changed after review began\nThis must not replace the reviewed source.\n' > "${mission}"
  if [[ "${rc}" -eq "${expected_rc}" ]] \
      && grep -qx "correctness_verdict: ${expected_code}" "${handoff}/review-gate.md" \
      && grep -qx "mission_verdict: ${expected_mission}" "${handoff}/review-gate.md"; then
    pass "${tag} has independent code=${expected_code} mission=${expected_mission} verdicts"
  else
    fail "${tag} rc=${rc} expected=${expected_rc} gate=$(tr '\n' ' ' < "${handoff}/review-gate.md")"
  fi
  if grep -q 'Implement the requested widget' "${TMP}/captured-${tag}.md" \
      && grep -q 'Implement the requested widget' "${handoff}/review-mission-source.md" \
      && ! grep -q 'Changed after review began' "${handoff}/review-mission-source.md" \
      && grep -Eq '^mission_sha256: [0-9a-f]{64}$' "${handoff}/review-gate.md" \
      && grep -q '^review_input_bytes: [1-9][0-9]*$' "${handoff}/review-gate.md"; then
    pass "${tag} receives and records the immutable mission snapshot with measured input bytes"
  else
    fail "${tag} snapshot or input measurement missing"
  fi
}

run_case aligned 0 PASS PASS
# Mandatory negative control: both cases fail the overall gate, but only this
# one is a correct implementation of the wrong task.
run_case wrong_task 7 PASS FAIL
run_case broken 7 FAIL PASS

printf 'review-mission-alignment: PASS=%s FAIL=%s\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
