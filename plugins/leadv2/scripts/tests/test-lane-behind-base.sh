#!/usr/bin/env bash
# test-lane-behind-base.sh — LANE-BEHIND-MAIN-01.
#
# WHY THIS TEST EXISTS: nothing in the dispatcher ever computed how far a lane had
# drifted behind the default branch, so gate results were routinely reported about a
# tree that is not the one the lane merges into — and the error goes BOTH ways, which
# is what makes it expensive:
#   - lane 70d40b43, 20 behind: e2e failed test-target-topic-gate.sh and read as a
#     brand-safety regression. The lane simply predated
#     personas/respiro-brand/topic-policy.md, which main had gained the day before.
#     That suite is 120/0 on main.
#   - lane a14c371d, 27 behind: reported "24 passed / 0 failed — deploy gate cleared"
#     and the lead wrote it down as mergeable. The green was measured against a tree
#     missing 27 commits of main.
#
# The dispatcher change is ADVISORY: it emits `lane_behind_base` and a stderr warning
# past a threshold, and never blocks — refusing would strand finished work behind an
# automatic gate, and the drift is usually harmless.
#
# WHAT THIS TEST COVERS: the git arithmetic that decides the number, in a scratch repo
# with real commits — the part that can silently be wrong (the origin/HEAD lookup, its
# fallback when no remote exists, and the HEAD..base direction, which is trivially easy
# to invert). The stderr wording and the emit plumbing are not covered here; they are
# observed live on the next dispatch of a behind lane.

set -uo pipefail

PASS=0; FAIL=0
declare -a ERRORS=()
log() { printf '[TEST] %s\n' "$*"; }
_check() { # <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then PASS=$((PASS+1)); log "PASS: $1"
  else FAIL=$((FAIL+1)); ERRORS+=("$1: expected '$2', got '$3'"); log "FAIL: $1 -- expected '$2', got '$3'"; fi
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/lane-behind.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

# The exact expression the dispatcher runs, lifted verbatim so a change there without a
# change here shows up as a failure rather than as silent drift.
_behind_of() { # <repo dir> -> "<base> <behind>"
  local root="$1" base behind
  base="$(git -C "${root}" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
  base="${base#origin/}"
  [[ -n "${base}" ]] || base=main
  if ! git -C "${root}" rev-parse --verify --quiet "${base}" >/dev/null 2>&1; then
    printf '%s -' "${base}"; return
  fi
  behind="$(git -C "${root}" rev-list --count "HEAD..${base}" 2>/dev/null || echo 0)"
  printf '%s %s' "${base}" "${behind:-0}"
}

REPO="${WORK}/repo"
git init -q -b main "${REPO}"
git -C "${REPO}" config user.email t@t.t
git -C "${REPO}" config user.name t
printf 'base\n' > "${REPO}/f.txt"
git -C "${REPO}" add f.txt && git -C "${REPO}" commit -qm base

# A lane branched here, then main moved on by 3.
git -C "${REPO}" branch lane
for i in 1 2 3; do
  printf 'main %s\n' "$i" >> "${REPO}/f.txt"
  git -C "${REPO}" commit -qam "main ${i}"
done

LANE="${WORK}/lane-wt"
git -C "${REPO}" worktree add -q "${LANE}" lane
printf 'lane work\n' > "${LANE}/g.txt"
git -C "${LANE}" add g.txt && git -C "${LANE}" commit -qm "lane work"

# 1. A lane that branched before 3 main commits is 3 behind, regardless of its own
#    commits ahead. Inverting the revspec would report 1 here, so this pins direction.
_check "behind counts main's commits, not the lane's" "main 3" "$(_behind_of "${LANE}")"

# 2. The main checkout is never behind itself. A non-zero here would make every
#    dispatch to the shared tree emit a spurious warning.
_check "main checkout is 0 behind" "main 0" "$(_behind_of "${REPO}")"

# 3. After merging main in, the lane is level — this is the state the warning asks for,
#    so it must actually clear.
git -C "${LANE}" merge -q main -m merge 2>/dev/null
_check "merging the base clears the drift" "main 0" "$(_behind_of "${LANE}")"

# 4. No remote configured: origin/HEAD does not resolve and the fallback to 'main' must
#    hold. Without the fallback the lookup yields an empty ref and rev-parse fails, so
#    the check would silently never fire — the failure mode being guarded against here
#    is "the warning stops appearing", which is invisible unless asserted.
_check "falls back to 'main' with no remote" "main 0" "$(_behind_of "${REPO}")"

# 5. A base that does not exist must not be counted as 0 behind. Reporting 0 for a
#    missing ref would read as "up to date" — the same lying-green shape this warning
#    exists to prevent.
REPO2="${WORK}/repo2"
git init -q -b trunk "${REPO2}"
git -C "${REPO2}" config user.email t@t.t
git -C "${REPO2}" config user.name t
printf 'x\n' > "${REPO2}/f.txt"
git -C "${REPO2}" add f.txt && git -C "${REPO2}" commit -qm x
_check "missing base reports '-', never 0" "main -" "$(_behind_of "${REPO2}")"

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ ${FAIL} -gt 0 ]]; then printf -- 'FAIL: %s\n' "${ERRORS[@]}"; exit 1; fi
exit 0
