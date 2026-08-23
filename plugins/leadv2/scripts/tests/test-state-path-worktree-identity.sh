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
  "founder-status.md"
  "founder-status-full.md"
  ".board-empty-since"
  ".founder-status-epoch"
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

# The RENDER-class symlink is a contract, not a convenience (founder-status
# files are opened directly by a human and by leadv2-single-lead-beat.sh) --
# assert both worktrees actually carry the symlink, not just an equal
# resolver return value.
for name in "founder-status.md" "founder-status-full.md"; do
  main_link="${MAIN_REPO}/docs/leadv2/${name}"
  wt_link="${WT_DIR}/docs/leadv2/${name}"
  if [[ -L "${main_link}" && -L "${wt_link}" ]]; then
    pass "${name}: symlinked in both the main checkout and the worktree"
  else
    fail "${name}: symlink contract" "main is_link=$( [[ -L "${main_link}" ]] && echo yes || echo no ) wt is_link=$( [[ -L "${wt_link}" ]] && echo yes || echo no )"
  fi
done

git -C "${MAIN_REPO}" worktree remove --force "${WT_DIR}" >/dev/null 2>&1 || true

if [[ "${FAIL}" -eq 0 ]]; then
  echo "ALL PASS"
  exit 0
else
  echo "SOME FAILED"
  exit 1
fi
