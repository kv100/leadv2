#!/usr/bin/env bash
# tests/test-plugin-scripts-drift-guard.sh — DRIFT-GUARDS-TO-CANON-01 fix-round 1.
#
# Round-1 landed plugins/leadv2/hooks/plugin-scripts-drift-guard.sh (commit
# a79dbccf) with ZERO test coverage. Review found the guard's staged-file
# enumeration used `git diff --cached --diff-filter=ACMR`, which OMITS `T`
# (typechange). Replacing a tracked symlink with a real file and `git add`ing
# it is recorded by git as T, never M — so the exact scenario the guard
# exists to catch (a vendored copy landing where canonical's symlink
# belongs) walked straight through with rc=0, no output, no block. Fixed to
# `ACMRT`. This suite is the acceptance test that fix should have shipped
# with the first time.
#
# Every case below plants its fixture in a mktemp sandbox (never this repo)
# and points the guard at it via LEADV2_CANONICAL_ROOT — the same override
# convention as test-drift-guard-safety-fixes.sh.
#
# Git status letters this guard covers (after the ACMRT fix), one case each:
#   A  brand-new real file, never a symlink
#   M  edit to an already-vendored (already-real) copy
#   T  symlink replaced by a real file and staged (THE round-1 gap — this is
#      the letter ACMR omitted and ACMRT restores)
#   R  rename of a real vendored file — was ALREADY covered pre-fix (R was
#      in ACMR too); included here for completeness, not as a regression
#      test for this round's change. Whether git reports it as R100 or
#      splits into A+D depends on local gitconfig; either way the guard's
#      own output is asserted, not one hardcoded status letter.
# Letter this guard deliberately does NOT cover: D (pure delete — nothing to
# vendor-check), and C (copy) is unexercised here but sits in the same
# family as R/A and is not expected to behave differently.
#
# Bash 3.2 compatible: no arrays, no ${x^^}, no mapfile.
# Run: bash plugins/leadv2/scripts/tests/test-plugin-scripts-drift-guard.sh
# Exit 0 = all pass; non-zero = failures found.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOKS_ROOT="$(cd "${SCRIPTS_ROOT}/../hooks" && pwd)"
GUARD="${HOOKS_ROOT}/plugin-scripts-drift-guard.sh"

FAIL=0
pass() { printf -- 'PASS: %s\n' "$*"; }
fail() { printf -- 'FAIL: %s\n' "$*" >&2; FAIL=1; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "${TMPROOT}"' EXIT

# ── 0. bash -n on the guard under test ──────────────────────────────────────
if bash -n "${GUARD}"; then
  pass "bash -n clean (plugin-scripts-drift-guard.sh)"
else
  fail "bash -n FAILED (plugin-scripts-drift-guard.sh)"
fi

# ── fixture builder: canonical root + a git repo with a tracked symlink ────
# $1 = sandbox dir (fresh), $2 = relpath under .claude/scripts (e.g. foo.sh)
mk_fixture() {
  local sbx="$1" rel="$2" canon repo
  canon="${sbx}/canonical"
  repo="${sbx}/project"
  mkdir -p "${canon}/plugins/leadv2/scripts/$(dirname "${rel}")"
  mkdir -p "${repo}/.claude/scripts/$(dirname "${rel}")"
  printf '#!/bin/bash\necho canonical\n' > "${canon}/plugins/leadv2/scripts/${rel}"
  git init -q "${repo}"
  git -C "${repo}" config user.email t@t.local
  git -C "${repo}" config user.name t
  ln -s "${canon}/plugins/leadv2/scripts/${rel}" "${repo}/.claude/scripts/${rel}"
  git -C "${repo}" add ".claude/scripts/${rel}"
  git -C "${repo}" commit -q -m "initial: symlink ${rel}"
}

run_guard() {
  # $1 = repo, $2 = canonical root -> prints guard stdout+stderr, returns its rc
  local repo="$1" canon="$2"
  ( cd "${repo}" && \
    LEADV2_CANONICAL_ROOT="${canon}" \
    bash -c 'echo "{\"tool_input\":{\"command\":\"git commit -m test\"}}" | bash "'"${GUARD}"'"' ) 2>&1
}

# ── case A: brand-new real file, never a symlink (has canonical counterpart) ─
SBX_A="${TMPROOT}/case-a"
mk_fixture "${SBX_A}" "bar.sh"
printf '#!/bin/bash\necho vendored-from-day-one\n' > "${SBX_A}/project/.claude/scripts/newfile.sh"
cp "${SBX_A}/project/.claude/scripts/newfile.sh" "${SBX_A}/canonical/plugins/leadv2/scripts/newfile.sh"
git -C "${SBX_A}/project" add .claude/scripts/newfile.sh
status_a="$(git -C "${SBX_A}/project" diff --cached --name-status -- .claude/scripts/newfile.sh)"
case "${status_a}" in
  A*) pass "case A: git status letter is A as expected (${status_a})" ;;
  *) fail "case A: expected git status A, got: ${status_a}" ;;
