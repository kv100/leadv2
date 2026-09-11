#!/usr/bin/env bash
# run-all-triggers: leadv2-dispatch-code
# RESUME-LANE-ACCEPTS-A-MISSION-ITS-WORKTREE-CANNOT-SEE-01.
# Hermetic committed-tree proof for @mission visibility on a resumed lane.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DC="${LEADV2_DISPATCH_CODE_FILE:-${SCRIPT_DIR}/leadv2-dispatch-code.sh}"
PASS=0 FAIL=0
ok() { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

D="$(mktemp -d /tmp/leadv2-resume-mission-XXXXXX)"
trap 'rm -rf "${D}"' EXIT
R="${D}/repo" W="${R}/.claude/worktrees/old-lane"
mkdir -p "${R}"
(cd "${R}" && git init -q -b main && git config user.email t@e && git config user.name t && printf 'round one\n' > BRIEF.md && git add BRIEF.md && git commit -qm seed)
mkdir -p "$(dirname "${W}")"
(cd "${R}" && git worktree add -q "${W}" -b worktree-old-lane)
(cd "${R}" && printf 'round two\n' > ROUND-2.md && git add ROUND-2.md && git commit -qm main-round-two)

# Source only exposes the production preflight without consuming this suite's argv.
LEADV2_DISPATCH_SOURCE_ONLY=1 source "${DC}"
PROJECT_ROOT="${R}"
LANE_WORKTREE_BIN="${SCRIPT_DIR}/leadv2-lane-worktree.sh"

RESUME_MISSION_WORKTREE=""
_resume_mission_visibility_preflight '@BRIEF.md' old-lane
if [[ "${RESUME_MISSION_WORKTREE}" == "$(cd "${W}" && pwd -P)" ]] && [[ "$(git -C "${RESUME_MISSION_WORKTREE}" show HEAD:BRIEF.md)" == 'round one' ]]; then
  ok 'case 1 visible mission is read from lane HEAD'
else
  bad 'case 1 visible mission did not resolve to lane HEAD'
fi

run_refusal() { # <path> <stdout+stderr file>
  local p="$1" out="$2" rc=0
  bash -c 'LEADV2_DISPATCH_SOURCE_ONLY=1; source "$1"; PROJECT_ROOT="$2"; LANE_WORKTREE_BIN="$3"; _resume_mission_visibility_preflight "@$4" old-lane' \
    _ "${DC}" "${R}" "${SCRIPT_DIR}/leadv2-lane-worktree.sh" "${p}" >"${out}" 2>&1 || rc=$?
  printf '%s' "${rc}"
}

W_PHYS="$(cd "${W}" && pwd -P)"
o2="${D}/case2.log"; rc2="$(run_refusal ROUND-2.md "${o2}")"
if [[ "${rc2}" == 5 ]] && grep -q 'present on main but not reachable' "${o2}" && grep -Fq "git -C ${W_PHYS} checkout main -- ROUND-2.md" "${o2}"; then
  ok 'case 2 invisible main mission refuses with lane-specific remedy'
else
  bad "case 2 invisible main mission refuses with lane-specific remedy (rc=${rc2}, out=$(tr '\n' ' ' < "${o2}"))"
fi

o3="${D}/case3.log"; rc3="$(run_refusal NO-SUCH.md "${o3}")"
if [[ "${rc3}" == 5 ]] && grep -q 'absent from both lane worktree' "${o3}" && ! grep -q 'present on main' "${o3}"; then
  ok 'case 3 absent-everywhere mission is distinct'
else
  bad "case 3 expected distinct rc=5 refusal (rc=${rc3}, out=$(tr '\n' ' ' < "${o3}"))"
fi

RESUME_MISSION_WORKTREE=sentinel
_resume_mission_visibility_preflight '@ROUND-2.md' ''; plain_rc=$?
if [[ ${plain_rc} -eq 0 && "${RESUME_MISSION_WORKTREE}" == "" ]]; then
  ok 'case 4 ordinary non-resume @mission preflight is byte-silent'
else
  bad 'case 4 ordinary non-resume behavior changed'
fi

printf 'test-resume-lane-refuses-invisible-mission: %d passed, %d failed\n' "${PASS}" "${FAIL}"
exit "${FAIL}"
