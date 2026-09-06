#!/usr/bin/env bash
# tests/test-leadv2-journal.sh — LIVE-LANES-RUN-WITHOUT-A-JOURNAL-01
#
# leadv2-journal.sh (the writer) used to compute its journal path from
# `git rev-parse --show-toplevel`, which returns the WORKTREE from inside a
# linked worktree. A reader rooted at the main checkout (or a different
# worktree of the same repo) resolved a different, fixed root and never saw
# the journal a worker wrote from its own worktree -- "run without a
# journal" even though the worker journaled correctly by its own rule.
#
# Fixed by routing the writer through leadv2-state-path.sh's canonical
# control-plane root (`git rev-parse --git-common-dir`, identical from every
# worktree of one repo) and exposing a `path <task-id>` subcommand so every
# external reader (persona-engine's scripts/anti-silence-pulse.sh, via the
# symlinked copy of this same script) computes the SAME address by calling
# the SAME resolver, instead of separately guessing candidate paths.
#
# Hermetic: LEADV2_STATE_BASE points at a throwaway dir, bypassing both the
# real ~/.claude/leadv2-state and the ephemeral-redirect (which only fires
# when LEADV2_STATE_BASE is unset).
# run-all-triggers: leadv2-journal leadv2-state-path

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOURNAL_SH="${SCRIPT_DIR}/../leadv2-journal.sh"
FAIL=0

bash -n "${JOURNAL_SH}" || { echo "ERROR: bash -n failed for ${JOURNAL_SH}"; exit 1; }

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAIL=1; }

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

MAIN_REPO="${TMP_ROOT}/main-repo"
WT_DIR="${TMP_ROOT}/linked-worktree"
STATE_BASE="${TMP_ROOT}/state-base"
mkdir -p "${MAIN_REPO}" "${STATE_BASE}"

git -C "${MAIN_REPO}" init -q
git -C "${MAIN_REPO}" config user.email test@test.test
git -C "${MAIN_REPO}" config user.name Test
touch "${MAIN_REPO}/.gitkeep"
git -C "${MAIN_REPO}" add -A
git -C "${MAIN_REPO}" commit -qm init
git -C "${MAIN_REPO}" worktree add -q -b test-journal-lane-branch "${WT_DIR}" >/dev/null 2>&1 \
  || { echo "ERROR: git worktree add failed"; exit 1; }

export LEADV2_STATE_BASE="${STATE_BASE}"
unset LEADV2_STATE_ROOT

# ── Test 1: basic append/tail sanity ────────────────────────────────────────
TID1="basic-sanity-task"
CLAUDE_PROJECT_ROOT="${MAIN_REPO}" bash "${JOURNAL_SH}" append "${TID1}" phase "started phase one" >/dev/null 2>&1
out="$(CLAUDE_PROJECT_ROOT="${MAIN_REPO}" bash "${JOURNAL_SH}" tail "${TID1}" 5 2>/dev/null)"
if [[ "${out}" == *"started phase one"* ]]; then
  pass "basic append/tail: appended entry is readable back via tail"
else
  fail "basic append/tail" "tail output did not contain the appended entry: '${out}'"
fi

# ── Test 2: worktree-vs-checkout path identity (the actual bug) ────────────
TID2="worktree-proof-task"
path_from_main="$(CLAUDE_PROJECT_ROOT="${MAIN_REPO}" bash "${JOURNAL_SH}" path "${TID2}" 2>/dev/null)"
path_from_wt="$(CLAUDE_PROJECT_ROOT="${WT_DIR}" bash "${JOURNAL_SH}" path "${TID2}" 2>/dev/null)"
if [[ -z "${path_from_main}" || -z "${path_from_wt}" ]]; then
  fail "worktree path identity" "main='${path_from_main}' worktree='${path_from_wt}' (empty)"
elif [[ "${path_from_main}" != "${path_from_wt}" ]]; then
  fail "worktree path identity" "main='${path_from_main}' worktree='${path_from_wt}' -- DIVERGED, this is the LIVE-LANES-RUN-WITHOUT-A-JOURNAL-01 defect"
elif [[ "${path_from_main}" == "${MAIN_REPO}"* || "${path_from_main}" == "${WT_DIR}"* ]]; then
  fail "worktree path identity" "resolved INSIDE a worktree/checkout: ${path_from_main} (should be under the shared state root)"
else
  pass "worktree path identity: main checkout and linked worktree resolve the SAME journal path (${path_from_main})"
