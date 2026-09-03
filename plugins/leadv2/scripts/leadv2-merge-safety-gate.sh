#!/usr/bin/env bash
# leadv2-merge-safety-gate.sh — LANE-MERGE-SILENTLY-REVERTS-MAIN-01
#
# Refuses to land a lane whose merge into the default branch would delete a
# file the lane's own commits never touched. Five measured occurrences on
# 2026-09-03 -- all caught only because a human happened to run
# `git diff --stat main..HEAD` by hand before merging; the worst would have
# silently dropped 221 lines of a production test suite another lane had
# landed an hour earlier -- merge exit 0, no conflict, no warning.
#
# Discriminator (checked against all five measured cases + two negative
# controls -- see tests/test-leadv2-merge-safety-gate.sh -- before trusting
# it): a file that exists on the default branch's tip but is entirely absent
# from the lane's tip is dangerous UNLESS the lane's own commits (base..lane)
# are the ones that removed it. A lane that never touched the path can only
# be missing it because the path did not exist yet when the lane forked --
# the default branch grew it afterward, and the lane's tree simply never
# had it. A lane whose own history mentions the path (its own `git rm`, or a
# rename) is trusted: that deletion is the lane's decision and must still
# land (item 3 of the brief) -- a false refusal here is exactly the failure
# this gate must not introduce.
#
# Scope is deliberately restricted to full-file absence (--diff-filter=D
# comparing the two branch TIPS), never a partial content edit: a file
# merely MODIFIED by the default branch after the lane forked, on a path the
# lane never touched, is what every ordinary lane looks like (the default
# branch is always moving) -- flagging that would refuse nearly every merge.
# Only a path that vanishes ENTIRELY from the lane's tree, on a path the
# lane's own history never mentions, is the accidental-revert shape every
# measured incident shares.
#
# Usage:
#   leadv2-merge-safety-gate.sh <repo_root> <lane_branch> [<default_branch>]
# Exit codes:
#   0 = safe to merge -- no undeclared deletions (or every deletion is the
#       lane's own)
#   1 = REFUSED -- see stderr for the file(s) and the one-line remedy
#   2 = usage / git error (cannot resolve repo_root, branches, or merge-base)
set -uo pipefail

REPO_ROOT="${1:-}"
LANE_BRANCH="${2:-}"
DEFAULT_BRANCH="${3:-}"

if [[ -z "${REPO_ROOT}" || -z "${LANE_BRANCH}" ]]; then
  printf 'Usage: %s <repo_root> <lane_branch> [<default_branch>]\n' "$(basename "$0")" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=leadv2-branch-merged.sh
source "${SCRIPT_DIR}/leadv2-branch-merged.sh"

if [[ -z "${DEFAULT_BRANCH}" ]]; then
  DEFAULT_BRANCH="$(lv2_default_branch "${REPO_ROOT}")"
fi

git -C "${REPO_ROOT}" rev-parse --verify "${DEFAULT_BRANCH}" >/dev/null 2>&1 || {
  printf 'leadv2-merge-safety-gate: cannot resolve default branch %s\n' "${DEFAULT_BRANCH}" >&2
  exit 2
}
git -C "${REPO_ROOT}" rev-parse --verify "${LANE_BRANCH}" >/dev/null 2>&1 || {
  printf 'leadv2-merge-safety-gate: cannot resolve lane branch %s\n' "${LANE_BRANCH}" >&2
  exit 2
}

BASE="$(git -C "${REPO_ROOT}" merge-base "${DEFAULT_BRANCH}" "${LANE_BRANCH}" 2>/dev/null || true)"
if [[ -z "${BASE}" ]]; then
  printf 'leadv2-merge-safety-gate: no merge-base between %s and %s\n' "${DEFAULT_BRANCH}" "${LANE_BRANCH}" >&2
  exit 2
fi

# Paths the lane's OWN commits touched -- base..lane, name-only. This is the
# trust boundary: if the lane's own history mentions a path (edited it,
# deleted it, renamed it), any resulting absence is the lane's decision.
LANE_TOUCHED="$(git -C "${REPO_ROOT}" diff --name-only "${BASE}" "${LANE_BRANCH}" -- 2>/dev/null || true)"

# Paths present on the default branch's tip that are entirely absent from
# the lane's tip -- comparing TIPS, not base, so this is exactly what a
# human running `git diff --stat main..HEAD` sees.
DELETED="$(git -C "${REPO_ROOT}" diff --name-status --diff-filter=D "${DEFAULT_BRANCH}" "${LANE_BRANCH}" -- 2>/dev/null | cut -f2- || true)"

OFFENDERS=""
OFFENDER_COUNT=0
if [[ -n "${DELETED}" ]]; then
  while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    if ! grep -qxF "${path}" <<<"${LANE_TOUCHED}"; then
      OFFENDERS="${OFFENDERS}${path}"$'\n'
      OFFENDER_COUNT=$((OFFENDER_COUNT + 1))
    fi
  done <<<"${DELETED}"
fi

if [[ ${OFFENDER_COUNT} -eq 0 ]]; then
  exit 0
fi

printf 'MERGE_REFUSED: lane %s would delete %d file(s) it never touched, currently present on %s:\n' \
  "${LANE_BRANCH}" "${OFFENDER_COUNT}" "${DEFAULT_BRANCH}" >&2
while IFS= read -r path; do
  [[ -n "${path}" ]] || continue
  lines="$(git -C "${REPO_ROOT}" show "${DEFAULT_BRANCH}:${path}" 2>/dev/null | wc -l | tr -d ' ')"
  printf '  %s:1 (%s lines on %s, absent from %s, never touched by lane commits)\n' \
    "${path}" "${lines}" "${DEFAULT_BRANCH}" "${LANE_BRANCH}" >&2
done <<<"${OFFENDERS}"
printf 'FIX: merge %s into the lane, then retry.\n' "${DEFAULT_BRANCH}" >&2
exit 1
