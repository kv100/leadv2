#!/usr/bin/env bash
# tests/test-phase8-e2e-gate-docs-only-skip.sh — E2E-GATE-TIMES-OUT-ON-DOCS-ONLY-DIAGNOSTICS-01
#
# Defect: leadv2-phase8-e2e-gate.sh carries a 900s budget sized for a real
# product change. A docs-only diagnostic lane (one new .md, zero code) has
# nothing for the gate to exercise, and still paid the full budget before
# timing out (rc=124) -- a FALSE RED on a lane whose work was fine. The gate
# only ever had two outcomes, pass and fail/timeout; both are dishonest for a
# diff with no executable change.
#
# Fix: leadv2-phase8-e2e-gate.sh now decides applicability from the actual
# diff (via _p8_diff_is_docs_only(), excluding docs/leadv2 and docs/handoff
# the same way lv2_lane_diff_is_empty / GATE-FOREIGN-FAILURE-01 already do),
# BEFORE resolving/running the e2e entrypoint. A diff whose every changed
# file is *.md or under docs/ writes the sentinel with a THIRD, distinct
# outcome (`outcome: skipped`, `skip_reason: no_executable_change`) and exits
# 0 in seconds -- never `pass` (no suite ran) and never the rc=124 timeout
# path. A diff with any executable file still runs the full gate under its
# normal budget, unaffected.
#
# T1 — real gate, docs-only diff (new file under docs/): fast exit 0,
#      sentinel carries outcome:skipped + skip_reason:no_executable_change,
#      no e2e entrypoint ever invoked (LEADV2_E2E_CMD points at a script that
#      would fail the test if executed), journal stub records
#      status=skipped verdict=skipped.
# T2 — real gate, executable diff (new .sh file): the full suite still runs
#      under LEADV2_E2E_CMD (a fast fake) -> normal PASS, sentinel has NO
#      outcome:skipped field. Proves the applicability check does not
#      swallow real product changes.
# T3 — mutation (negative control, E2E-KILLRATE-01): invert
#      _p8_diff_is_docs_only's return codes in a scratch copy of the gate so
#      the docs-only case returns pass instead of skipped -> T1's own
#      assertion (sentinel has outcome:skipped) must go red, proving the
#      control actually depends on the code path it claims to cover.
#
# Run: bash scripts/tests/test-phase8-e2e-gate-docs-only-skip.sh
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

TMP="$(lv2_mktemp_dir "phase8-e2e-gate-docs-only-skip-test")"; trap 'rm -rf "$TMP"' EXIT

# A command that would fail the run loudly if the gate ever invoked it --
# T1 asserts the gate never gets this far for a docs-only diff.
NEVER_RUN="${TMP}/never-run.sh"
printf '%s\n' '#!/usr/bin/env bash' 'echo "NEVER_RUN was invoked" >&2' 'exit 1' > "${NEVER_RUN}"
chmod +x "${NEVER_RUN}"

# A fast, real-exiting fake e2e suite for the executable-diff case (T2).
FAST_PASS="${TMP}/fast-pass.sh"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "${FAST_PASS}"
chmod +x "${FAST_PASS}"

# Journal stub: records every append() call so we can assert on the
# decision line without touching the real leadv2-journal.sh (Supabase).
JOURNAL_STUB="${TMP}/journal-stub.sh"
JOURNAL_LOG="${TMP}/journal.log"
printf '%s\n' '#!/usr/bin/env bash' \
  '# usage: journal-stub.sh append <task_id> <type> <text>' \
  'shift  # drop "append"' \
  'printf "%s|%s|%s\n" "$1" "$2" "$3" >> "'"${JOURNAL_LOG}"'"' \
  > "${JOURNAL_STUB}"
chmod +x "${JOURNAL_STUB}"

_mk_scratch_repo() { # <dir>
  local d="$1"
  mkdir -p "${d}"
  git -C "${d}" init -q
  git -C "${d}" config user.email test@test.local
  git -C "${d}" config user.name test
  printf 'A\n' > "${d}/A.txt"
  git -C "${d}" add -A && git -C "${d}" commit -q -m init
  lv2_assert_scratch_repo "${d}"
}

_run_gate() { # <root> <task_id> <e2e_cmd>
  local root="$1" task_id="$2" cmd="$3"
  local handoff="${root}/docs/handoff"
  mkdir -p "${handoff}/${task_id}"
  GATE_RC=0
  CLAUDE_PROJECT_ROOT="${root}" \
  LEADV2_PROJECT_ROOT="${root}" \
  LEADV2_HANDOFF_DIR="${handoff}" \
  LEADV2_E2E_CMD="bash ${cmd}" \
  LEADV2_PHASE8_E2E_TIMEOUT_S=5 \
  LEADV2_E2E_OWNERSHIP=0 \
  LEADV2_LANE_WORK_ROOT="${root}" \
  LEADV2_JOURNAL_BIN="${JOURNAL_STUB}" \
    bash "${GATE_SH}" "${task_id}" >"${TMP}/${task_id}.log" 2>&1 || GATE_RC=$?
  GATE_LOG="$(cat "${TMP}/${task_id}.log")"
  GATE_SENTINEL="$(cat "${handoff}/${task_id}/e2e-gate-passed.flag" 2>/dev/null || true)"
}

# ── T1: docs-only diff -- skipped, fast, sentinel + journal say so ─────────
R1="${TMP}/r1"; _mk_scratch_repo "${R1}"
mkdir -p "${R1}/docs"
printf '# notes\n' > "${R1}/docs/CHANGES.md"