fi

# Prove it end-to-end, not just path-string equality: append from the
# WORKTREE, read via tail rooted at the MAIN checkout.
CLAUDE_PROJECT_ROOT="${WT_DIR}" bash "${JOURNAL_SH}" append "${TID2}" note "written from the worktree" >/dev/null 2>&1
cross_read="$(CLAUDE_PROJECT_ROOT="${MAIN_REPO}" bash "${JOURNAL_SH}" tail "${TID2}" 5 2>/dev/null)"
if [[ "${cross_read}" == *"written from the worktree"* ]]; then
  pass "cross-worktree read: entry written from the worktree is visible from the main checkout"
else
  fail "cross-worktree read" "main-checkout tail did not see the worktree-written entry: '${cross_read}'"
fi

# ── Test 3: negative control -- a lane with no journal still reports absent ─
TID3="never-journaled-task"
absent_out="$(CLAUDE_PROJECT_ROOT="${MAIN_REPO}" bash "${JOURNAL_SH}" tail "${TID3}" 5 2>/dev/null)"
absent_rc=0
CLAUDE_PROJECT_ROOT="${MAIN_REPO}" bash "${JOURNAL_SH}" tail "${TID3}" 5 >/dev/null 2>&1 || absent_rc=$?
if [[ -z "${absent_out}" && ${absent_rc} -eq 0 ]]; then
  pass "negative control: a task-id that never journaled reports empty (not a fabricated entry), rc=0"
else
  fail "negative control" "expected empty output + rc=0, got out='${absent_out}' rc=${absent_rc}"
fi

# ── Test 4: mutation control on the resolver body (RED-then-GREEN) ─────────
# Mutant: unconditionally clear TASK_DIR right after the resolver block, so
# the script always falls through to the pre-fix per-checkout fallback --
# exactly the bug this task fixes, reproduced as a one-line mutation of the
# real script rather than a hand-written duplicate.
MUTANT_SH="${TMP_ROOT}/leadv2-journal.mutant.sh"
cp "${JOURNAL_SH}" "${MUTANT_SH}"
sed -i.bak 's/^JOURNAL_FILE="\${TASK_DIR}\/journal.md"$/TASK_DIR="${PROJECT_ROOT}\/${_lv2_leadv2_dir}\/tasks\/${TASK_ID}"\nJOURNAL_FILE="${TASK_DIR}\/journal.md"/' "${MUTANT_SH}"
rm -f "${MUTANT_SH}.bak"
chmod +x "${MUTANT_SH}"
if ! grep -q 'TASK_DIR="${PROJECT_ROOT}/${_lv2_leadv2_dir}/tasks/${TASK_ID}"$' "${MUTANT_SH}"; then
  echo "ERROR: mutation-control sed pattern did not match ${JOURNAL_SH} (source drifted -- update this test)"; exit 1
fi
if cmp -s "${JOURNAL_SH}" "${MUTANT_SH}"; then
  echo "ERROR: mutation is a no-op (mutant identical to source)"; exit 1
fi

identity_holds() {  # <journal-sh> -> 0 if main/worktree paths agree, 1 if they diverge
  local bin="$1" from_main from_wt
  from_main="$(CLAUDE_PROJECT_ROOT="${MAIN_REPO}" bash "${bin}" path "mutant-check-task" 2>/dev/null)"
  from_wt="$(CLAUDE_PROJECT_ROOT="${WT_DIR}" bash "${bin}" path "mutant-check-task" 2>/dev/null)"
  [[ -n "${from_main}" && "${from_main}" == "${from_wt}" ]]
}

identity_holds "${MUTANT_SH}"; pre_rc=$?
identity_holds "${JOURNAL_SH}"; post_rc=$?
if [[ ${pre_rc} -ne 0 && ${post_rc} -eq 0 ]]; then
  pass "mutation control: mutant (forced per-checkout fallback) diverges across worktrees, real resolver agrees"
  echo "RED-then-GREEN: leadv2-journal path-identity (pre_rc=${pre_rc} -> post_rc=${post_rc})"
else
  fail "mutation control" "mutant pre_rc=${pre_rc} (want !=0) real post_rc=${post_rc} (want 0)"
fi

git -C "${MAIN_REPO}" worktree remove --force "${WT_DIR}" >/dev/null 2>&1 || true

if [[ "${FAIL}" -eq 0 ]]; then
  echo "ALL PASS"
  exit 0
else
  echo "SOME FAILED"
  exit 1
fi
