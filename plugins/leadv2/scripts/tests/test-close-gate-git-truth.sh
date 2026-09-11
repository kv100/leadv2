#!/usr/bin/env bash
# changed-scope triggers, self-registered (W18-CLOSER-THROUGHPUT):
# run-all-triggers: leadv2-dispatch-product-close
# CLOSER-MUST-LAND-FROM-GIT-TRUTH-NOT-A-REPORT-FILE-01.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "${HERE}/.." && pwd)"
PC="${LEADV2_PC_SCRIPT:-${SCRIPTS}/leadv2-dispatch-product-close.sh}"
PASS=0 FAIL=0
pass() { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/close-git-truth.XXXXXX")"; trap 'rm -rf "${TMP}"' EXIT
ROOT="${TMP}/root"; LANE="${TMP}/lane"; JOURNAL="${TMP}/journal.log"
git init -q -b main "${ROOT}"
git -C "${ROOT}" config user.email test@example.invalid
git -C "${ROOT}" config user.name test
printf 'seed\n' > "${ROOT}/declared.txt"
git -C "${ROOT}" add declared.txt && git -C "${ROOT}" commit -qm seed
git -C "${ROOT}" worktree add -q -b worktree-gittruth "${LANE}" main
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %q\n' "${JOURNAL}" > "${TMP}/journal.sh"
chmod +x "${TMP}/journal.sh"

run_close() { # <task> <lane-root>
  local task="$1" lane_root="$2"
  LEADV2_BUILDER_SELFCHECK=0 LEADV2_ARM_ADVANCE=0 LEADV2_DISPATCH_TERMINAL_LEDGER=0 \
  LEADV2_JOURNAL_BIN="${TMP}/journal.sh" LEADV2_LANE_WORK_ROOT="${lane_root}" \
  LEADV2_DISPATCH_LANE_WRITES="declared.txt" \
    bash "${PC}" "${ROOT}" "${task}" glm '' 0 0 '' >"${TMP}/${task}.out" 2>&1
}

# Commit is deliberately outside the declared write set and there is no report:
# a report-file heuristic would call this empty; git truth must preserve it.
printf 'real commit\n' > "${LANE}/actual.txt"
git -C "${LANE}" add actual.txt && git -C "${LANE}" commit -qm real-work
SHA="$(git -C "${LANE}" rev-parse HEAD)"
run_close gittruthc "${LANE}" || rc=$?
rc="${rc:-0}"
MD="${ROOT}/docs/handoff/dispatch-gittruthc/review-gate.md"
if [[ "${rc}" == 5 && -f "${MD}" ]] && grep -q '^reason: git_truth_commits$' "${MD}" \
   && grep -q "commits=.*${SHA}" "${MD}" && grep -q "${SHA}" "${JOURNAL}"; then
  pass 'committed branch without report is git_truth_commits and journals its SHA'
else
  fail "committed branch was misclassified (rc=${rc}, out=$(cat "${TMP}/gittruthc.out"), md=$(cat "${MD}" 2>/dev/null), journal=$(cat "${JOURNAL}" 2>/dev/null))"
fi

# The index is not visible to git log.  It must also block no_work.
git -C "${LANE}" reset --hard main >/dev/null
mkdir -p "${LANE}/docs/handoff"
printf 'staged only\n' > "${LANE}/docs/handoff/ignored.md"
git -C "${LANE}" add docs/handoff/ignored.md
unset rc; run_close gittruths "${LANE}" || rc=$?; rc="${rc:-0}"
MD="${ROOT}/docs/handoff/dispatch-gittruths/review-gate.md"
if [[ "${rc}" == 5 ]] && grep -q '^reason: git_truth_staged$' "${MD}"; then
  pass 'staged but uncommitted work is git_truth_staged, not no_work'
else
  fail "staged work was misclassified (rc=${rc}, md=$(cat "${MD}" 2>/dev/null))"
fi

# Paired control: no lane branch/worktree exists and root has no uncommitted work.
unset rc; run_close gittruthn "${TMP}/missing-lane" || rc=$?; rc="${rc:-0}"
MD="${ROOT}/docs/handoff/dispatch-gittruthn/review-gate.md"
if [[ "${rc}" == 5 ]] && grep -q '^reason: no_work$' "${MD}"; then
  pass 'missing branch with no index/commits remains no_work'
else
  fail "missing branch did not remain no_work (rc=${rc}, md=$(cat "${MD}" 2>/dev/null))"
fi

printf '[TEST] %d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == 0 ]]
