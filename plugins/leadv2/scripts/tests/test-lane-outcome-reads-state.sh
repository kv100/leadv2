#!/usr/bin/env bash
# test-lane-outcome-reads-state.sh —
# LANE-OUTCOME-CLASSIFIES-BY-WORDING-NOT-STATE-01
#
# Covers what test-lane-outcome.sh does NOT: (1) a recorded gate verdict
# outranks every other signal, (2) the wording probe is a last resort that
# can never flip a real work-delta, (3) an undeterminable work state comes
# out as "unknown", never silently downgraded to "died-clean"/"respawn".
#
# No network, no real `claude` invocation -- every scenario builds a fixture
# run_dir by hand plus a throwaway local git repo. Never touches prod run
# dirs. Self-selects via tests/run-all.sh's "a changed test suite selects
# itself" rule (matches plugins/leadv2/scripts/tests/test-*.sh).
set -u
set +e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLASSIFIER="${SCRIPT_DIR}/../leadv2-lane-outcome.sh"
PARKED_LIB="${SCRIPT_DIR}/../lib/leadv2-parked-detect.sh"
THIS_TEST="${SCRIPT_DIR}/test-lane-outcome-reads-state.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

FAILURES=0
PASSES=0
pass() { printf 'PASS: %s\n' "$1"; PASSES=$((PASSES + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAILURES=$((FAILURES + 1)); }

_new_run_dir() { # -> path
  local d
  d="$(mktemp -d "${TMP_ROOT}/run-XXXXXX")"
  printf 'run_id: %s\n' "$(basename "${d}")" > "${d}/meta.yaml"
  echo "${d}"
}

_new_repo() { # -> path, a real one-commit git repo with a remote-tracking branch
  local d
  d="$(mktemp -d "${TMP_ROOT}/repo-XXXXXX")"
  git -C "${d}" init -q
  git -C "${d}" config user.email test@test.com
  git -C "${d}" config user.name test
  echo "one" > "${d}/file.txt"
  git -C "${d}" add file.txt
  git -C "${d}" commit -q -m init
  # Give it an @{u} so the ahead-commits probe has something to compare against.
  git -C "${d}" branch -q upstream
  git -C "${d}" branch -q --set-upstream-to=upstream 2>/dev/null || true
  echo "${d}"
}

_assert_outcome() { # <run_dir> <case> <expect_outcome> [expect_next]
  local run_dir="$1" case_name="$2" expect_outcome="$3" expect_next="${4:-}"
  local got_outcome got_next
  got_outcome="$(grep '^outcome=' "${run_dir}/.outcome" 2>/dev/null | head -1 | cut -d= -f2-)"
  got_next="$(grep '^next=' "${run_dir}/.outcome" 2>/dev/null | head -1 | cut -d= -f2-)"
  if [[ "${got_outcome}" != "${expect_outcome}" ]]; then
    fail "${case_name}" "outcome=${got_outcome}, expected ${expect_outcome}"
    return 1
  fi
  if [[ -n "${expect_next}" && "${got_next}" != "${expect_next}" ]]; then
    fail "${case_name}" "next=${got_next}, expected ${expect_next}"
    return 1
  fi
  pass "${case_name}"
  return 0
}

# ---------------------------------------------------------------------------
# case_bash_n
# ---------------------------------------------------------------------------
if bash -n "${CLASSIFIER}" && bash -n "${PARKED_LIB}" && bash -n "${THIS_TEST}"; then
  pass "case_bash_n"
else
  fail "case_bash_n" "syntax error in classifier, parked-detect lib, or this suite"
fi

# ---------------------------------------------------------------------------
# case_verdict_outranks_bound — a recorded .gate-verdict wins even though the
# raw bound/work signals would independently compute a DIFFERENT outcome
# (bound=max_turns + real work would normally be died-with-work).
# ---------------------------------------------------------------------------
run_dir="$(_new_run_dir)"
REPO_DIR="$(_new_repo)"
printf 'run_id: %s\ncwd: %s\n' "$(basename "${run_dir}")" "${REPO_DIR}" >> /dev/null
{ printf 'run_id: %s\n' "$(basename "${run_dir}")"; printf 'cwd: %s\n' "${REPO_DIR}"; } > "${run_dir}/meta.yaml"
echo "dirty" >> "${REPO_DIR}/file.txt"
echo max_turns > "${run_dir}/.bound_reason"
printf 'outcome=completed\n' > "${run_dir}/.gate-verdict"
"${CLASSIFIER}" "${run_dir}" 124 yes >/dev/null || true
_assert_outcome "${run_dir}" "case_verdict_outranks_bound" "completed" "none"

# ---------------------------------------------------------------------------
# case_work_yes_never_downgraded_by_wording — bound=none, exit=0, real work
# on disk (work_delta=yes passed explicitly), worker's last message is
# textbook "parked" prose, AND the contradictory .deliverable/.no-deliverable
# marker pair is present. State (work=yes) must win over wording: the
# classifier must NOT report "parked" here.
# ---------------------------------------------------------------------------
run_dir="$(_new_run_dir)"
{ printf 'run_id: %s\n' "$(basename "${run_dir}")"; } > "${run_dir}/meta.yaml"
printf 'Status update.\nStanding by, waiting for the other lane to finish.\n' > "${run_dir}/result.md"
: > "${run_dir}/.deliverable"
: > "${run_dir}/.no-deliverable"
"${CLASSIFIER}" "${run_dir}" 0 yes >/dev/null || true
got="$(grep '^outcome=' "${run_dir}/.outcome" | head -1 | cut -d= -f2-)"
if [[ "${got}" == "parked" ]]; then
  fail "case_work_yes_never_downgraded_by_wording" "wording overrode work=yes state -> parked"
else
  pass "case_work_yes_never_downgraded_by_wording (got ${got})"
fi

# ---------------------------------------------------------------------------
# case_undetermined_work_is_unknown_not_died_clean — no cwd on record at
# all (meta.yaml has no cwd key), non-bound nonzero exit. The work probe
# CANNOT run; the old behaviour defaulted this straight to died-clean/
# respawn, throwing away any work that might exist. Must be "unknown"/none.
# ---------------------------------------------------------------------------
run_dir="$(_new_run_dir)"
"${CLASSIFIER}" "${run_dir}" 1 >/dev/null || true
_assert_outcome "${run_dir}" "case_undetermined_work_is_unknown_not_died_clean" "unknown" "none"

# ---------------------------------------------------------------------------
# case_unknown_work_never_auto_respawns — same fixture, explicit check that
# next= is never "respawn" for an unknown outcome (that IS the disk-wins
# guarantee: an undetermined lane cannot be silently thrown away).
# ---------------------------------------------------------------------------
run_dir="$(_new_run_dir)"
"${CLASSIFIER}" "${run_dir}" 1 >/dev/null || true
got_next="$(grep '^next=' "${run_dir}/.outcome" | head -1 | cut -d= -f2-)"
if [[ "${got_next}" == "respawn" ]]; then
  fail "case_unknown_work_never_auto_respawns" "next=respawn for an undetermined lane"
else
  pass "case_unknown_work_never_auto_respawns (next=${got_next})"
fi

# ---------------------------------------------------------------------------
# case_bound_with_real_work_still_died_with_work — control: the ordinary
# died-with-work path (bound hit + real work delta) must still work exactly
# as before this change (no verdict file, no wording involved).
# ---------------------------------------------------------------------------
run_dir="$(_new_run_dir)"
{ printf 'run_id: %s\n' "$(basename "${run_dir}")"; } > "${run_dir}/meta.yaml"
echo max_turns > "${run_dir}/.bound_reason"
"${CLASSIFIER}" "${run_dir}" 124 yes >/dev/null || true
_assert_outcome "${run_dir}" "case_bound_with_real_work_still_died_with_work" "died-with-work" "continue"

# ---------------------------------------------------------------------------
# case_e2e_real_work_never_died_clean — MANDATORY end-to-end control (brief
# §3): worker exited nonzero (a real failure, not a bound hit), the
# worktree has real uncommitted work AND the worker's own last message is
# textbook "died clean" prose ("no further action until it finishes").
# Disk must win: outcome must never be died-clean.
# ---------------------------------------------------------------------------
run_dir="$(_new_run_dir)"
REPO_DIR2="$(_new_repo)"
{ printf 'run_id: %s\n' "$(basename "${run_dir}")"; printf 'cwd: %s\n' "${REPO_DIR2}"; } > "${run_dir}/meta.yaml"
echo "real uncommitted change" >> "${REPO_DIR2}/file.txt"
printf 'Wrapping up.\nNo further action until it finishes.\n' > "${run_dir}/result.md"
"${CLASSIFIER}" "${run_dir}" 1 yes >/dev/null || true
got="$(grep '^outcome=' "${run_dir}/.outcome" | head -1 | cut -d= -f2-)"
if [[ "${got}" == "died-clean" ]]; then
  fail "case_e2e_real_work_never_died_clean" "prose won over disk -- outcome=died-clean with real work on disk"
else
  pass "case_e2e_real_work_never_died_clean (got ${got})"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\ntest-lane-outcome-reads-state: %d passed, %d failed\n' "${PASSES}" "${FAILURES}"
if [[ "${FAILURES}" -ne 0 ]]; then
  exit 1
fi
