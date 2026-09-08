#!/usr/bin/env bash
# tests/test-docs-only-detector-sees-commits.sh — DOCS-ONLY-DETECTOR-STAMPS-A-FALSE-PASS-01
#
# Defect: leadv2-phase8-e2e-gate.sh's _p8_diff_is_docs_only() built its
# changed-file list from `git diff --name-only HEAD` + untracked only. A lane
# that did the right thing and COMMITTED its work has a clean tree, so BOTH
# sources are empty; the vacuous for-loop then returned 0 ("every changed
# file is docs"), and the gate stamped e2e-gate-passed.flag with
# outcome=skipped reason=no_executable_change WITHOUT RUNNING ANYTHING
# (measured 2026-09-08 00:5xZ on f33ff575078f/a0b9aa86: a committed
# ~180-line Python estimator + suite skipped as "docs only"; three false
# sentinels deleted by hand that night).
#
# Fix: the detector unions a THIRD source — the committed lane range
# (git diff --name-only <merge-base main HEAD> HEAD) — and an EMPTY list is
# no longer docs-only (rc1: run the suites, never skip on a diff the gate
# could not see). The fail-closed direction is the point.
#
# T1 — committed executable change on a lane branch (clean tree, the exact
#      defect shape): the gate RUNS the e2e suite (invocation marker), the
#      sentinel is a normal pass with NO outcome:skipped — a real verdict,
#      not reason=no_executable_change.
# T2 — committed docs-only change (one new .md under docs/) on a lane
#      branch: still skips fast — sentinel outcome:skipped +
#      skip_reason:no_executable_change, entrypoint never invoked. One
#      sample each way, or the branch is not a branch.
# T3 — detector is BLIND: no resolvable merge base (main deleted) and the
#      only visible change sits under an excluded path, so the file list is
#      EMPTY. Old behaviour stamped the sentinel (docs-only) for a diff the
#      gate could not read; the empty list must return rc1, the suite RUNS
#      (marker), exits non-zero on a fake-red suite, and NO sentinel is
#      written.
# M1 — mutation control (E2E-KILLRATE-01): restore the pre-fix detector
#      body inside _p8_diff_is_docs_only (drop the merge-base source, empty
#      list vacuously docs-only again) -> T1's committed-code verdict flips
#      back to skipped (marker absent) -> suite must go red on the VERDICT.
#      (The half-revert — merge-base source dropped but the empty-list rc1
#      kept — is killed by T2: a committed docs lane would be RUN instead
#      of skipped, so outcome:skipped disappears there too.)
# M2 — mutation control: make an empty changed list return 0 (docs-only)
#      again inside the same body -> T3's unreadable lane is stamped
#      skipped without a run (sentinel exists, marker absent) -> suite must
#      go red on the sentinel. This is the dangerous direction that
#      produced three false PASSes.
#
# Run: bash scripts/tests/test-docs-only-detector-sees-commits.sh
# Exit 0 = all pass; non-zero = failures found.
# run-all-triggers: leadv2-phase8-e2e-gate

set -uo pipefail
_t_src="${BASH_SOURCE[0]:-}"
if [[ -z "$_t_src" && -f "${0:-}" ]]; then _t_src="$0"; fi
SCRIPT_DIR="$(cd "$(dirname "$_t_src")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPTS_ROOT}/leadv2-temp.sh"

GATE_SH="${SCRIPTS_ROOT}/leadv2-phase8-e2e-gate.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

if bash -n "$GATE_SH"; then pass "bash -n clean (leadv2-phase8-e2e-gate.sh)"; else fail "bash -n failed (gate)"; fi

TMP="$(lv2_mktemp_dir "docs-only-detector-sees-commits-test")"; trap 'rm -rf "$TMP"' EXIT
INVOKED_MARKER="${TMP}/e2e-invoked.txt"

