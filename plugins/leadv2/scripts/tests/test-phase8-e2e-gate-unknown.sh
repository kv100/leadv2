#!/usr/bin/env bash
# tests/test-phase8-e2e-gate-unknown.sh — GATE-UNKNOWN-MUST-NOT-KILL-A-ROUND-01
#
# Defect: leadv2-phase8-e2e-gate.sh already wrote status:unknown/reason:e2e_timeout
# to e2e-gate.md on a timeout (rc==124), but then exited 1 -- the SAME code used
# for a real regression/blocked path. Its consumer, leadv2-phase8-close.sh,
# treated any non-zero exit identically ("E2E gate failed ... exit 1"),
# conflating "gate ran out of time" (unknown/inconclusive) with "gate ran and
# found a regression" (fail) and killing the round over an inconclusive result.
#
# Fix: the gate now exits 5 (distinct from every other exit-1 path in that
# script) on timeout, and leadv2-phase8-close.sh branches on exit 5 separately:
# it does NOT report a generic gate failure, it logs (not log_error) a line
# containing "gate inconclusive, work committed" verbatim, appends a resumable
# close-state.md marker, and still exits non-zero (5) so the caller knows the
# round isn't *done* -- but can tell it apart from a real dead lane.
#
# T1 — real timeout end-to-end: drives the REAL leadv2-phase8-e2e-gate.sh with
#      a fake e2e entrypoint that outlives a 1s budget -> gate exits 5,
#      e2e-gate.md has status:unknown/reason:e2e_timeout/commit:/gate: fields.
# T2 — consumer logic (extracted verbatim from leadv2-phase8-close.sh, not a
#      reimplementation) driven with a stub gate script forced to exit 5 ->
#      close-state.md written, "gate inconclusive, work committed" logged via
#      log (not log_error), overall exit 5 (not 1).
# T3 — negative control: same consumer logic, stub gate forced to exit 1 (a
#      real regression/blocked path, NOT a timeout) -> generic "E2E gate
#      failed" path still fires, exit 1 (proves T2's branch didn't swallow
#      real failures).
# T4 — mutation: flip the T1 gate's `exit 5` back to `exit 1` on the timeout
#      branch -> T1 assertion must go red; restore and re-verify green.
#
# Run: bash scripts/tests/test-phase8-e2e-gate-unknown.sh
# Exit 0 = all pass; non-zero = failures found.
set -uo pipefail
# GATE-UNKNOWN-MUST-NOT-KILL-A-ROUND-01 / lead fix: BASH_SOURCE does not exist under
# zsh, so this resolved to the caller's cwd and the suite ran against script paths
# that do not exist (five zsh runs rc=1, while the round reported "10/10 zsh green").
# Same order as the merged lib/leadv2-lane-state.sh: this file's path when bash names
# it, then $0 when it names a real file.
_t8_src="${BASH_SOURCE[0]:-}"
if [[ -z "$_t8_src" && -f "${0:-}" ]]; then _t8_src="$0"; fi
SCRIPT_DIR="$(cd "$(dirname "$_t8_src")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPTS_ROOT}/leadv2-temp.sh"

GATE_SH="${SCRIPTS_ROOT}/leadv2-phase8-e2e-gate.sh"
CLOSE_SH="${SCRIPTS_ROOT}/leadv2-phase8-close.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

if bash -n "$GATE_SH"; then pass "bash -n clean (leadv2-phase8-e2e-gate.sh)"; else fail "bash -n failed (gate)"; fi
if bash -n "$CLOSE_SH"; then pass "bash -n clean (leadv2-phase8-close.sh)"; else fail "bash -n failed (close)"; fi

TMP="$(lv2_mktemp_dir "phase8-e2e-gate-unknown-test")"; trap 'rm -rf "$TMP"' EXIT

