#!/usr/bin/env bash
# test-mutation-runner-measures-only-declared-files.sh
# MUTATION-RUNNER-STAGES-EVERYTHING-01
#
# Subject: the REAL leadv2-mutation-control.sh. Nothing in it is stubbed. What
# is faked one level lower is a throwaway git repo standing in for a lane's
# checkout, plus three two-line scripts standing in for a production file, its
# suite, and an unrelated file another lane is mid-edit on.
#
# The claim: the measured scratch tree contains HEAD plus the mutation's file,
# the suite, and whatever the caller declares -- and nothing else. A dirty file
# no one declared must not reach the verdict. The paired obligation is that the
# runner still WORKS: a mutation inserted inside the function body must still
# turn the suite red and be reported killed.
#
# DECLARED NEGATIVE CONTROLS (apply INSIDE leadv2-mutation-control.sh's
# snapshot block; each must turn this suite RED):
#   N1  drop the `_mc_overlay "${_d}"` loop  => case (a) fails: the declared
#       file's uncommitted MARK=lane_wip never reaches the scratch, so the
#       baseline is not green and nothing is measured at all
#   N2  default LEADV2_MUTCTL_SNAPSHOT to worktree => case (b) fails: the stray
#       file is copied in and the suite goes red for someone else's edit
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="${LEADV2_MUTCTL_SH:-${SCRIPT_DIR}/../leadv2-mutation-control.sh}"
[[ -f "${RUNNER}" ]] || { echo "FATAL: runner not found: ${RUNNER}" >&2; exit 2; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/mutctl-declared.XXXXXX")" || exit 2
trap 'rm -rf "${WORK}"' EXIT
R="${WORK}/repo"

mkdir -p "${R}/tests"
git init -q -b main "${R}" >/dev/null 2>&1 || { echo "FATAL: git init"; exit 2; }
git -C "${R}" config user.email t@t.local; git -C "${R}" config user.name t
printf 'greet() {\n  printf hello\n}\nMARK=base\n' > "${R}/prod.sh"
printf 'CLEAN=1\n' > "${R}/noise.sh"
# The suite fails loudly if a file nobody declared reached the measured tree.
# It also requires MARK=lane_wip, which exists ONLY in the uncommitted working
# copy of prod.sh -- so the suite is green only if the DECLARED file's dirty
# state reached the measured tree (CHALLENGE-05's original point, kept).
printf '#!/usr/bin/env bash\nif grep -q CONTAMINANT ../noise.sh 2>/dev/null; then echo "contaminated"; exit 1; fi\n. ../prod.sh\n[[ "$(greet)" == hello ]] && [[ "${MARK:-}" == lane_wip ]]\n' \
  > "${R}/tests/suite.sh"
chmod +x "${R}/tests/suite.sh"
git -C "${R}" add prod.sh noise.sh tests/suite.sh >/dev/null 2>&1
git -C "${R}" commit -qm base >/dev/null 2>&1
git -C "${R}" checkout -q -b lane
printf 'greet() {\n  printf hello\n}\nMARK=base\n# lane touched this\n' > "${R}/prod.sh"
git -C "${R}" add prod.sh >/dev/null 2>&1
git -C "${R}" commit -qm "lane work" >/dev/null 2>&1

# The lane's own uncommitted work on the DECLARED file -- must reach the tree.
printf 'greet() {\n  printf hello\n}\nMARK=lane_wip\n# lane touched this\n' > "${R}/prod.sh"
# Another lane's half-finished edit, uncommitted, nobody declared it -- must not.
printf 'CONTAMINANT=1\n' > "${R}/noise.sh"

SED='s/  printf hello/  printf goodbye/'
echo "== the runner measures HEAD + declared files only"
OUT="$(cd "${R}" && bash "${RUNNER}" tests/suite.sh prod.sh "${SED}" "${WORK}" 2>&1)"

# (a) the runner still works: a mutation inside the function body kills the suite
if grep -q '^MUTATION-CONTROL ok ' <<< "${OUT}"; then
  ok "(a) declared file's uncommitted state is in the tree AND the body mutation is killed"
else
  bad "(a) runner did not report a kill: $(grep -m1 'MUTATION-CONTROL' <<< "${OUT}")"
fi

# (b) the stray file did not reach the verdict
if grep -q 'reason=baseline_not_green' <<< "${OUT}" || grep -q 'contaminated' <<< "${OUT}"; then
  bad "(b) an undeclared dirty file reached the measured tree"
else
  ok "(b) undeclared dirty file never reached the measured tree"
fi

# (c) and it was named, not silently dropped
if grep -qE 'snapshot=head_plus_declared declared=[0-9]+ excluded_dirty=[1-9]' <<< "${OUT}"; then
  ok "(c) the excluded dirty file is counted out loud"
else
  bad "(c) no excluded_dirty count: $(grep -m1 'snapshot=' <<< "${OUT}")"
fi

# (d) the other colour: the old whole-worktree snapshot really was contaminated
echo "== contrast: the pre-fix snapshot mode"
OUT_W="$(cd "${R}" && LEADV2_MUTCTL_SNAPSHOT=worktree bash "${RUNNER}" tests/suite.sh prod.sh "${SED}" "${WORK}" 2>&1)"
if grep -q 'reason=baseline_not_green' <<< "${OUT_W}"; then
  ok "(d) snapshot=worktree still shows the contamination this fix removes"
else
  bad "(d) worktree mode did not reproduce the contamination (expected baseline_not_green)"
fi

echo
echo "passed=${PASS} failed=${FAIL}"
[[ ${FAIL} -eq 0 ]]