# E2E stubs: RUN_RECORDER records invocation then exits 0; NEVER_RUN fails
# the test loudly if invoked; RUN_RED records invocation then exits 1.
RUN_RECORDER="${TMP}/run-recorder.sh"
printf '%s\n' '#!/usr/bin/env bash' "echo invoked >> '${INVOKED_MARKER}'" 'exit 0' > "${RUN_RECORDER}"
chmod +x "${RUN_RECORDER}"
NEVER_RUN="${TMP}/never-run.sh"
printf '%s\n' '#!/usr/bin/env bash' 'echo "NEVER_RUN was invoked" >&2' 'exit 1' > "${NEVER_RUN}"
chmod +x "${NEVER_RUN}"
RUN_RED="${TMP}/run-red.sh"
printf '%s\n' '#!/usr/bin/env bash' "echo invoked >> '${INVOKED_MARKER}'" 'echo fake-red-suite >&2' 'exit 1' > "${RUN_RED}"
chmod +x "${RUN_RED}"

# Journal stub: records append() calls so verdict lines can be asserted
# without touching the real leadv2-journal.sh (Supabase).
JOURNAL_STUB="${TMP}/journal-stub.sh"
JOURNAL_LOG="${TMP}/journal.log"
printf '%s\n' '#!/usr/bin/env bash' \
  '# usage: journal-stub.sh append <task_id> <type> <text>' \
  'shift  # drop "append"' \
  'printf "%s|%s|%s\n" "$1" "$2" "$3" >> "'"${JOURNAL_LOG}"'"' \
  > "${JOURNAL_STUB}"
chmod +x "${JOURNAL_STUB}"

# Scratch repo shaped like a lane: `main` carries the baseline commit, HEAD
# sits on branch `lane`, so the lane's work IS the committed range
# merge-base(main, lane)..lane. Branch name pinned via symbolic-ref (git
# init's default depends on user config).
_mk_lane_repo() { # <dir>
  local d="$1"
  mkdir -p "${d}"
  git -C "${d}" init -q
  git -C "${d}" symbolic-ref HEAD refs/heads/main
  git -C "${d}" config user.email test@test.local
  git -C "${d}" config user.name test
  printf 'A\n' > "${d}/A.txt"
  git -C "${d}" add -A && git -C "${d}" commit -q -m init
  git -C "${d}" checkout -q -b lane
  lv2_assert_scratch_repo "${d}"
}

# T3's fixture: N1's per-write check sees the WORKING-TREE edit of the
# declared write (it does not apply the docs/leadv2 exclude), which is what
# lets the gate reach the detector at all. Every task id run against R3
# needs its own prepass in its own handoff dir.
_write_prepass() { # <root> <task_id> <writes>
  mkdir -p "${1}/docs/handoff/${2}"
  printf 'LANE_WRITES: %s\n' "${3}" > "${1}/docs/handoff/${2}/architect-prepass.md"
}

_run_gate() { # <root> <task_id> <e2e_cmd>
  local root="$1" task_id="$2" cmd="$3"
  local handoff="${root}/docs/handoff"
  mkdir -p "${handoff}/${task_id}"
  rm -f "${INVOKED_MARKER}"
  GATE_RC=0; GATE_INVOKED=0
  CLAUDE_PROJECT_ROOT="${root}" \
  LEADV2_PROJECT_ROOT="${root}" \
  LEADV2_HANDOFF_DIR="${handoff}" \
  LEADV2_E2E_CMD="bash ${cmd}" \
  LEADV2_PHASE8_E2E_TIMEOUT_S=10 \
  LEADV2_E2E_OWNERSHIP=0 \
  LEADV2_LANE_WORK_ROOT="${root}" \
  LEADV2_JOURNAL_BIN="${JOURNAL_STUB}" \
    bash "${GATE_SH}" "${task_id}" >"${TMP}/${task_id}.log" 2>&1 || GATE_RC=$?
  GATE_LOG="$(cat "${TMP}/${task_id}.log")"
  GATE_SENTINEL="$(cat "${handoff}/${task_id}/e2e-gate-passed.flag" 2>/dev/null || true)"
  [[ -f "${INVOKED_MARKER}" ]] && GATE_INVOKED=1
}

# ── T1: committed executable change, clean tree -> real run, not skipped ───
R1="${TMP}/r1"; _mk_lane_repo "${R1}"
mkdir -p "${R1}/scripts"
printf '%s\n' '#!/usr/bin/env python3' 'def estimate(x):' '    return x * 2 + 1' > "${R1}/scripts/estimator.py"
git -C "${R1}" add -A && git -C "${R1}" commit -q -m "estimator"
_run_gate "${R1}" "t1code" "${RUN_RECORDER}"

