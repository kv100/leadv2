#!/usr/bin/env bash
# test-worker-commit-epilogue.sh — offline tests for WORKERS-MUST-COMMIT-01:
# leadv2_worker_commit_epilogue() in lib/leadv2-worker-epilogue.sh, sourced
# by glm-coder.sh's finalize path right before the outcome classifier.
#
# No network, no real `claude` invocation. Every scenario builds a hermetic
# throwaway git repo and a fixture run_dir by hand. Never touches prod run
# dirs or the lane's own tree.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EPILOGUE_LIB="${SCRIPT_DIR}/../lib/leadv2-worker-epilogue.sh"
GLM_CODER="${SCRIPT_DIR}/../glm-coder.sh"
THIS_TEST="${SCRIPT_DIR}/test-worker-commit-epilogue.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

FAILURES=0
PASSES=0
pass() { printf 'PASS: %s\n' "$1"; PASSES=$((PASSES + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAILURES=$((FAILURES + 1)); }

# shellcheck disable=SC1090
source "${EPILOGUE_LIB}"

_new_repo() { # -> path, one commit on main, docs/ present
  local d
  d="$(mktemp -d "${TMP_ROOT}/repo-XXXXXX")"
  git -C "${d}" init -q -b main
  git -C "${d}" config user.email "test@example.com"
  git -C "${d}" config user.name "test"
  mkdir -p "${d}/docs" "${d}/plugins/leadv2/scripts"
  echo "one" > "${d}/plugins/leadv2/scripts/in-scope.sh"
  echo "one" > "${d}/outside.txt"
  git -C "${d}" add -A
  git -C "${d}" commit -q -m "init"
  echo "${d}"
}

_new_run_dir() { # <lane_writes_csv> -> path
  local d
  d="$(mktemp -d "${TMP_ROOT}/run-XXXXXX")"
  printf 'LANE_WRITES: %s\n' "$1" > "${d}/prompt.txt"
  printf 'run_id: %s\n' "$(basename "${d}")" > "${d}/meta.yaml"
  echo "${d}"
}

# ---------------------------------------------------------------------------
# case_bash_n — syntax-clean on the epilogue lib and both call sites.
# ---------------------------------------------------------------------------
if bash -n "${EPILOGUE_LIB}" && bash -n "${GLM_CODER}" && bash -n "${THIS_TEST}"; then
  pass "case_bash_n"
else
  fail "case_bash_n" "bash -n reported a syntax error"
fi

# ---------------------------------------------------------------------------
# case_a — dirty, in-scope exit -> auto-commit exists, HEAD moves, tree
#          becomes clean, outcome work=yes via the existing git-ahead path.
# ---------------------------------------------------------------------------
repo="$(_new_repo)"
run_dir="$(_new_run_dir "plugins/leadv2/scripts")"
echo "meta.yaml" >> "${run_dir}/meta.yaml"
printf 'cwd: %s\n' "${repo}" >> "${run_dir}/meta.yaml"
head_before="$(git -C "${repo}" rev-parse HEAD)"
echo "changed" >> "${repo}/plugins/leadv2/scripts/in-scope.sh"
leadv2_worker_commit_epilogue "${run_dir}" "${repo}" "case_a" >/dev/null
head_after="$(git -C "${repo}" rev-parse HEAD)"
dirty_after="$(git -C "${repo}" status --porcelain)"
if [[ "${head_after}" == "${head_before}" ]]; then
  fail "case_a_in_scope_auto_commit" "HEAD did not move -- no commit happened"
elif [[ -n "${dirty_after}" ]]; then
  fail "case_a_in_scope_auto_commit" "tree still dirty after epilogue: ${dirty_after}"
elif ! grep -q "^worker_exit=dirty auto_committed=1" "${run_dir}/progress.log" 2>/dev/null; then
  fail "case_a_in_scope_auto_commit" "progress.log missing worker_exit=dirty auto_committed=1"
elif ! grep -q "^auto_committed: 1$" "${run_dir}/meta.yaml" 2>/dev/null; then
  fail "case_a_in_scope_auto_commit" "meta.yaml missing auto_committed: 1"
else
  pass "case_a_in_scope_auto_commit"
fi

# ---------------------------------------------------------------------------
# case_b — dirty, out-of-scope-only exit -> no commit, foreign_dirty listed,
#          tree stays dirty (nothing outside LANE_WRITES is ever touched).
# ---------------------------------------------------------------------------
repo="$(_new_repo)"
run_dir="$(_new_run_dir "plugins/leadv2/scripts")"
printf 'cwd: %s\n' "${repo}" >> "${run_dir}/meta.yaml"
head_before="$(git -C "${repo}" rev-parse HEAD)"
echo "changed" >> "${repo}/outside.txt"
leadv2_worker_commit_epilogue "${run_dir}" "${repo}" "case_b" >/dev/null
head_after="$(git -C "${repo}" rev-parse HEAD)"
dirty_after="$(git -C "${repo}" status --porcelain)"
if [[ "${head_after}" != "${head_before}" ]]; then
  fail "case_b_out_of_scope_no_commit" "HEAD moved -- a foreign file was committed"
elif [[ -z "${dirty_after}" ]]; then
  fail "case_b_out_of_scope_no_commit" "tree unexpectedly clean -- foreign file vanished"
elif ! grep -q "^worker_exit=dirty auto_committed=0 foreign_dirty=1" "${run_dir}/progress.log" 2>/dev/null; then
  fail "case_b_out_of_scope_no_commit" "progress.log missing auto_committed=0 foreign_dirty=1"
elif ! grep -q "^foreign_dirty=outside.txt$" "${run_dir}/progress.log" 2>/dev/null; then
  fail "case_b_out_of_scope_no_commit" "progress.log missing foreign_dirty=outside.txt"
else
  pass "case_b_out_of_scope_no_commit"
fi

# ---------------------------------------------------------------------------
# case_c — clean, already-committed exit -> untouched, worker_exit=clean.
# ---------------------------------------------------------------------------
repo="$(_new_repo)"
run_dir="$(_new_run_dir "plugins/leadv2/scripts")"
printf 'cwd: %s\n' "${repo}" >> "${run_dir}/meta.yaml"
head_before="$(git -C "${repo}" rev-parse HEAD)"
leadv2_worker_commit_epilogue "${run_dir}" "${repo}" "case_c" >/dev/null
head_after="$(git -C "${repo}" rev-parse HEAD)"
if [[ "${head_after}" != "${head_before}" ]]; then
  fail "case_c_clean_exit_untouched" "HEAD moved on an already-clean tree"
elif ! grep -q "^worker_exit=clean auto_committed=0 foreign_dirty=0$" "${run_dir}/progress.log" 2>/dev/null; then
  fail "case_c_clean_exit_untouched" "progress.log missing worker_exit=clean line"
else
  pass "case_c_clean_exit_untouched"
fi

# ---------------------------------------------------------------------------
# case_d — dirty exit, no LANE_WRITES declared -> never guesses scope, no
#          commit, undeclared_lane_writes reported.
# ---------------------------------------------------------------------------
repo="$(_new_repo)"
run_dir="$(mktemp -d "${TMP_ROOT}/run-XXXXXX")"
printf 'run_id: %s\ncwd: %s\n' "$(basename "${run_dir}")" "${repo}" > "${run_dir}/meta.yaml"
: > "${run_dir}/prompt.txt"
head_before="$(git -C "${repo}" rev-parse HEAD)"
echo "changed" >> "${repo}/plugins/leadv2/scripts/in-scope.sh"
leadv2_worker_commit_epilogue "${run_dir}" "${repo}" "case_d" >/dev/null
head_after="$(git -C "${repo}" rev-parse HEAD)"
if [[ "${head_after}" != "${head_before}" ]]; then
  fail "case_d_undeclared_lane_writes_no_guess" "HEAD moved with no LANE_WRITES declared"
elif ! grep -q "foreign_dirty=undeclared_lane_writes" "${run_dir}/progress.log" 2>/dev/null; then
  fail "case_d_undeclared_lane_writes_no_guess" "progress.log missing undeclared_lane_writes marker"
else
  pass "case_d_undeclared_lane_writes_no_guess"
fi

printf '\ntest-worker-commit-epilogue: %d passed, %d failed\n' "${PASSES}" "${FAILURES}"
(( FAILURES == 0 ))