esac
out_a="$(run_guard "${SBX_A}/project" "${SBX_A}/canonical")"; rc_a=$?
if [[ "${rc_a}" == 2 ]] && printf -- '%s' "${out_a}" | grep -q "newfile.sh"; then
  pass "case A (new real file): guard REFUSES and names newfile.sh (rc=${rc_a})"
else
  fail "case A (new real file): expected rc=2 naming newfile.sh, got rc=${rc_a} out=${out_a}"
fi

# ── case M: edit to an already-vendored (already-real) copy ────────────────
SBX_M="${TMPROOT}/case-m"
mk_fixture "${SBX_M}" "bar.sh"
rm "${SBX_M}/project/.claude/scripts/bar.sh"
printf '#!/bin/bash\necho vendored-v1\n' > "${SBX_M}/project/.claude/scripts/bar.sh"
git -C "${SBX_M}/project" add .claude/scripts/bar.sh
git -C "${SBX_M}/project" commit -q -m "accidental vendor (simulates a pre-fix slip)" --no-verify
printf '#!/bin/bash\necho vendored-v2-edited\n' > "${SBX_M}/project/.claude/scripts/bar.sh"
git -C "${SBX_M}/project" add .claude/scripts/bar.sh
status_m="$(git -C "${SBX_M}/project" diff --cached --name-status -- .claude/scripts/bar.sh)"
case "${status_m}" in
  M*) pass "case M: git status letter is M as expected (${status_m})" ;;
  *) fail "case M: expected git status M, got: ${status_m}" ;;
esac
out_m="$(run_guard "${SBX_M}/project" "${SBX_M}/canonical")"; rc_m=$?
if [[ "${rc_m}" == 2 ]] && printf -- '%s' "${out_m}" | grep -q "bar.sh"; then
  pass "case M (edit to vendored copy): guard REFUSES and names bar.sh (rc=${rc_m})"
else
  fail "case M (edit to vendored copy): expected rc=2 naming bar.sh, got rc=${rc_m} out=${out_m}"
fi

# ── case T: symlink replaced by a real file (the round-1 gap) ──────────────
SBX_T="${TMPROOT}/case-t"
mk_fixture "${SBX_T}" "foo.sh"
rm "${SBX_T}/project/.claude/scripts/foo.sh"
printf '#!/bin/bash\necho vendored-copy\n' > "${SBX_T}/project/.claude/scripts/foo.sh"
git -C "${SBX_T}/project" add .claude/scripts/foo.sh
status_t="$(git -C "${SBX_T}/project" diff --cached --name-status -- .claude/scripts/foo.sh)"
case "${status_t}" in
  T*) pass "case T: git status letter is T as expected (${status_t})" ;;
  *) fail "case T: expected git status T, got: ${status_t}" ;;
esac
# Sanity: confirm the OLD filter (ACMR) really misses this — the exact
# reviewer probe reproduced, as a live regression tripwire for this suite.
acmr_only="$(git -C "${SBX_T}/project" diff --cached --name-only --diff-filter=ACMR -- '.claude/scripts/*.sh')"
if [[ -z "${acmr_only}" ]]; then
  pass "case T: --diff-filter=ACMR (pre-fix) confirmed BLIND to typechange (reviewer's probe reproduced)"