if [[ "${GATE_RC}" -eq 0 ]] \
   && [[ "${GATE_INVOKED}" -eq 1 ]] \
   && grep -q '^e2e-gate-passed: t1code$' <<<"${GATE_SENTINEL}" \
   && ! grep -q '^outcome: skipped$' <<<"${GATE_SENTINEL}" \
   && ! grep -q 'no_executable_change' <<<"${GATE_LOG}"; then
  pass "T1: committed estimator + clean tree -> suite RAN (marker), normal pass sentinel, no no_executable_change"
else
  fail "T1: expected real run on committed code, got rc=${GATE_RC} invoked=${GATE_INVOKED} sentinel=<${GATE_SENTINEL}> log=<${GATE_LOG}>"
fi

# ── T2: committed docs-only change -> still skips fast ─────────────────────
R2="${TMP}/r2"; _mk_lane_repo "${R2}"
mkdir -p "${R2}/docs"
printf '# notes\n' > "${R2}/docs/CHANGES.md"
git -C "${R2}" add -A && git -C "${R2}" commit -q -m "notes"
_t2_start=$(date +%s)
_run_gate "${R2}" "t2docs" "${NEVER_RUN}"
_t2_elapsed=$(( $(date +%s) - _t2_start ))

if [[ "${GATE_RC}" -eq 0 ]] \
   && [[ "${GATE_INVOKED}" -eq 0 ]] \
   && grep -q '^outcome: skipped$' <<<"${GATE_SENTINEL}" \
   && grep -q '^skip_reason: no_executable_change$' <<<"${GATE_SENTINEL}" \
   && ! grep -q 'NEVER_RUN was invoked' <<<"${GATE_LOG}" \
   && [[ "${_t2_elapsed}" -lt 5 ]]; then
  pass "T2: committed .md-only lane still skips in ${_t2_elapsed}s — outcome:skipped sentinel, entrypoint never invoked"
else
  fail "T2: expected fast skip on committed docs-only lane, got rc=${GATE_RC} invoked=${GATE_INVOKED} elapsed=${_t2_elapsed}s sentinel=<${GATE_SENTINEL}> log=<${GATE_LOG}>"
fi

if grep -q 't2docs|decision|e2e_gate task=t2docs status=skipped verdict=skipped reason=no_executable_change' "${JOURNAL_LOG}" 2>/dev/null; then
  pass "T2: journal still records status=skipped verdict=skipped reason=no_executable_change"
else
  fail "T2: journal missing the skipped decision line — journal=<$(cat "${JOURNAL_LOG}" 2>/dev/null)>"
fi

# ── T3: detector blind (no merge base, change under excluded path) ─────────
# N1's empty-lane check must pass first: architect-prepass declares the
# write and its WORKING-TREE edit is visible to lv2_lane_diff_is_empty's
# per-write check (which, unlike the detector, does not apply the
# docs/leadv2 exclude). The DETECTOR excludes docs/leadv2, has no merge
# base (main deleted), and sees a clean HEAD-vs-worktree picture elsewhere
# -> its list is EMPTY and must not be docs-only.
R3="${TMP}/r3"; _mk_lane_repo "${R3}"
mkdir -p "${R3}/docs/leadv2"
printf 'kind: housekeeping\n' > "${R3}/docs/leadv2/housekeeping.yaml"
git -C "${R3}" add -A && git -C "${R3}" commit -q -m "housekeeping"
git -C "${R3}" branch -D main 2>/dev/null
printf 'extra: true\n' >> "${R3}/docs/leadv2/housekeeping.yaml"
_write_prepass "${R3}" "t3blind" "docs/leadv2/housekeeping.yaml"
_run_gate "${R3}" "t3blind" "${RUN_RED}"

if [[ "${GATE_RC}" -eq 1 ]] \
   && [[ "${GATE_INVOKED}" -eq 1 ]] \
   && [[ ! -f "${R3}/docs/handoff/t3blind/e2e-gate-passed.flag" ]] \
   && ! grep -q 'no_executable_change' <<<"${GATE_LOG}"; then
  pass "T3: empty changed list (unreadable lane) -> rc1, suite RAN, red verdict, NO sentinel stamped"
