#!/usr/bin/env bash
# tests/test-state-path-worktree-identity.sh — LANE-STATE-LEAK-01
#
# The whole point of this task: resolve every LANE-STATE-LEAK-01 managed name
# from a linked worktree and from the main checkout of the SAME repo, and
# assert the two resolved paths are byte-identical. Without this asserted, a
# future name added with a raw ${PROJECT_ROOT}/docs/leadv2/... string
# regresses silently -- exactly the bug this task fixes.
#
# Hermetic: LEADV2_STATE_BASE points at a throwaway dir (bypasses both the
# real ~/.claude/leadv2-state and the STATE-DIR-JUNK-01 ephemeral redirect,
# since that redirect only fires when LEADV2_STATE_BASE is UNSET).
# run-all-triggers: leadv2-state-path
#
# SUITE-SELECTION-COVERS-140-OF-390-01: this suite carried no trigger
# marker and matched no name convention, so `run-all.sh --scope changed`
# never selected it — it could only ever run under `--scope all`. The
# triggers are the production files the suite's own body references most,
# with shared helpers excluded so a helper edit does not select everything.


set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_PATH_SH="${SCRIPT_DIR}/../leadv2-state-path.sh"
FAIL=0

bash -n "${STATE_PATH_SH}" || { echo "ERROR: bash -n failed for ${STATE_PATH_SH}"; exit 1; }

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
git -C "${MAIN_REPO}" worktree add -q -b test-lane-branch "${WT_DIR}" >/dev/null 2>&1 \
  || { echo "ERROR: git worktree add failed"; exit 1; }

export LEADV2_STATE_BASE="${STATE_BASE}"
unset LEADV2_STATE_ROOT

# Every name LANE-STATE-LEAK-01 routes through the resolver -- STANDARD +
# RENDER + MERGE(file) + MERGE(dir). GLOB (.arm-exceptions-<day>) is
# excluded on purpose: by design it is NOT symlinked and each call resolves
# a fresh dated leaf, so "same name resolves identically" is exactly what
# the STANDARD/RENDER/MERGE names below already prove for the shared root;
# a dedicated glob-day assertion would just restate that.
MANAGED_NAMES=(
  "active.yaml"
  "bus.jsonl"
  "merge-queue.jsonl"
  "open-threads.md"
  ".codex-credits-empty.stamp"
  "glm-deferred.jsonl"
  "glm-deferred.d"
)

for name in "${MANAGED_NAMES[@]}"; do
  from_main="$(PROJECT_ROOT="${MAIN_REPO}" bash "${STATE_PATH_SH}" "${name}" 2>/dev/null)"
  from_wt="$(PROJECT_ROOT="${WT_DIR}" bash "${STATE_PATH_SH}" "${name}" 2>/dev/null)"
  if [[ -z "${from_main}" || -z "${from_wt}" ]]; then
    fail "${name}: resolution" "main='${from_main}' worktree='${from_wt}' (empty)"
  elif [[ "${from_main}" != "${from_wt}" ]]; then
    fail "${name}: identity" "main='${from_main}' worktree='${from_wt}'"
  elif [[ "${from_main}" == "${MAIN_REPO}"* || "${from_main}" == "${WT_DIR}"* ]]; then
    fail "${name}: outside-checkout" "resolved INSIDE a worktree: ${from_main}"
  else
    pass "${name}: identical from main checkout and linked worktree (${from_main})"
  fi
done

# ONE-STATUS-MECHANISM-01 (2026-09-13): the founder-status RENDER-class
# symlink assertions were deleted with the retired beat chain (RENDER is
# empty now; no live writer creates those files).

# ── falsification: prove this suite's own identity check can actually FAIL ──
# Mutant: force the git-common-dir lookup empty so the resolver takes its
# "not inside a git repo" branch unconditionally, which pins STATE_ROOT at
# "${LINK_ROOT}/docs/leadv2" -- the exact raw, per-worktree path
# LANE-STATE-LEAK-01 exists to kill. Against a REAL linked worktree (main vs
# WT_DIR are different directories), that must make main/worktree resolution
# diverge. A copy of production code, mutated one line, run through the
# suite's own identity check -- not a printed sentence.
MUTANT_SH="${TMP_ROOT}/leadv2-state-path.mutant.sh"
cp "${STATE_PATH_SH}" "${MUTANT_SH}"
sed -i.bak 's/COMMON_DIR="\$(git -C "\$LINK_ROOT" rev-parse --path-format=absolute --git-common-dir 2>\/dev\/null || true)"/COMMON_DIR=""/' "${MUTANT_SH}"
rm -f "${MUTANT_SH}.bak"
chmod +x "${MUTANT_SH}"
if ! grep -q 'COMMON_DIR=""' "${MUTANT_SH}"; then
  echo "ERROR: falsification mutant patch did not apply (sed pattern stale vs source)"; exit 1
fi

identity_holds() {  # <state-path-bin> -> 0 if main/worktree resolve identically, 1 if they diverge
  local bin="$1"
  local from_main from_wt
  from_main="$(PROJECT_ROOT="${MAIN_REPO}" bash "${bin}" "active.yaml" 2>/dev/null)"
  from_wt="$(PROJECT_ROOT="${WT_DIR}" bash "${bin}" "active.yaml" 2>/dev/null)"
  [[ -n "${from_main}" && "${from_main}" == "${from_wt}" ]]
}

identity_holds "${MUTANT_SH}"; pre_rc=$?
identity_holds "${STATE_PATH_SH}"; post_rc=$?
if [[ ${pre_rc} -ne 0 && ${post_rc} -eq 0 ]]; then
  pass "falsification: mutant (raw per-worktree path) diverges, real resolver agrees"
  echo "RED-then-GREEN: worktree-identity (pre_rc=${pre_rc} -> post_rc=${post_rc})"
else
  fail "falsification" "mutant pre_rc=${pre_rc} (want !=0) real post_rc=${post_rc} (want 0)"
fi

git -C "${MAIN_REPO}" worktree remove --force "${WT_DIR}" >/dev/null 2>&1 || true

if [[ "${FAIL}" -eq 0 ]]; then
  echo "ALL PASS"
  exit 0
else
  echo "SOME FAILED"
  exit 1
fi