else
  fail "case T: expected ACMR to miss the typechange, got: ${acmr_only}"
fi
out_t="$(run_guard "${SBX_T}/project" "${SBX_T}/canonical")"; rc_t=$?
if [[ "${rc_t}" == 2 ]] && printf -- '%s' "${out_t}" | grep -q "foo.sh"; then
  pass "case T (symlink->real, THE round-1 gap): guard REFUSES and names foo.sh (rc=${rc_t})"
else
  fail "case T (symlink->real, THE round-1 gap): expected rc=2 naming foo.sh, got rc=${rc_t} out=${out_t}"
fi

# ── case rename: a real vendored file renamed. R was already in the
# pre-fix ACMR filter (only T was missing), so this case is not testing the
# round-1 fix — it is coverage for a letter this guard already handled,
# recorded here so "which letters are covered" is proven, not assumed.
# Whether git reports R100 or splits into A+D depends on gitconfig
# (diff.renames) and content similarity; either shape is asserted below by
# checking the guard's own output, not by asserting one specific letter. ───
SBX_R="${TMPROOT}/case-r"
mk_fixture "${SBX_R}" "bar.sh"
rm "${SBX_R}/project/.claude/scripts/bar.sh"
printf '#!/bin/bash\necho vendored-renamed\n' > "${SBX_R}/project/.claude/scripts/bar.sh"
git -C "${SBX_R}/project" add .claude/scripts/bar.sh
git -C "${SBX_R}/project" commit -q -m "accidental vendor (setup for rename case)" --no-verify
cp "${SBX_R}/canonical/plugins/leadv2/scripts/bar.sh" "${SBX_R}/canonical/plugins/leadv2/scripts/bar-renamed.sh"
git -C "${SBX_R}/project" mv .claude/scripts/bar.sh .claude/scripts/bar-renamed.sh
status_r="$(git -C "${SBX_R}/project" diff --cached --name-status -- '.claude/scripts/*.sh')"
out_r="$(run_guard "${SBX_R}/project" "${SBX_R}/canonical")"; rc_r=$?
if [[ "${rc_r}" == 2 ]] && printf -- '%s' "${out_r}" | grep -q "bar-renamed.sh"; then
  pass "case rename (real file renamed): guard REFUSES and names bar-renamed.sh (rc=${rc_r}; raw status: ${status_r//$'\n'/ | })"
else
  fail "case rename (real file renamed): expected rc=2 naming bar-renamed.sh, got rc=${rc_r} out=${out_r} status=${status_r}"
fi

# ── negative control: revert the fix (ACMRT -> ACMR) in a FULL mutant copy
# (hooks/ + a lib/ subtree, mirroring a real canonical checkout) and prove
# the SAME case T fixture above now slips through silently (rc=0, no
# output). This is the tripwire that makes this suite falsifiable: comment
# out the fix and this case MUST go red. ────────────────────────────────────
SBX_NEG="${TMPROOT}/case-negctrl"
mkdir -p "${SBX_NEG}/canonical/plugins/leadv2/hooks" "${SBX_NEG}/canonical/plugins/leadv2/scripts/lib"
MUTANT="${SBX_NEG}/canonical/plugins/leadv2/hooks/plugin-scripts-drift-guard.sh"
sed 's/--diff-filter=ACMRT/--diff-filter=ACMR/' "${GUARD}" > "${MUTANT}"
if grep -q -- '--diff-filter=ACMR ' "${MUTANT}" && ! grep -q -- '--diff-filter=ACMRT' "${MUTANT}"; then
  pass "negative control: mutant copy confirmed reverted to ACMR (fix removed)"
else
  fail "negative control: sed did not produce the expected ACMR-only mutant"