else
  fail "T3: expected run-not-skip on an unreadable (empty-list) lane, got rc=${GATE_RC} invoked=${GATE_INVOKED} sentinel_exists=$([[ -f "${R3}/docs/handoff/t3blind/e2e-gate-passed.flag" ]] && echo yes || echo no) log=<${GATE_LOG}>"
fi

if grep -q 't3blind|decision|e2e_gate task=t3blind status=ran verdict=fail' "${JOURNAL_LOG}" 2>/dev/null; then
  pass "T3: journal records a real verdict (status=ran verdict=fail) for the unreadable lane"
else
  fail "T3: journal missing the ran/fail decision line — journal=<$(cat "${JOURNAL_LOG}" 2>/dev/null)>"
fi

# ── M1: mutation control — restore the pre-fix detector body ───────────────
# Drop the merge-base (committed-range) source inside
# _p8_diff_is_docs_only's body and let an empty list fall through the
# vacuous loop to return 0 again, exactly the shipped defect. T1's verdict
# must flip real-run -> skipped.
cat > "${TMP}/m1-anchor.txt" <<'M1_ANCHOR_EOF'
  local _root="$1" _f _base
  local -a _changed
  # Same base ladder as lv2_lane_diff_is_empty: no `main` / failed
  # merge-base -> empty base -> the committed-range source is skipped and
  # the HEAD-only sources below carry the list (today's behaviour), but the
  # empty-list return below still fails closed.
  _base="$(git -C "${_root}" merge-base main HEAD 2>/dev/null)" || _base=""
  mapfile -t _changed < <(
    { if [[ -n "${_base}" ]]; then
        git -C "${_root}" diff --name-only "${_base}" HEAD -- ':(exclude)docs/leadv2' ':(exclude)docs/handoff' 2>/dev/null
      fi
      git -C "${_root}" diff --name-only HEAD -- ':(exclude)docs/leadv2' ':(exclude)docs/handoff' 2>/dev/null
      git -C "${_root}" ls-files --others --exclude-standard -- ':(exclude)docs/leadv2' ':(exclude)docs/handoff' 2>/dev/null; } | sort -u
  )
  # Empty list = this function is blind (unresolvable base and a clean
  # tree, or a lane shape it does not understand) -> rc1, NOT docs-only.
  [[ "${#_changed[@]}" -eq 0 ]] && return 1
M1_ANCHOR_EOF
cat > "${TMP}/m1-mutant.txt" <<'M1_MUTANT_EOF'
  local _root="$1" _f
  local -a _changed
  mapfile -t _changed < <(
    { git -C "${_root}" diff --name-only HEAD -- ':(exclude)docs/leadv2' ':(exclude)docs/handoff' 2>/dev/null
      git -C "${_root}" ls-files --others --exclude-standard -- ':(exclude)docs/leadv2' ':(exclude)docs/handoff' 2>/dev/null; } | sort -u
  )
M1_MUTANT_EOF
cp "${GATE_SH}" "${TMP}/gate-orig.sh"
python3 - "${GATE_SH}" "${TMP}/gate-orig.sh" "${TMP}/m1-anchor.txt" "${TMP}/m1-mutant.txt" <<'PYEOF'
import sys
path, orig, anchor_f, mutant_f = sys.argv[1:5]
anchor = open(anchor_f).read().rstrip('\n')
mutant = open(mutant_f).read().rstrip('\n')
content = open(orig).read()
if anchor not in content:
    print("ANCHOR_NOT_FOUND")
    sys.exit(1)
open(path, 'w').write(content.replace(anchor, mutant, 1))
PYEOF
if [[ $? -ne 0 ]]; then
  fail "M1: mutation anchor not found in gate body -- fix text drifted from the suite's anchor"