# ── T1: real gate, real timeout ──────────────────────────────────────────────
R1="${TMP}/r1"; mkdir -p "${R1}"
git -C "${R1}" init -q
git -C "${R1}" config user.email test@test.local
git -C "${R1}" config user.name test
printf 'A\n' > "${R1}/A.txt"
git -C "${R1}" add -A && git -C "${R1}" commit -q -m init
lv2_assert_scratch_repo "${R1}"

SLEEPER="${R1}/fake-e2e.sh"
printf '%s\n' '#!/usr/bin/env bash' 'sleep 30' 'exit 0' > "${SLEEPER}"
chmod +x "${SLEEPER}"

HANDOFF1="${R1}/docs/handoff/t1sig"
mkdir -p "${HANDOFF1}"
T1_RC=0
CLAUDE_PROJECT_ROOT="${R1}" \
LEADV2_PROJECT_ROOT="${R1}" \
LEADV2_HANDOFF_DIR="${R1}/docs/handoff" \
LEADV2_E2E_CMD="bash ${SLEEPER}" \
LEADV2_PHASE8_E2E_TIMEOUT_S=1 \
LEADV2_E2E_OWNERSHIP=0 \
LEADV2_LANE_WORK_ROOT="${R1}" \
  bash "${GATE_SH}" "t1sig" >"${TMP}/t1.log" 2>&1 || T1_RC=$?
T1_MD="$(cat "${HANDOFF1}/e2e-gate.md" 2>/dev/null || true)"
T1_COMMIT="$(git -C "${R1}" rev-parse HEAD 2>/dev/null || true)"

if [[ "${T1_RC}" -eq 5 ]] && grep -q 'status: unknown' <<<"${T1_MD}" \
   && grep -q 'reason: e2e_timeout' <<<"${T1_MD}" \
   && grep -q "commit: ${T1_COMMIT}" <<<"${T1_MD}" \
   && grep -q 'gate: phase8_close' <<<"${T1_MD}"; then
  pass "T1: real timeout -> exit 5, e2e-gate.md has status/reason/commit/gate fields"
else
  fail "T1: expected exit 5 + full md fields, got rc=${T1_RC} md=<${T1_MD}> commit=${T1_COMMIT} log=<$(cat "${TMP}/t1.log")>"
fi

# ── T2/T3: extract the real consumer block from leadv2-phase8-close.sh ──────
# Extract verbatim between the two anchor comments -- proves we're testing
# the actual shipped branch, not a hand-copy that could silently diverge.
_extract_consumer_block() {
  awk '/^E2E_GATE_SCRIPT=/,/^ASSERT_SCRIPT=/' "${CLOSE_SH}" | sed '$d'
}
BLOCK="$(_extract_consumer_block)"
if [[ -z "${BLOCK}" ]]; then
  fail "extraction: could not find E2E_GATE_SCRIPT..ASSERT_SCRIPT block in leadv2-phase8-close.sh (anchors moved?)"
else
  pass "extraction: consumer block pulled verbatim from leadv2-phase8-close.sh"
fi

_run_consumer() { # <stub_gate_exit_code> <task_id>
  local stub_rc="$1" task_id="$2"
  mkdir -p "${TMP}/${task_id}"
  local stubs_dir="${TMP}/scripts-${task_id}"
  mkdir -p "${stubs_dir}"
  local stub="${stubs_dir}/leadv2-phase8-e2e-gate.sh"
  printf '%s\n' '#!/usr/bin/env bash' "exit ${stub_rc}" > "${stub}"
  chmod +x "${stub}"
  local runner="${TMP}/runner-${task_id}.sh"
  {
    echo '#!/usr/bin/env bash'
    echo 'set -uo pipefail'
    printf 'TASK_ID=%q\n' "${task_id}"
    printf 'SCRIPTS_DIR=%q\n' "${stubs_dir}"
    printf 'LEADV2_HANDOFF_DIR=%q\n' "${TMP}"
    echo 'log()       { printf -- "[%s] %s\n" "$(date "+%Y-%m-%d %H:%M:%S")" "$*" >&2; }'
    echo 'log_info()  { log "INFO: $*"; }'
    echo 'log_error() { log "ERROR: $*"; }'
    echo "${BLOCK}"
  } > "${runner}"
  chmod +x "${runner}"
  CONSUMER_RC=0
  bash "${runner}" >"${TMP}/consumer-${task_id}.log" 2>&1 || CONSUMER_RC=$?
  CONSUMER_LOG="$(cat "${TMP}/consumer-${task_id}.log")"
  CONSUMER_STATE="$(cat "${TMP}/${task_id}/close-state.md" 2>/dev/null || true)"
}