fi
bash -n "${MUTANT}" || fail "negative control: mutant fails bash -n (fixture broken)"
mkdir -p "${SBX_NEG}/project/.claude/scripts"
printf '#!/bin/bash\necho canonical\n' > "${SBX_NEG}/canonical/plugins/leadv2/scripts/foo.sh"
git init -q "${SBX_NEG}/project"
git -C "${SBX_NEG}/project" config user.email t@t.local
git -C "${SBX_NEG}/project" config user.name t
ln -s "${SBX_NEG}/canonical/plugins/leadv2/scripts/foo.sh" "${SBX_NEG}/project/.claude/scripts/foo.sh"
git -C "${SBX_NEG}/project" add .claude/scripts/foo.sh
git -C "${SBX_NEG}/project" commit -q -m "initial: symlink foo.sh"
rm "${SBX_NEG}/project/.claude/scripts/foo.sh"
printf '#!/bin/bash\necho vendored-copy\n' > "${SBX_NEG}/project/.claude/scripts/foo.sh"
git -C "${SBX_NEG}/project" add .claude/scripts/foo.sh
neg_out="$(cd "${SBX_NEG}/project" && LEADV2_CANONICAL_ROOT="${SBX_NEG}/canonical" \
  bash -c 'echo "{\"tool_input\":{\"command\":\"git commit -m test\"}}" | bash "'"${MUTANT}"'"' 2>&1)"
neg_rc=$?
if [[ "${neg_rc}" == 0 && -z "${neg_out}" ]]; then
  pass "negative control: reverted-filter mutant silently PASSES the same typechange (rc=0, no output) — confirms the fix is load-bearing"
else
  fail "negative control: expected the ACMR-only mutant to slip through silently, got rc=${neg_rc} out=${neg_out}"
fi
# ... and the SAME fixture against the real (fixed) guard must still block,
# proving this isn't a fixture-only artifact.
pos_out="$(cd "${SBX_NEG}/project" && LEADV2_CANONICAL_ROOT="${SBX_NEG}/canonical" \
  bash -c 'echo "{\"tool_input\":{\"command\":\"git commit -m test\"}}" | bash "'"${GUARD}"'"' 2>&1)"
pos_rc=$?
if [[ "${pos_rc}" == 2 ]] && printf -- '%s' "${pos_out}" | grep -q "foo.sh"; then
  pass "negative control: same fixture against the FIXED guard blocks and names foo.sh (rc=${pos_rc})"
else
  fail "negative control: fixed guard did not block the negctrl fixture, got rc=${pos_rc} out=${pos_out}"
fi

# ── true negative: an untouched symlink must never be blocked ──────────────
SBX_CLEAN="${TMPROOT}/case-clean"
mk_fixture "${SBX_CLEAN}" "foo.sh"
out_clean="$(run_guard "${SBX_CLEAN}/project" "${SBX_CLEAN}/canonical")"; rc_clean=$?
if [[ "${rc_clean}" == 0 && -z "${out_clean}" ]]; then
  pass "true negative: untouched symlink -> guard is silent, rc=0"
else
  fail "true negative: untouched symlink should be rc=0/silent, got rc=${rc_clean} out=${out_clean}"
fi

# ── --no-verify bypass must still work (documented escape hatch) ───────────
SBX_BYPASS="${TMPROOT}/case-bypass"
mk_fixture "${SBX_BYPASS}" "foo.sh"
rm "${SBX_BYPASS}/project/.claude/scripts/foo.sh"
printf '#!/bin/bash\necho vendored\n' > "${SBX_BYPASS}/project/.claude/scripts/foo.sh"
git -C "${SBX_BYPASS}/project" add .claude/scripts/foo.sh
bypass_out="$(cd "${SBX_BYPASS}/project" && LEADV2_CANONICAL_ROOT="${SBX_BYPASS}/canonical" \
  bash -c 'echo "{\"tool_input\":{\"command\":\"git commit -m test --no-verify\"}}" | bash "'"${GUARD}"'"' 2>&1)"
bypass_rc=$?
if [[ "${bypass_rc}" == 0 ]]; then
  pass "bypass: --no-verify still honored (rc=0)"
else
  fail "bypass: --no-verify should short-circuit to rc=0, got rc=${bypass_rc} out=${bypass_out}"
fi

echo "---"
if [[ ${FAIL} -eq 0 ]]; then
  echo "ALL TESTS PASSED"
  exit 0
else
  echo "TESTS FAILED"
  exit 1
fi