else
  if diff -q "${TMP}/gate-orig.sh" "${GATE_SH}" >/dev/null 2>&1; then
    fail "M1: mutation did not change the file (anchor matched but replace no-op)"
  else
    pass "M1: pre-fix body restored inside _p8_diff_is_docs_only (verified byte-diff from original)"
  fi
  _run_gate "${R1}" "t1mutA" "${RUN_RECORDER}"
  if grep -q '^outcome: skipped$' <<<"${GATE_SENTINEL}" && [[ "${GATE_INVOKED}" -eq 0 ]]; then
    pass "M1: mutant kills T1's VERDICT — committed code flipped back to skipped, suite never ran"
  else
    fail "M1: mutant did NOT flip T1's verdict (invoked=${GATE_INVOKED} sentinel=<${GATE_SENTINEL}>) — committed-range source is not covered"
  fi
  cp "${TMP}/gate-orig.sh" "${GATE_SH}"
  if diff -q "${TMP}/gate-orig.sh" "${GATE_SH}" >/dev/null 2>&1; then
    pass "M1: restoration verified byte-identical to original"
  else
    fail "M1: restoration failed -- gate script differs from original after restore"
  fi
  _run_gate "${R1}" "t1mutA2" "${RUN_RECORDER}"
  if [[ "${GATE_INVOKED}" -eq 1 ]] && ! grep -q '^outcome: skipped$' <<<"${GATE_SENTINEL}"; then
    pass "M1: restored gate re-verified green — committed code runs again"
  else
    fail "M1: restored gate did not recover the run verdict, sentinel=<${GATE_SENTINEL}>"
  fi
fi

# ── M2: mutation control — empty list is docs-only again ───────────────────
# The dangerous direction: an empty changed list returns 0, so an unreadable
# lane is stamped skipped WITHOUT a run. T3's sentinel must not exist.
if grep -qF '[[ "${#_changed[@]}" -eq 0 ]] && return 1' "${GATE_SH}"; then
  cp "${GATE_SH}" "${TMP}/gate-orig2.sh"
  sed -e 's/\[\[ "${#_changed\[@\]}" -eq 0 \]\] && return 1/[[ "${#_changed[@]}" -eq 0 ]] \&\& return 0/' \
    "${TMP}/gate-orig2.sh" > "${TMP}/gate-m2.sh"
  if [[ ! -s "${TMP}/gate-m2.sh" ]] || diff -q "${TMP}/gate-orig2.sh" "${TMP}/gate-m2.sh" >/dev/null 2>&1; then
    fail "M2: mutation did not change the file (anchor matched but sed no-op)"
  else
    cp "${TMP}/gate-m2.sh" "${GATE_SH}"
    pass "M2: empty-list fail-closed inverted inside _p8_diff_is_docs_only (return 0)"
    _write_prepass "${R3}" "t3mutB" "docs/leadv2/housekeeping.yaml"
    _run_gate "${R3}" "t3mutB" "${RUN_RED}"
    if [[ -f "${R3}/docs/handoff/t3mutB/e2e-gate-passed.flag" ]] \
       && grep -q '^outcome: skipped$' <<<"${GATE_SENTINEL}" \
       && [[ "${GATE_INVOKED}" -eq 0 ]]; then
      pass "M2: mutant kills T3 — e2e-gate-passed.flag stamped for a lane the gate could not read, suite never ran"
    else
      fail "M2: mutant did NOT stamp the false sentinel (invoked=${GATE_INVOKED} sentinel=<${GATE_SENTINEL}>) — empty-list rule is not covered"
    fi
    cp "${TMP}/gate-orig2.sh" "${GATE_SH}"
    if diff -q "${TMP}/gate-orig2.sh" "${GATE_SH}" >/dev/null 2>&1; then
      pass "M2: restoration verified byte-identical to original"
    else
      fail "M2: restoration failed -- gate script differs from original after restore"
    fi
    _write_prepass "${R3}" "t3mutB2" "docs/leadv2/housekeeping.yaml"
    _run_gate "${R3}" "t3mutB2" "${RUN_RED}"
    if [[ ! -f "${R3}/docs/handoff/t3mutB2/e2e-gate-passed.flag" ]] && [[ "${GATE_INVOKED}" -eq 1 ]]; then
      pass "M2: restored gate re-verified green — unreadable lane runs, no sentinel"
    else
      fail "M2: restored gate did not recover, sentinel=<${GATE_SENTINEL}>"
    fi
  fi
else
  fail "M2: empty-list anchor not found in gate script -- fix not present"
fi

printf -- '\n[TEST] %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
