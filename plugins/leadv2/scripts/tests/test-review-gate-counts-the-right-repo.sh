#!/usr/bin/env bash
# run-all-triggers: leadv2-dispatch-product-close
# PREPASS-MECHANISM-CLOSURE-01: three real fixture cases for path-to-repo truth.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PC="${LEADV2_PC_SCRIPT:-${HERE}/../leadv2-dispatch-product-close.sh}"
PASS=0 FAIL=0
pass() { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/right-repo.XXXXXX")"
trap '[[ "${LEADV2_PC_TEST_KEEP_TMP:-0}" == 1 ]] || rm -rf "${TMP}"' EXIT
ROOT="${TMP}/persona"
CANONICAL="${TMP}/leadv2"
SIBLING_WT_DIR="${TMP}/sibling-worktrees"
JOURNAL="${TMP}/journal.log"
printf '%s\n' '# intentionally empty active-registry fixture' > "${TMP}/missing-active.sh"

init_repo() {
  local repo="$1"
  git init -q -b main "${repo}"
  git -C "${repo}" config user.email test@example.invalid
  git -C "${repo}" config user.name test
}

init_repo "${ROOT}"
printf 'seed\n' > "${ROOT}/seed.txt"
mkdir -p "${ROOT}/docs"
printf 'declared\n' > "${ROOT}/docs/declared.txt"
git -C "${ROOT}" add . && git -C "${ROOT}" commit -qm seed

init_repo "${CANONICAL}"
mkdir -p "${CANONICAL}/plugins/leadv2/scripts"
printf 'seed\n' > "${CANONICAL}/plugins/leadv2/scripts/probe.sh"
git -C "${CANONICAL}" add . && git -C "${CANONICAL}" commit -qm seed
mkdir -p "${SIBLING_WT_DIR}"
git -C "${CANONICAL}" worktree add -q -b worktree-case-plugin "${SIBLING_WT_DIR}/case-plugin" main
printf 'plugin work\n' >> "${SIBLING_WT_DIR}/case-plugin/plugins/leadv2/scripts/probe.sh"
git -C "${SIBLING_WT_DIR}/case-plugin" add . && git -C "${SIBLING_WT_DIR}/case-plugin" commit -qm plugin-work

git -C "${ROOT}" worktree add -q -b worktree-case-project "${TMP}/project-lane" main
printf 'project work\n' >> "${TMP}/project-lane/docs/declared.txt"
git -C "${TMP}/project-lane" add . && git -C "${TMP}/project-lane" commit -qm project-work
git -C "${ROOT}" worktree add -q -b worktree-case-negative "${TMP}/negative-lane" main

printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %q\n' "${JOURNAL}" > "${TMP}/journal.sh"
chmod +x "${TMP}/journal.sh"

run_close() {
  local task="$1" lane="$2" writes="$3"
  LEADV2_BUILDER_SELFCHECK=0 LEADV2_ARM_ADVANCE=0 LEADV2_DISPATCH_TERMINAL_LEDGER=0 \
  LEADV2_JOURNAL_BIN="${TMP}/journal.sh" LEADV2_DISPATCH_CACHE_DIR="${TMP}/cache" LEADV2_ACTIVE_REGISTRY_SH="${TMP}/missing-active.sh" LEADV2_LANE_WORK_ROOT="${lane}" \
  LEADV2_WORKTREE_DIR="${SIBLING_WT_DIR}" LEADV2_CANONICAL_ROOT="${CANONICAL}" \
  LEADV2_DISPATCH_LANE_WRITES="${writes}" \
    bash "${PC}" "${ROOT}" "${task}" glm '' 0 0 "${task}" >"${TMP}/${task}.out" 2>&1
}

unset rc
run_close case-plugin "${ROOT}" plugins/leadv2/scripts/probe.sh || rc=$?
rc="${rc:-0}"
if [[ "${rc}" == 0 ]] && grep -q "root=${SIBLING_WT_DIR}/case-plugin" "${JOURNAL}"; then
  pass 'plugin write is diffed from the sibling lane and names its root'
else
  fail "plugin lane did not pass (rc=${rc}, output=$(cat "${TMP}/case-plugin.out"), journal=$(cat "${JOURNAL}" 2>/dev/null))"
fi

unset rc
run_close case-project "${TMP}/project-lane" docs/declared.txt || rc=$?
rc="${rc:-0}"
if [[ "${rc}" == 0 ]] && grep -q "root=${TMP}/project-lane" "${JOURNAL}"; then
  pass 'dispatching-repo write is diffed from the persona lane'
else
  fail "project lane did not pass (rc=${rc}, output=$(cat "${TMP}/case-project.out"), journal=$(cat "${JOURNAL}" 2>/dev/null))"
fi

# A local diff must not make an unresolved/shared declared path disappear from
# review. The shared canonical file is deliberately dirty here; the close gate
# must refuse partial_diff instead of reviewing only the persona bytes.
printf 'canonical work\n' >> "${CANONICAL}/plugins/leadv2/scripts/probe.sh"
unset rc
run_close case-mixed "${TMP}/project-lane" docs/declared.txt,plugins/leadv2/scripts/probe.sh || rc=$?
rc="${rc:-0}"
MD="${ROOT}/docs/handoff/dispatch-case-mixed/review-gate.md"
if [[ "${rc}" == 5 ]] && grep -q '^reason: partial_diff$' "${MD}"; then
  pass 'local bytes plus shared-canonical bytes refuse partial_diff'
else
  fail "mixed local/shared writes escaped review (rc=${rc}, output=$(cat "${TMP}/case-mixed.out"), md=$(cat "${MD}" 2>/dev/null))"
fi

# A branch on the dispatching ROOT is not this lane's branch. Its unrelated
# commit must remain visible in the survey but cannot become git_truth_commits.
git -C "${ROOT}" checkout -qb foreign-feature
printf 'foreign\n' > "${ROOT}/foreign.txt"
git -C "${ROOT}" add foreign.txt && git -C "${ROOT}" commit -qm foreign-work
unset rc
run_close case-foreign "${ROOT}" docs/declared.txt || rc=$?
rc="${rc:-0}"
MD="${ROOT}/docs/handoff/dispatch-case-foreign/review-gate.md"
if [[ "${rc}" == 5 ]] && grep -q '^reason: no_work$' "${MD}" \
   && grep -q 'branch=foreign-feature commits=1' "${MD}" \
   && ! grep -q '^reason: git_truth_commits$' "${MD}"; then
  pass 'foreign ROOT branch is surveyed but cannot become lane git truth'
else
  fail "foreign ROOT commit was credited to the lane (rc=${rc}, output=$(cat "${TMP}/case-foreign.out"), md=$(cat "${MD}" 2>/dev/null))"
fi

unset rc
run_close case-negative "${TMP}/negative-lane" plugins/leadv2/scripts/probe.sh || rc=$?
rc="${rc:-0}"
MD="${ROOT}/docs/handoff/dispatch-case-negative/review-gate.md"
if [[ "${rc}" == 5 ]] && grep -q '^reason: cross_repo_elsewhere$' "${MD}" \
   && grep -q '^dirty: 0$' "${MD}" \
   && grep -q "repo=${CANONICAL}" "${JOURNAL}"; then
  pass 'negative control refuses shared-canonical-only resolution and surveys both repos'
else
  fail "negative control was relaxed (rc=${rc}, output=$(cat "${TMP}/case-negative.out"), md=$(cat "${MD}" 2>/dev/null), journal=$(cat "${JOURNAL}" 2>/dev/null))"
fi

printf '[TEST] %d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == 0 ]]