_t1_start=$(date +%s)
_run_gate "${R1}" "t1docs" "${NEVER_RUN}"
_t1_elapsed=$(( $(date +%s) - _t1_start ))

if [[ "${GATE_RC}" -eq 0 ]] \
   && grep -q '^outcome: skipped$' <<<"${GATE_SENTINEL}" \
   && grep -q '^skip_reason: no_executable_change$' <<<"${GATE_SENTINEL}" \
   && ! grep -q 'NEVER_RUN was invoked' <<<"${GATE_LOG}" \
   && [[ "${_t1_elapsed}" -lt 5 ]]; then
  pass "T1: docs-only diff -> exit 0, sentinel outcome:skipped/skip_reason:no_executable_change, e2e entrypoint never invoked, finished in ${_t1_elapsed}s"
else
  fail "T1: expected fast skip, got rc=${GATE_RC} elapsed=${_t1_elapsed}s sentinel=<${GATE_SENTINEL}> log=<${GATE_LOG}>"
fi

if grep -q 't1docs|decision|e2e_gate task=t1docs status=skipped verdict=skipped reason=no_executable_change' "${JOURNAL_LOG}" 2>/dev/null; then
  pass "T1: journal records status=skipped verdict=skipped reason=no_executable_change (distinct from pass/timeout)"
else
  fail "T1: journal missing the skipped decision line — journal=<$(cat "${JOURNAL_LOG}" 2>/dev/null)>"
fi

# ── T2: executable diff -- gate still runs the full suite, normal PASS ─────
R2="${TMP}/r2"; _mk_scratch_repo "${R2}"
mkdir -p "${R2}/scripts"
printf '%s\n' '#!/usr/bin/env bash' 'echo hi' > "${R2}/scripts/newthing.sh"

_run_gate "${R2}" "t2code" "${FAST_PASS}"

if [[ "${GATE_RC}" -eq 0 ]] \
   && grep -q '^e2e-gate-passed: t2code$' <<<"${GATE_SENTINEL}" \
   && ! grep -q 'outcome: skipped' <<<"${GATE_SENTINEL}"; then
  pass "T2: executable diff -> normal PASS (sentinel has no outcome:skipped) -- applicability check does not swallow real changes"
else
  fail "T2: expected normal pass, got rc=${GATE_RC} sentinel=<${GATE_SENTINEL}> log=<${GATE_LOG}>"
fi

# ── T3: mutation (negative control) -- invert the docs-only verdict ────────
# Inside the applicability function body, flip its two return codes so a
# docs-only diff falls through to "run the suite" (i.e. behaves like a
# normal, non-skipped pass) instead of the skipped branch. T1's own
# assertion (sentinel outcome:skipped) must go red.
ANCHOR_A='    if [[ "${_f}" != *.md && "${_f}" != docs/* ]]; then
      return 1
    fi
  done
  return 0
}'
if grep -qF "${ANCHOR_A}" "${GATE_SH}"; then
  cp "${GATE_SH}" "${TMP}/gate-orig.sh"
  python3 - "$GATE_SH" "${TMP}/gate-orig.sh" <<'PYEOF'
import sys
path, orig = sys.argv[1], sys.argv[2]
with open(orig) as f:
    content = f.read()
anchor = '''    if [[ "${_f}" != *.md && "${_f}" != docs/* ]]; then
      return 1
    fi
  done
  return 0
}'''
# Invert: docs-only diffs now return 1 (not-docs-only) -> gate falls
# through to run the real e2e entrypoint instead of skipping. The mutation
# lives INSIDE the function body, not a top-level insert.
mutated = '''    if [[ "${_f}" != *.md && "${_f}" != docs/* ]]; then
      return 1
    fi
  done
  return 1
}'''
if anchor not in content:
    print("ANCHOR_NOT_FOUND")
    sys.exit(1)
mutated_content = content.replace(anchor, mutated, 1)
with open(path, 'w') as f:
    f.write(mutated_content)
PYEOF
  if [[ $? -ne 0 ]]; then
    fail "T3: mutation anchor not found -- cannot prove mutation kills the test"
  else
    if diff -q "${TMP}/gate-orig.sh" "${GATE_SH}" >/dev/null 2>&1; then
      fail "T3: mutation did not change the file (anchor matched but replace no-op)"
    else
      pass "T3: mutation applied (verified byte-diff from original)"
    fi
    _run_gate "${R1}" "t1docs-mutant" "${NEVER_RUN}"
    if ! grep -q '^outcome: skipped$' <<<"${GATE_SENTINEL}"; then
      pass "T3: mutant kills T1's assertion (mutated sentinel has no outcome:skipped) -- docs-only case no longer distinguishable from a real run"
    else
      fail "T3: mutant did NOT change observable behaviour (sentinel still shows outcome:skipped) -- mutation is not covered"
    fi
    cp "${TMP}/gate-orig.sh" "${GATE_SH}"
    if diff -q "${TMP}/gate-orig.sh" "${GATE_SH}" >/dev/null 2>&1; then
      pass "T3: restoration verified byte-identical to original"
    else
      fail "T3: restoration failed -- gate script differs from original after restore"
    fi
    _run_gate "${R1}" "t1docs-restored" "${NEVER_RUN}"
    if grep -q '^outcome: skipped$' <<<"${GATE_SENTINEL}"; then
      pass "T3: restored gate re-verified green -- outcome:skipped is back"
    else
      fail "T3: restored gate did not recover skipped behaviour, sentinel=<${GATE_SENTINEL}>"
    fi
  fi
else
  fail "T3: applicability anchor not found in gate script -- fix not present"
fi

printf -- '\n[TEST] %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
