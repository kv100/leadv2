#!/usr/bin/env bash
# test-mission-writeset.sh — DISPATCH-CLOSE-GATE-01 Mechanism 1 unit coverage for
# lib/leadv2-mission-writeset.sh (required-path extraction, LANE_WRITES coverage) and the
# leadv2-dispatch-code.sh `mission-writeset-check` CLI entry point.
#
# Negative controls (mutation-proven, see bottom): the citation-exclusion in
# leadv2_writeset_extract_required, and the coverage loop in leadv2_writeset_missing, are
# each mutated on a temp copy of the lib and the suite asserts the relevant test goes red.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${SCRIPT_DIR}/../lib/leadv2-mission-writeset.sh"
DISPATCH_SH="${SCRIPT_DIR}/../leadv2-dispatch-code.sh"
# shellcheck disable=SC1090
source "${LIB}"

PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/mission-writeset-test.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT
PROJECT_ROOT_FOR_TEST="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

# ── fixtures ──────────────────────────────────────────────────────────────────
MISSION_REFUSE="$(cat <<'EOF'
# TASK

Some intro text.

## Done means

Leave the RED logs in `docs/handoff/X/round4-red/` and the render proof at
`docs/handoff/X/render-proof.md`.
EOF
)"

MISSION_CITE_ONLY="$(cat <<'EOF'
# TASK

## Context

See the prior report at `docs/handoff/Y/report.md` for background.

## Done means

Per the render proof described in `docs/handoff/Y/report.md`, ship the fix.
EOF
)"

MISSION_INSTR="$(cat <<'EOF'
# TASK

Write the RED artifact to `docs/handoff/Z/red/run1.log` before closing.
Leave the RED logs in `docs/handoff/Z/other/`.
EOF
)"

# ── extraction: Done-means backticked paths are required ───────────────────────
req="$(leadv2_writeset_extract_required <<< "${MISSION_REFUSE}")"
printf '%s\n' "${req}" | grep -qF 'docs/handoff/X/round4-red/' \
  && pass "extract: Done-means backtick path captured" || fail "extract: round4-red missing from: ${req}"
printf '%s\n' "${req}" | grep -qF 'docs/handoff/X/render-proof.md' \
  && pass "extract: second Done-means backtick path captured" || fail "extract: render-proof missing"

# ── extraction: a cited-only path is NOT required ───────────────────────────────
req_cite="$(leadv2_writeset_extract_required <<< "${MISSION_CITE_ONLY}")"
[[ -z "${req_cite}" ]] \
  && pass "extract: citation-only path excluded (see/described in)" || fail "extract: cite leaked into required: ${req_cite}"

# ── extraction: write/leave-the-logs instructions anywhere in the mission ──────
req_instr="$(leadv2_writeset_extract_required <<< "${MISSION_INSTR}")"
printf '%s\n' "${req_instr}" | grep -qF 'docs/handoff/Z/red/run1.log' \
  && pass "extract: 'write ... to' instruction captured" || fail "extract: write-to missing: ${req_instr}"
printf '%s\n' "${req_instr}" | grep -qF 'docs/handoff/Z/other/' \
  && pass "extract: 'leave the logs in' instruction captured" || fail "extract: leave-logs missing: ${req_instr}"

# ── missing: uncovered LANE_WRITES refuses, naming the exact path ──────────────
missing="$(leadv2_writeset_missing "plugins/leadv2/scripts/foo.sh" <<< "${MISSION_REFUSE}")"
printf '%s\n' "${missing}" | grep -qF 'docs/handoff/X/round4-red/' \
  && pass "missing: uncovered path named" || fail "missing: round4-red not reported: ${missing}"

# ── missing: cited-only mission dispatches normally (nothing missing) ──────────
missing_cite="$(leadv2_writeset_missing "plugins/leadv2/scripts/foo.sh" <<< "${MISSION_CITE_ONLY}")"
[[ -z "${missing_cite}" ]] \
  && pass "missing: citation-only mission has nothing missing" || fail "missing: cite-only wrongly refused: ${missing_cite}"

# ── missing: directory-prefix coverage ──────────────────────────────────────────
missing_covered="$(leadv2_writeset_missing "docs/handoff/X/" <<< "${MISSION_REFUSE}")"
[[ -z "${missing_covered}" ]] \
  && pass "missing: directory-prefix LANE_WRITES covers nested Done-means paths" \
  || fail "missing: dir-prefix coverage failed: ${missing_covered}"

