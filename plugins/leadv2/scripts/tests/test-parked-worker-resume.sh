#!/usr/bin/env bash
# WORKER-PARKED-ON-BG-01: red-first contract/classifier/resume coverage.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "${SCRIPT_DIR}" && git rev-parse --show-toplevel)"
PASS=0; FAIL=0
ok() { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }
assert_eq() { [[ "$1" == "$2" ]] && ok "$3" || bad "$3 (got=$1 want=$2)"; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-parked.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT INT TERM
SKIP=0

# RED-FIRST-SELF-INVALIDATES-01: `HEAD^` is a floating ref -- it was pre-fix
# only at authoring time, and stops meaning that the moment this fix's own
# merge commit becomes HEAD^ (which it now is: b680643). Pin the baseline to
# the parent of the commit that introduced the marker instead.
source "${SCRIPT_DIR}/lib/leadv2-red-first-baseline.sh"
LEADV2_REPO="${REPO}"
BASE="$(lv2_rf_baseline_ref '_LEADV2_FOREGROUND_CONTRACT_MISSION' plugins/leadv2/scripts/leadv2-helpers.sh '6fa4823')"; rf_rc=$?
mkdir -p "${TMP}/prefix"
PREFIX="${TMP}/prefix/plugins/leadv2/scripts"
if [[ ${rf_rc} -eq 0 ]]; then
  lv2_rf_extract "${BASE}" "${TMP}/prefix" plugins/leadv2/scripts >/dev/null 2>&1 || rf_rc=3
fi

# 1. All four arms receive the fixed prefix at the one post-signature site;
# pre-fix archive is deliberately red.
contract_case() { # <scripts>
  local s="$1" body
  [[ -f "${s}/leadv2-helpers.sh" && -f "${s}/leadv2-dispatch-code.sh" ]] || return 2
  body="$(awk '/^_spawn_worker_body\(\) \{/{p=1} p{print} p && /^}/{exit}' "${s}/leadv2-dispatch-code.sh")"
  grep -q '_LEADV2_FOREGROUND_CONTRACT_MISSION' "${s}/leadv2-helpers.sh" \
    && grep -q '_LEADV2_FOREGROUND_CONTRACT_MISSION' <<<"${body}" \
    && grep -q 'glm|glm-flash)' <<<"${body}" && grep -q 'kimi)' <<<"${body}" \
    && grep -q 'sonnet)' <<<"${body}" && grep -q 'codex)' <<<"${body}" \
    && [[ "$(grep -n '_LEADV2_FOREGROUND_CONTRACT_MISSION' <<<"${body}" | head -1 | cut -d: -f1)" -lt "$(grep -n '_LEADV2_EVIDENCE_CONTRACT_MISSION' <<<"${body}" | head -1 | cut -d: -f1)" ]]
}
contract_case "${SCRIPT_DIR}" >/dev/null 2>&1; post=$?
if [[ ${post} -ne 0 ]]; then
  bad "contract red-first (post=${post})"
elif [[ ${rf_rc} -ne 0 ]]; then
  printf '[TEST] SKIP: red-first baseline unresolvable — contract red-first\n'
  SKIP=$((SKIP + 1))
else
  contract_case "${PREFIX}" >/dev/null 2>&1; pre=$?
  [[ ${pre} -ne 0 ]] && ok "red-first foreground contract reaches glm/kimi/sonnet/codex without changing spawn identity site" || bad "contract red-first (pre=$pre post=$post)"
fi

# 2. Classifier: clean parked result plus declared-unsatisfied deliverable -> parked.
run="${TMP}/run"; mkdir -p "${run}"
printf 'standing by for the background test result — no further action until it completes.\n' > "${run}/result.md"
printf 'docs/handoff/report.md\n' > "${run}/.deliverable"; : > "${run}/.no-deliverable"
out="$(bash "${SCRIPT_DIR}/leadv2-lane-outcome.sh" "${run}" 0 no)"
assert_eq "${out}" "parked" "clean waiting result with unsatisfied deliverable classifies parked"
grep -q '^next=continue$' "${run}/.outcome" && ok "parked outcome carries continue next" || bad "parked outcome missing continue next"
stream="${TMP}/developer.stream.jsonl"
printf '%s\n' '{"type":"result","subtype":"success","result":"Standing by for the background test result — no further action until it completes."}' > "${stream}"
# The same reader is used by product-close for arms that have no outcome file.
source "${SCRIPT_DIR}/lib/leadv2-parked-detect.sh"
if lv2_parked_text_file "${stream}"; then ok "clean success stream replay is parked-shaped"; else bad "clean success stream replay was not detected"; fi

# 3. Negative control: a satisfying deliverable never becomes parked.
run2="${TMP}/run2"; mkdir -p "${run2}"
printf 'standing by for the background test result\n' > "${run2}/result.md"; : > "${run2}/.deliverable"
out2="$(bash "${SCRIPT_DIR}/leadv2-lane-outcome.sh" "${run2}" 0 no)"
assert_eq "${out2}" "completed" "clean success with deliverable does not resume"

# 4/5. Load only the resume helpers, then prove parked launches once and the
# marker blocks a second parked exit. This avoids unrelated close-gate effects.
helpers="${TMP}/resume-helpers.sh"
for fn in _pc_meta_value _pc_run_dir_for _pc_lane_outcome _pc_resume_launcher_for _pc_resolve_asked_into_void pc_dwr_resume_once; do
  awk -v n="${fn}" '$0 ~ "^" n "\\(\\)" {p=1} p{print} p && /^}/{exit}' "${SCRIPT_DIR}/leadv2-dispatch-product-close.sh" >> "${helpers}"
done
source "${helpers}"
emit() { printf '%s\n' "$*" >> "${TMP}/journal"; }
root="${TMP}/repo"; mkdir -p "${root}"; runs="${TMP}/glm-runs"; handle="260823-010101-parked01"; old="${runs}/${handle}"; mkdir -p "${old}" "${TMP}/handoff"
printf 'cwd: %s\nmax_turns: 50\ntimeout: 60\noutcome: parked\n' "${root}" > "${old}/meta.yaml"
printf 'continue the declared deliverable\n' > "${old}/prompt.txt"
launcher="${TMP}/launcher.sh"
printf '#!/usr/bin/env bash\nprintf "260823-010102-resume01\\n"\n' > "${launcher}"; chmod +x "${launcher}"
AUTHOR=glm; HANDLE="${handle}"; HANDOFF="${TMP}/handoff"; TASK=parked001
GLM_RUNS_DIR="${runs}"; LEADV2_PC_RESUME_LAUNCHER_BIN="${launcher}"; LEADV2_PC_DWR_RESUME=1
pc_dwr_resume_once; rc=$?
assert_eq "${rc}" "0" "parked lane launches exactly one resume"
HANDLE="${handle}"; pc_dwr_resume_once; rc2=$?
assert_eq "${rc2}" "1" "second parked exit does not loop"
grep -q 'reason=already_attempted' "${TMP}/journal" && ok "second parked exit journals already_attempted" || bad "missing already_attempted journal"

# Existing DWR suite is the positive control for died-with-work semantics.
if bash "${SCRIPT_DIR}/tests/test-dwr-resume.sh" >/dev/null 2>&1; then ok "positive control died-with-work resume remains green"; else bad "positive control died-with-work resume"; fi

printf '[TEST] RESULT: pass=%s fail=%s skip=%s\n' "${PASS}" "${FAIL}" "${SKIP}"
[[ ${FAIL} -eq 0 ]]