_run_consumer 5 t2sig
if [[ "${CONSUMER_RC}" -eq 5 ]] \
   && grep -q 'gate inconclusive, work committed' <<<"${CONSUMER_LOG}" \
   && ! grep -q 'ERROR: E2E gate failed' <<<"${CONSUMER_LOG}" \
   && grep -q 'status: inconclusive' <<<"${CONSUMER_STATE}" \
   && grep -q 'reason: e2e_timeout' <<<"${CONSUMER_STATE}"; then
  pass "T2: consumer branches on exit 5 -> logs 'gate inconclusive, work committed' (not log_error), writes close-state.md, exit 5"
else
  fail "T2: expected exit 5 + inconclusive marker, got rc=${CONSUMER_RC} log=<${CONSUMER_LOG}> state=<${CONSUMER_STATE}>"
fi

# ── T3: negative control -- a REAL failure (exit 1, not a timeout) must
# still take the generic failure path, proving T2's branch didn't swallow it.
_run_consumer 1 t3sig
if [[ "${CONSUMER_RC}" -eq 1 ]] \
   && grep -q 'ERROR: E2E gate failed' <<<"${CONSUMER_LOG}" \
   && ! grep -q 'gate inconclusive' <<<"${CONSUMER_LOG}"; then
  pass "T3 (negative control): a real exit-1 gate failure still takes the generic failure path, exit 1"
else
  fail "T3: expected generic failure path for exit 1, got rc=${CONSUMER_RC} log=<${CONSUMER_LOG}>"
fi

# ── T4: mutation -- flip gate's exit 5 back to exit 1 on the timeout branch,
# prove T1 goes red, then restore and re-verify green.
ANCHOR='  echo "leadv2-phase8-e2e-gate: TIMEOUT (tests/run-all.sh --scope changed exceeded ${E2E_TIMEOUT_S}s) — see ${LOG}" >&2
  tail -40 "$LOG" >&2 || true
  exit 5
fi'
MUTATED='  echo "leadv2-phase8-e2e-gate: TIMEOUT (tests/run-all.sh --scope changed exceeded ${E2E_TIMEOUT_S}s) — see ${LOG}" >&2
  tail -40 "$LOG" >&2 || true
  exit 1
fi'

if grep -qF 'exit 5' "${GATE_SH}"; then
  cp "${GATE_SH}" "${TMP}/gate-orig.sh"
  python3 - "$GATE_SH" "${TMP}/gate-orig.sh" <<'PYEOF'
import sys
path, orig = sys.argv[1], sys.argv[2]
with open(orig) as f:
    content = f.read()
anchor = '''  echo "leadv2-phase8-e2e-gate: TIMEOUT (tests/run-all.sh --scope changed exceeded ${E2E_TIMEOUT_S}s) — see ${LOG}" >&2
  tail -40 "$LOG" >&2 || true
  exit 5
fi'''
mutated = anchor.replace('exit 5', 'exit 1')
if anchor not in content:
    print("ANCHOR_NOT_FOUND")
    sys.exit(1)
mutated_content = content.replace(anchor, mutated, 1)
with open(path, 'w') as f:
    f.write(mutated_content)