# ── missing: glob coverage ───────────────────────────────────────────────────────
missing_glob="$(leadv2_writeset_missing "docs/handoff/X/*" <<< "${MISSION_REFUSE}")"
[[ -z "${missing_glob}" ]] \
  && pass "missing: glob LANE_WRITES covers Done-means paths" || fail "missing: glob coverage failed: ${missing_glob}"

# ── suggest line ──────────────────────────────────────────────────────────────
suggested="$(printf '%s\n' "${missing}" | leadv2_writeset_suggest_line "plugins/leadv2/scripts/foo.sh")"
printf '%s' "${suggested}" | grep -qF 'LANE_WRITES: plugins/leadv2/scripts/foo.sh,docs/handoff/X/round4-red/' \
  && pass "suggest_line: appends missing paths to existing LANE_WRITES" || fail "suggest_line: got '${suggested}'"

# ── CLI: mission-writeset-check exit codes (the mission's stated Control) ──────
MFILE="${TMP}/mission-refuse.md"; printf '%s\n' "${MISSION_REFUSE}" > "${MFILE}"
out="$(bash "${DISPATCH_SH}" mission-writeset-check "${MFILE}" "plugins/leadv2/scripts/foo.sh" 2>&1)"; rc=$?
[[ ${rc} -ne 0 ]] && printf '%s' "${out}" | grep -qF 'docs/handoff/X/round4-red/' \
  && pass "CLI: refuses with exit non-zero and names the missing path" \
  || fail "CLI: refuse case rc=${rc} out=${out}"

MFILE_CITE="${TMP}/mission-cite.md"; printf '%s\n' "${MISSION_CITE_ONLY}" > "${MFILE_CITE}"
out2="$(bash "${DISPATCH_SH}" mission-writeset-check "${MFILE_CITE}" "plugins/leadv2/scripts/foo.sh" 2>&1)"; rc2=$?
[[ ${rc2} -eq 0 ]] \
  && pass "CLI: a citation-only mission dispatches normally (exit 0)" || fail "CLI: cite-only case rc=${rc2} out=${out2}"

# C1: consumer repositories install this entrypoint as a single-file symlink. The
# symlink directory intentionally has no lib/ sibling; canonical fallback must load both
# new libraries before the real CLI can start.
CONSUMER_SCRIPTS="${TMP}/consumer/.claude/scripts"
mkdir -p "${CONSUMER_SCRIPTS}"
ln -s "${DISPATCH_SH}" "${CONSUMER_SCRIPTS}/leadv2-dispatch-code.sh"
consumer_out="$(cd "${TMP}/consumer" && LEADV2_CANONICAL_ROOT="${PROJECT_ROOT_FOR_TEST}" bash ".claude/scripts/leadv2-dispatch-code.sh" mission-writeset-check "${MFILE_CITE}" "plugins/leadv2/scripts/foo.sh" 2>&1)"; consumer_rc=$?
[[ ${consumer_rc} -eq 0 ]] \
  && pass "C1: per-file consumer symlink starts with canonical mission/red-proof libraries" \
  || fail "C1: consumer symlink startup failed rc=${consumer_rc} out=${consumer_out}"

# C4: extraction precision remains below the enable-by-default bar, so the production
# rollout is intentionally opt-in. This reads the dispatcher's live effective default.
default_out="$(LEADV2_DISPATCH_SOURCE_ONLY=1 PROJECT_ROOT="${PROJECT_ROOT_FOR_TEST}" bash -c 'source "$1"; printf "%s" "$REQUIRE_MISSION_WRITESET"' _ "${DISPATCH_SH}" 2>&1)"; default_rc=$?
[[ ${default_rc} -eq 0 && "${default_out}" == "0" ]] \
  && pass "C4: mission writeset enforcement defaults to opt-in (0)" \
  || fail "C4: expected default 0 rc=${default_rc} out=${default_out}"

# ── C1 wiring control: architect_prepass itself, not just the lib/CLI, must refuse ──────
# DISPATCH-CLOSE-GATE-01 review round 1, C1: deleting all three `_mission_writeset_guard`
# call sites in architect_prepass left this suite green (pass=14 fail=0) because every
# assertion above only exercises the lib functions and the standalone CLI subcommand,
# neither of which is on the live dispatch path. This drives architect_prepass itself
# (LEADV2_DISPATCH_SOURCE_ONLY=1 lets the dispatcher be sourced instead of run as a CLI)
# with a mission that names a path outside LANE_WRITES, on the kill-switch branch
# (ARCHITECT_GATE=0) which is the cheapest real call site to exercise end-to-end.
_run_prepass_refusal() { # <dispatch_script_path> -> stdout=combined output; exit=architect_prepass rc
  local dsh="$1"
  LEADV2_DISPATCH_SOURCE_ONLY=1 LEADV2_REQUIRE_MISSION_WRITESET=1 PROJECT_ROOT="${PROJECT_ROOT_FOR_TEST}" \
  CLAUDE_PROJECT_ROOT="${PROJECT_ROOT_FOR_TEST}" \
  bash -c '
    set -uo pipefail
    # shellcheck disable=SC1090
    source "$1"
    export ARCHITECT_GATE=0
    architect_prepass "$2" "wiretest8" "plugins/leadv2/scripts/foo.sh"
    exit $?
  ' _ "${dsh}" "${MISSION_REFUSE}" 2>&1
  return $?
}
wire_out="$(_run_prepass_refusal "${DISPATCH_SH}")"; wire_rc=$?
[[ ${wire_rc} -ne 0 ]] && printf '%s' "${wire_out}" | grep -qF 'mission_writeset_refused' \
  && pass "wiring: architect_prepass itself refuses a non-covering mission" \
  || fail "wiring: architect_prepass rc=${wire_rc} out=${wire_out}"

# ── real on-disk specimens (C2/C3): the fixtures ARE the test, not a hand-fitted string ──
SPECIMEN_DIR="${SCRIPT_DIR}/../../../../docs/handoff/DISPATCH-CLOSE-GATE-01/specimens"
R4="${SPECIMEN_DIR}/fix-round-4.md"
R5="${SPECIMEN_DIR}/fix-round-5.md"

if [[ -f "${R4}" ]]; then
  out_r4="$(bash "${DISPATCH_SH}" mission-writeset-check "${R4}" 2>&1)"; rc_r4=$?
  [[ ${rc_r4} -eq 0 ]] \
    && pass "specimen: fix-round-4.md (real corrected mission) dispatches normally" \
    || fail "specimen: fix-round-4.md wrongly refused rc=${rc_r4} out=${out_r4}"
else
  fail "specimen: docs/handoff/DISPATCH-CLOSE-GATE-01/specimens/fix-round-4.md not found"
fi

if [[ -f "${R5}" ]]; then
  # Reconstructed pre-correction write set: the real round-5 LANE_WRITES minus
  # `lib/leadv2-lane-guard.sh`, which the "Write set note (corrected)" paragraph in the
  # SAME on-disk file says was omitted from the first dispatch. The mission body is
  # untouched -- only the declared csv is rolled back, exactly what the first dispatch saw.
  PRECORRECTION_CSV="plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/leadv2-dispatch-ledger.sh,plugins/leadv2/scripts/leadv2-dispatch-product-close.sh,plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh,plugins/leadv2/scripts/tests/test-close-chain.sh,plugins/leadv2/scripts/tests/test-t13-slice1.sh,plugins/leadv2/scripts/tests/test-scope-gate-orchestration-dirt.sh,plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh,plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh,tests/run-all.sh,.gitignore"
  out_r5="$(bash "${DISPATCH_SH}" mission-writeset-check "${R5}" "${PRECORRECTION_CSV}" 2>&1)"; rc_r5=$?
  [[ ${rc_r5} -ne 0 ]] && printf '%s' "${out_r5}" | grep -qF 'lib/leadv2-lane-guard.sh' \
    && pass "specimen: pre-correction fix-round-5.md refused, names lib/leadv2-lane-guard.sh" \
    || fail "specimen: pre-correction fix-round-5.md rc=${rc_r5} out=${out_r5}"
else
  fail "specimen: docs/handoff/DISPATCH-CLOSE-GATE-01/specimens/fix-round-5.md not found"
fi

printf 'SUMMARY: pass=%s fail=%s\n' "${PASS}" "${FAIL}"
(( FAIL == 0 ))
