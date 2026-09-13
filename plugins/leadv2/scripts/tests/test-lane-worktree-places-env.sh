#!/usr/bin/env bash
# run-all-triggers: leadv2-lane-worktree
# LANE-ENV-SYMLINK-01: creation/reuse placement is symlink-only and fail-open.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LANE_SH="${LEADV2_LANE_WORKTREE_SCRIPT:-${HERE}/../leadv2-lane-worktree.sh}"
PASS=0 FAIL=0
pass() { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/lane-env.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT

ROOT="${TMP}/with-env"
ERRF="${TMP}/with-env.err"
git init -q -b main "${ROOT}"
git -C "${ROOT}" config user.email test@example.invalid
git -C "${ROOT}" config user.name test
printf '.env\n' > "${ROOT}/.gitignore"
printf 'SECRET=value\n' > "${ROOT}/.env"
printf 'seed\n' > "${ROOT}/seed.txt"
git -C "${ROOT}" add .gitignore seed.txt && git -C "${ROOT}" commit -qm seed

LANE="$(LEADV2_PROJECT_ROOT="${ROOT}" LEADV2_WORKTREE_DIR="${TMP}/lanes" \
  LEADV2_LANE_WORKTREE_ERRF="${ERRF}" LEADV2_CODEX_WORKTREE_TRUST=off \
  bash "${LANE_SH}" ensure with-env-lane)"
if [[ -L "${LANE}/.env" ]] && [[ "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${LANE}/.env")" == "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${ROOT}/.env")" ]] \
   && [[ -z "$(git -C "${LANE}" status --short)" ]]; then
  pass 'fresh ignored .env is a symlink and the lane remains clean'
else
  fail "fresh lane env placement failed (lane=${LANE}, link=$(readlink "${LANE}/.env" 2>/dev/null), status=$(git -C "${LANE}" status --short))"
fi

ROOT_NO_ENV="${TMP}/without-env"
ERRF_NO_ENV="${TMP}/without-env.err"
git init -q -b main "${ROOT_NO_ENV}"
git -C "${ROOT_NO_ENV}" config user.email test@example.invalid
git -C "${ROOT_NO_ENV}" config user.name test
printf '.env\n' > "${ROOT_NO_ENV}/.gitignore"
printf 'seed\n' > "${ROOT_NO_ENV}/seed.txt"
git -C "${ROOT_NO_ENV}" add .gitignore seed.txt && git -C "${ROOT_NO_ENV}" commit -qm seed
LANE_NO_ENV="$(LEADV2_PROJECT_ROOT="${ROOT_NO_ENV}" LEADV2_WORKTREE_DIR="${TMP}/lanes-no-env" \
  LEADV2_LANE_WORKTREE_ERRF="${ERRF_NO_ENV}" LEADV2_CODEX_WORKTREE_TRUST=off \
  bash "${LANE_SH}" ensure without-env-lane)"
if [[ ! -e "${LANE_NO_ENV}/.env" ]] && grep -q 'reason=source_absent' "${ERRF_NO_ENV}"; then
  pass 'missing source .env is skipped and the reason is recorded'
else
  fail "missing source handling failed (lane=${LANE_NO_ENV}, err=$(cat "${ERRF_NO_ENV}" 2>/dev/null))"
fi

printf '[TEST] %d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == 0 ]]