PYEOF
  if [[ $? -ne 0 ]]; then
    fail "T4: mutation anchor not found -- cannot prove mutation kills the test"
  else
    if diff -q "${TMP}/gate-orig.sh" "${GATE_SH}" >/dev/null 2>&1; then
      fail "T4: mutation did not change the file (anchor matched but replace no-op)"
    else
      pass "T4: mutation applied (verified byte-diff from original)"
    fi
    M_RC=0
    CLAUDE_PROJECT_ROOT="${R1}" \
    LEADV2_PROJECT_ROOT="${R1}" \
    LEADV2_HANDOFF_DIR="${R1}/docs/handoff" \
    LEADV2_E2E_CMD="bash ${SLEEPER}" \
    LEADV2_PHASE8_E2E_TIMEOUT_S=1 \
    LEADV2_E2E_OWNERSHIP=0 \
    LEADV2_LANE_WORK_ROOT="${R1}" \
      bash "${GATE_SH}" "t1sig" >"${TMP}/t1-mutated.log" 2>&1 || M_RC=$?
    if [[ "${M_RC}" -ne 5 ]]; then
      pass "T4: mutant kills T1's assertion (mutated_rc=${M_RC}, baseline was 5) -- single-cause: only exit code changed"
    else
      fail "T4: mutant did NOT change observable behaviour (mutated_rc=${M_RC}) -- mutation is not covered"
    fi
    cp "${TMP}/gate-orig.sh" "${GATE_SH}"
    if diff -q "${TMP}/gate-orig.sh" "${GATE_SH}" >/dev/null 2>&1; then
      pass "T4: restoration verified byte-identical to original"
    else
      fail "T4: restoration failed -- gate script differs from original after restore"
    fi
    R_RC=0
    CLAUDE_PROJECT_ROOT="${R1}" \
    LEADV2_PROJECT_ROOT="${R1}" \
    LEADV2_HANDOFF_DIR="${R1}/docs/handoff" \
    LEADV2_E2E_CMD="bash ${SLEEPER}" \
    LEADV2_PHASE8_E2E_TIMEOUT_S=1 \
    LEADV2_E2E_OWNERSHIP=0 \
    LEADV2_LANE_WORK_ROOT="${R1}" \
      bash "${GATE_SH}" "t1sig" >"${TMP}/t1-restored.log" 2>&1 || R_RC=$?
    if [[ "${R_RC}" -eq 5 ]]; then
      pass "T4: restored_rc=5 matches baseline -- restoration confirmed behaviourally too"
    else
      fail "T4: restored_rc=${R_RC}, expected 5 -- restoration did not fully recover behaviour"
    fi
  fi
else
  fail "T4: 'exit 5' not found in gate script -- fix not present"
fi

# ── T5: STATE, not wording -- the inconclusive branch must exit BEFORE the
# sentinel writer runs. leadv2-phase8-assert.sh is what writes
# docs/handoff/<task>/phase8-passed.flag; every reader that decides whether a
# round is finished keys on that flag's presence. If the `exit 5` branch is ever
# moved below ASSERT_SCRIPT=, an inconclusive gate would leave a passed sentinel
# behind and the round would read as CLOSED -- which is the exact defect this
# task exists to prevent. Drop T2's message assertion and this one still holds
# the claim: resumability is a property of ordering, not of a log line.
_t5_exit5="$(grep -n '^    exit 5$' "${CLOSE_SH}" | head -1 | cut -d: -f1)"
_t5_assert="$(grep -n '^ASSERT_SCRIPT=' "${CLOSE_SH}" | head -1 | cut -d: -f1)"
if [[ -n "${_t5_exit5}" && -n "${_t5_assert}" && "${_t5_exit5}" -lt "${_t5_assert}" ]]; then
  pass "T5: inconclusive exit 5 (line ${_t5_exit5}) precedes the sentinel writer ASSERT_SCRIPT= (line ${_t5_assert}) -- no phase8-passed.flag on an inconclusive round"
else
  fail "T5: inconclusive branch does not precede the sentinel writer (exit5=${_t5_exit5:-<none>} assert=${_t5_assert:-<none>}) -- an inconclusive gate could leave a passed sentinel and the round would read as closed"
fi

printf -- '\n[TEST] %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
