#!/usr/bin/env bash
# FALSIFICATION-PATH-HAS-NO-BASELINE-CLASSIFIER-01 — the C4 (TEST-FALSIFICATION-GATE-01)
# block in lib/leadv2-builder-selfcheck.sh runs a test-*.sh/*_test.sh file and, on a
# non-zero exit, used to charge the lane FAIL unconditionally -- never consulting
# `_selfcheck_baseline_verdict`, the SAME classifier the C3 (suites) block already used
# to tell "this suite is red for reasons inherited from main" from "this lane broke it".
# Measured on two live lanes 2026-09-05: every refusal was `falsification:<suite>:
# test_failed` against a suite red on a clean `git archive main` checkout too -- the
# lane paid for redness it never introduced, solely because it happened to touch a
# test-*.sh file that C3 never ran (or wasn't even in tests_mode=auto's stem set).
#
# self-registered: any tests/test-*.sh directly under this directory is auto-discovered
# by tests/run-all.sh's DISCOVERED_SUITE_MAP (maxdepth 1, no EXTRA_SUITE_MAP row needed).
#
# WHAT IS REAL HERE. The actual production `lv2_selfcheck_run` is sourced and called
# end-to-end (not an extracted copy) against real git repos this suite builds, so the
# assertions prove the WIRING -- that the falsification path actually reaches the
# baseline classifier -- not just the classifier's own logic in isolation (that is
# test-selfcheck-baseline-ref.sh's job, one file over).
#
# BOUNDARY DECISION (declared before the fix, per the task brief): SKIP_RED here means
# "skip attribution of the CRASH to the lane" -- i.e. it only ever applies inside the
# `tf_rc != 0` branch. It can never apply to the RED-then-GREEN marker check, because
# that check only runs once the test has ALREADY exited 0 (see the `elif grep -qE
# 'RED-then-GREEN...'` arm immediately below the case block this fix adds) -- there is
# no "red half" of a marker check performed against an already-passing run. So the
# baseline classifier answers exactly one question on this path: was this test's
# non-zero exit inherited from main, or did the lane cause it.
#
# DECLARED NEGATIVE CONTROL (tests/mutations/catalog.yaml, id
# falsification-path-always-skips-baseline-red): `_selfcheck_baseline_verdict`'s body
# replaced with `printf 'SKIP_RED'; return` unconditionally. Kills case (B) below --
# a lane-introduced regression would silently stop blocking.
set -euo pipefail
ROOT="${LEADV2_TEST_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
LIB="${ROOT}/scripts/lib/leadv2-builder-selfcheck.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

# shellcheck source=/dev/null
source "$LIB"

git_init() {
  local dir="$1" default="${2:-main}"
  git -c init.defaultBranch="${default}" init -q "${dir}"
  git -C "${dir}" config user.email t@e
  git -C "${dir}" config user.name t
}

run_gate() { # <diff_root> <diff_file> <out_md>
  ( cd /tmp && LEADV2_BUILDER_SELFCHECK_TESTS=never LEADV2_SCOPE_DISCIPLINE=0 \
      lv2_selfcheck_run "$2" "$1" "$1" "$3" "" > /dev/null 2>&1 )
}

# ── repo A: local "main" resolves (the ordinary case) ──────────────────────────────
REPO="$T/repoA"
git_init "${REPO}" main
mkdir -p "${REPO}/tests"
printf '#!/usr/bin/env bash\nexit 1\n' > "${REPO}/tests/test-legacy-broken.sh"   # (A) inherited red
printf '#!/usr/bin/env bash\nexit 0\n' > "${REPO}/tests/test-was-green.sh"       # (B) currently green
git -C "${REPO}" add -A; git -C "${REPO}" commit -qm baseline
git -C "${REPO}" checkout -qb lane
# lane touches (A) without fixing it (still exit 1) -- and breaks (B) (now exit 1) --
# and introduces a brand-new broken test (C), never seen at baseline.
printf '#!/usr/bin/env bash\n# lane reformat, still broken\nexit 1\n' > "${REPO}/tests/test-legacy-broken.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "${REPO}/tests/test-was-green.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "${REPO}/tests/test-new-broken.sh"      # (C) lane-introduced file
git -C "${REPO}" add -A; git -C "${REPO}" commit -qm "lane change"

DIFF="$T/a.diff"
git -C "${REPO}" diff main lane > "${DIFF}"
OUT="$T/a.md"
run_gate "${REPO}" "${DIFF}" "${OUT}" || true

# (A) inherited red: baseline copy is ALSO red -> SKIP, not charged to the lane.
if grep -qE '\| falsification \| tests/test-legacy-broken\.sh \| SKIP \(baseline_red\) \|' "${OUT}"; then
  ok "(A) a falsification test red on the baseline is SKIP (baseline_red), not FAIL"
else
  bad "(A) expected SKIP (baseline_red) for test-legacy-broken.sh; got:
$(grep 'test-legacy-broken' "${OUT}" || echo '<no row>')"
fi

# (B) THE PAIRED NEGATIVE THAT MATTERS: green on the baseline, red only in the lane --
# must still FAIL. If this ever flips too, the fix stopped being an attribution
# correction and became a hole any lane can drive a real regression through.
if grep -qE '\| falsification \| tests/test-was-green\.sh \| FAIL \(test_failed:rc=1\) \|' "${OUT}"; then
  ok "(B) a falsification test green on the baseline and red only in the lane still FAILs"
else
  bad "(B) expected FAIL (test_failed) for test-was-green.sh; got:
$(grep 'test-was-green' "${OUT}" || echo '<no row>')"
fi

# (C) a lane-introduced test file has no baseline copy at all -- must still FAIL, never
# SKIP_RED (a lane cannot launder its own new red by never having shipped it before).
if grep -qE '\| falsification \| tests/test-new-broken\.sh \| FAIL \(test_failed:rc=1\) \|' "${OUT}"; then
  ok "(C) a lane-introduced (baseline-absent) falsification test still FAILs"
else
  bad "(C) expected FAIL (test_failed) for test-new-broken.sh; got:
$(grep 'test-new-broken' "${OUT}" || echo '<no row>')"
fi

# ── repo B: no "main" branch anywhere, no origin -- baseline is unresolvable ────────
REPO2="$T/repoB"
git_init "${REPO2}" trunk
mkdir -p "${REPO2}/tests"
printf '#!/usr/bin/env bash\nexit 0\n' > "${REPO2}/tests/test-x.sh"
git -C "${REPO2}" add -A; git -C "${REPO2}" commit -qm c1
printf '#!/usr/bin/env bash\nexit 1\n' > "${REPO2}/tests/test-x.sh"
git -C "${REPO2}" add -A; git -C "${REPO2}" commit -qm c2

DIFF2="$T/b.diff"
git -C "${REPO2}" diff HEAD~1 HEAD > "${DIFF2}"
OUT2="$T/b.md"
run_gate "${REPO2}" "${DIFF2}" "${OUT2}" || true

# (D) merge-base to both "main" and "origin/main" fails -> fail OPEN and NAME it, never
# a silent FAIL and never a silent pass.
if grep -qE '\| falsification \| tests/test-x\.sh \| SKIP \(baseline_unresolved\) \|' "${OUT2}"; then
  ok "(D) an unresolvable baseline SKIPs (baseline_unresolved), open and named"
else
  bad "(D) expected SKIP (baseline_unresolved) for test-x.sh; got:
$(grep 'test-x' "${OUT2}" || echo '<no row>')"
fi

printf '[FALSIFICATION-BASELINE-CLASSIFIER] pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
